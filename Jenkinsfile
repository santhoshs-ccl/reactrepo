pipeline {
    agent any

    environment {
        APP_NAME       = 'reactrepo'
        MCP_SERVER_URL = 'http://localhost:8765'
        DEPLOY_ENV     = "${env.BRANCH_NAME == 'main' ? 'production' : 'staging'}"
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 20, unit: 'MINUTES')
        disableConcurrentBuilds()
        timestamps()
        ansiColor('xterm')
    }

    triggers {
        pollSCM('H/5 * * * *')   // polls GitHub every 5 min — no webhook needed
    }

    stages {

        stage('MCP: Start') {
            steps {
                script {
                    mcpNotify(event: 'pipeline.started', branch: env.BRANCH_NAME,
                              build: env.BUILD_NUMBER, commit: env.GIT_COMMIT?.take(7))
                }
            }
        }

        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_AUTHOR = sh(script: 'git log -1 --pretty=%an', returnStdout: true).trim()
                    env.GIT_MSG    = sh(script: 'git log -1 --pretty=%B',  returnStdout: true).trim()
                    echo "Commit by ${env.GIT_AUTHOR}: ${env.GIT_MSG}"
                }
            }
        }

        stage('Build') {
            steps {
                script { mcpNotify(event: 'stage.started', stage: 'Build') }
                sh '''
                    echo "==> npm install"
                    npm install
                    echo "==> npm run build"
                    npm run build
                '''
            }
            post {
                success { script { mcpNotify(event: 'stage.passed', stage: 'Build') } }
                failure { script { mcpNotify(event: 'stage.failed', stage: 'Build') } }
            }
        }

        stage('Test') {
            steps {
                script { mcpNotify(event: 'stage.started', stage: 'Test') }
                sh 'CI=true npm test -- --watchAll=false --passWithNoTests'
            }
            post {
                success { script { mcpNotify(event: 'stage.passed', stage: 'Test') } }
                failure { script { mcpNotify(event: 'stage.failed', stage: 'Test') } }
            }
        }

        stage('MCP: Code Analysis') {
            when { anyOf { branch 'main'; branch 'staging'; changeRequest() } }
            steps {
                script {
                    def diff = sh(script: 'git diff HEAD~1 --stat 2>/dev/null || echo "Initial commit"',
                                  returnStdout: true).trim()
                    def result = mcpTool(tool: 'analyze_code_diff',
                                         payload: [diff: diff, branch: env.BRANCH_NAME])
                    echo "MCP Analysis:\n${result}"
                    writeFile file: 'mcp-analysis.txt', text: result
                    archiveArtifacts artifacts: 'mcp-analysis.txt', allowEmptyArchive: true
                }
            }
        }

        stage('Security Scan') {
            steps {
                sh 'npm audit --audit-level=high || true'
            }
        }

        stage('Deploy') {
            when { anyOf { branch 'main'; branch 'staging' } }
            steps {
                script { mcpNotify(event: 'stage.started', stage: "Deploy:${env.DEPLOY_ENV}") }
                withCredentials([
                    sshUserPrivateKey(credentialsId: 'ccl-deploy-key', keyFileVariable: 'SSH_KEY'),
                    string(credentialsId: 'ccl-deploy-host', variable: 'DEPLOY_HOST')
                ]) {
                    sh '''
                        chmod 600 $SSH_KEY
                        echo "==> Deploying build/ → deployer@${DEPLOY_HOST}:/var/www/${APP_NAME}/"
                        rsync -avz --delete \
                            -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
                            build/ deployer@$DEPLOY_HOST:/var/www/${APP_NAME}/
                        ssh -i $SSH_KEY -o StrictHostKeyChecking=no deployer@$DEPLOY_HOST \
                            "sudo systemctl reload nginx && echo Deploy done"
                    '''
                }
            }
            post {
                success { script { mcpNotify(event: 'deploy.success', env: env.DEPLOY_ENV) } }
                failure { script { mcpNotify(event: 'deploy.failed',  env: env.DEPLOY_ENV) } }
            }
        }

        stage('Smoke Test') {
            when { anyOf { branch 'main'; branch 'staging' } }
            steps {
                script {
                    withCredentials([string(credentialsId: 'ccl-deploy-host', variable: 'DEPLOY_HOST')]) {
                        def url = "http://${env.DEPLOY_HOST}"
                        sh """
                            sleep 3
                            STATUS=\$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 ${url} || echo 000)
                            echo "Smoke test → HTTP \$STATUS"
                            [ "\$STATUS" = "200" ] || [ "\$STATUS" = "301" ] || [ "\$STATUS" = "302" ] || exit 1
                        """
                        mcpTool(tool: 'validate_deployment', payload: [url: url, env: env.DEPLOY_ENV])
                    }
                }
            }
        }

    } // end stages

    post {
        success { script { mcpNotify(event: 'pipeline.success', branch: env.BRANCH_NAME,
                                     build: env.BUILD_NUMBER, env: env.DEPLOY_ENV) } }
        failure { script { mcpNotify(event: 'pipeline.failed',  branch: env.BRANCH_NAME,
                                     build: env.BUILD_NUMBER, env: env.DEPLOY_ENV) } }
        always  { cleanWs() }
    }
}

def mcpNotify(Map args) {
    try {
        def p = groovy.json.JsonOutput.toJson(args)
        sh "curl -s -X POST ${MCP_SERVER_URL}/notify -H 'Content-Type: application/json' -d '${p}' || true"
    } catch (e) { echo "MCP notify skipped: ${e.message}" }
}

def mcpTool(Map args) {
    try {
        def p = groovy.json.JsonOutput.toJson(args.payload)
        return sh(script: "curl -s -X POST ${MCP_SERVER_URL}/tool/${args.tool} -H 'Content-Type: application/json' -d '${p}'",
                  returnStdout: true).trim()
    } catch (e) { echo "MCP tool skipped: ${e.message}"; return '' }
}
