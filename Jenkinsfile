pipeline {
    agent any

    environment {
        APP_NAME         = 'reactrepo'
        GITHUB_REPO      = 'santhoshs-ccl/reactrepo'
        MCP_SERVER_URL   = 'http://localhost:8765'
        DEPLOY_ENV       = "${env.BRANCH_NAME == 'main' ? 'production' : 'staging'}"
        SLACK_CHANNEL    = '#deployments'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
        timestamps()
    }

    triggers {
        githubPush()
    }

    stages {

        // ─────────────────────────────────────────────
        // STAGE 0 — MCP: notify pipeline started
        // ─────────────────────────────────────────────
        stage('MCP: Pipeline Start') {
            steps {
                script {
                    mcpNotify(
                        event   : 'pipeline.started',
                        branch  : env.BRANCH_NAME,
                        build   : env.BUILD_NUMBER,
                        commit  : env.GIT_COMMIT?.take(7)
                    )
                }
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 1 — Checkout
        // ─────────────────────────────────────────────
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_MSG = sh(
                        script: 'git log -1 --pretty=%B',
                        returnStdout: true
                    ).trim()
                    env.GIT_AUTHOR = sh(
                        script: 'git log -1 --pretty=%an',
                        returnStdout: true
                    ).trim()
                    echo "Commit by ${env.GIT_AUTHOR}: ${env.GIT_COMMIT_MSG}"
                }
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 2 — Build
        // ─────────────────────────────────────────────
        stage('Build') {
            steps {
                script {
                    mcpNotify(event: 'stage.started', stage: 'Build')
                }
                sh '''
                    echo "==> Installing Node dependencies"
                    npm ci

                    echo "==> Building React app"
                    npm run build
                '''
            }
            post {
                failure {
                    script { mcpNotify(event: 'stage.failed', stage: 'Build') }
                }
                success {
                    script { mcpNotify(event: 'stage.passed', stage: 'Build') }
                }
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 3 — Test
        // ─────────────────────────────────────────────
        stage('Test') {
            steps {
                sh '''
                    echo "==> Running tests"
                    npm test -- --ci --reporters=default --reporters=jest-junit
                '''
            }
            post {
                always {
                    junit allowEmptyResults: true,
                          testResults: 'junit.xml'
                }
                failure {
                    script { mcpNotify(event: 'stage.failed', stage: 'Test') }
                }
                success {
                    script { mcpNotify(event: 'stage.passed', stage: 'Test') }
                }
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 4 — Security scan
        // ─────────────────────────────────────────────
        stage('Security Scan') {
            steps {
                sh '''
                    echo "==> Checking for known vulnerabilities"
                    npm audit --audit-level=high || true
                '''
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 5 — Deploy
        // ─────────────────────────────────────────────
        stage('Deploy') {
            when {
                anyOf { branch 'main'; branch 'staging' }
            }
            steps {
                script {
                    mcpNotify(event: 'stage.started', stage: "Deploy:${env.DEPLOY_ENV}")
                }
                withCredentials([
                    sshUserPrivateKey(
                        credentialsId: 'ccl-deploy-key',
                        keyFileVariable: 'SSH_KEY'
                    ),
                    string(
                        credentialsId: 'ccl-deploy-host',
                        variable: 'DEPLOY_HOST'
                    )
                ]) {
                    sh '''
                        echo "==> Deploying to ${DEPLOY_ENV}"
                        chmod 600 $SSH_KEY

                        echo "==> Copying build output to server"
                        scp -i $SSH_KEY -o StrictHostKeyChecking=no -r build/* \
                            deployer@$DEPLOY_HOST:/var/www/${APP_NAME}/

                        echo "==> Restarting web server"
                        ssh -i $SSH_KEY -o StrictHostKeyChecking=no \
                            deployer@$DEPLOY_HOST \
                            "sudo systemctl reload nginx && echo 'Deploy complete'"
                    '''
                }
            }
            post {
                failure {
                    script { mcpNotify(event: 'deploy.failed', env: env.DEPLOY_ENV) }
                }
                success {
                    script { mcpNotify(event: 'deploy.success', env: env.DEPLOY_ENV) }
                }
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 6 — Smoke Test
        // ─────────────────────────────────────────────
        stage('Smoke Test') {
            when {
                anyOf { branch 'main'; branch 'staging' }
            }
            steps {
                script {
                    def targetUrl = env.DEPLOY_ENV == 'production'
                        ? 'http://localhost:3000'
                        : 'http://localhost:3001'

                    sh """
                        echo "==> Smoke testing ${targetUrl}"
                        STATUS=\$(curl -s -o /dev/null -w "%{http_code}" ${targetUrl})
                        if [ "\$STATUS" != "200" ]; then
                            echo "SMOKE TEST FAILED — HTTP \$STATUS"
                            exit 1
                        fi
                        echo "Smoke test passed — HTTP \$STATUS"
                    """

                    mcpTool(
                        tool   : 'validate_deployment',
                        payload: [url: targetUrl, env: env.DEPLOY_ENV]
                    )
                }
            }
        }

    } // end stages

    // ─────────────────────────────────────────────
    // POST — pipeline-level notifications
    // ─────────────────────────────────────────────
    post {
        success {
            script {
                mcpNotify(
                    event  : 'pipeline.success',
                    branch : env.BRANCH_NAME,
                    build  : env.BUILD_NUMBER,
                    env    : env.DEPLOY_ENV
                )
            }
        }
        failure {
            script {
                mcpNotify(
                    event  : 'pipeline.failed',
                    branch : env.BRANCH_NAME,
                    build  : env.BUILD_NUMBER,
                    env    : env.DEPLOY_ENV
                )
            }
        }
        always {
            cleanWs()
        }
    }
}

// ─────────────────────────────────────────────────────────
// Shared helpers (inline — move to shared library later)
// ─────────────────────────────────────────────────────────

def mcpNotify(Map args) {
    try {
        def payload = groovy.json.JsonOutput.toJson(args)
        sh """
            curl -s -X POST ${MCP_SERVER_URL}/notify \
              -H 'Content-Type: application/json' \
              -d '${payload}' || true
        """
    } catch (e) {
        echo "MCP notify warning: ${e.message}"
    }
}

def mcpTool(Map args) {
    try {
        def payload = groovy.json.JsonOutput.toJson(args.payload)
        def result = sh(
            script: """
                curl -s -X POST ${MCP_SERVER_URL}/tool/${args.tool} \
                  -H 'Content-Type: application/json' \
                  -d '${payload}'
            """,
            returnStdout: true
        ).trim()
        return result
    } catch (e) {
        echo "MCP tool warning: ${e.message}"
        return ''
    }
}
