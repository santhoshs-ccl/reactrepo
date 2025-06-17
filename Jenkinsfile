pipeline {
    agent any

    stages {
        stage('Pull Latest Code') {
            steps {
                dir('/home/ubuntu/reactrepo') {
                    sh '''
                        git reset --hard
                        git pull origin main
                    '''
                }
            }
        }

        stage('Install Dependencies') {
            steps {
                dir('/home/ubuntu/reactrepo') {
                    sh 'npm install'
                }
            }
        }

        stage('Build React App') {
            steps {
                dir('/home/ubuntu/reactrepo') {
                    sh 'npm run build'
                }
            }
        }

        stage('Restart Apache') {
            steps {
                sh 'sudo systemctl restart apache2'
            }
        }
    }
}
