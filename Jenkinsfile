pipeline {
    agent any

    stages {
        stage('Pull Latest Code') {
            steps {
                dir('/var/www/reactrepo') {
                    sh '''
                        git reset --hard
                        git pull origin main
                    '''
                }
            }
        }

        stage('Install Dependencies') {
            steps {
                dir('/var/www/reactrepo') {
                    sh 'npm install'
                }
            }
        }

        stage('Build React App') {
            steps {
                dir('/var/www/reactrepo') {
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
