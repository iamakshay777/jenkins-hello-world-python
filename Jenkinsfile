pipeline {
    agent any

    // Edit these to match your AWS setup
    environment {
        AWS_REGION    = 'us-east-1'
        AWS_ACCOUNT   = '595028890058'                                  // <-- replace with your AWS account ID
        ECR_REPO      = 'hello-world-python'
        ECR_REGISTRY  = "${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        IMAGE_NAME    = "${ECR_REGISTRY}/${ECR_REPO}"
        IMAGE_TAG     = "${env.BUILD_NUMBER}"
        DEPLOY_DIR    = '/opt/hello-world-python'
    }

    options {
        timestamps()
        ansiColor('xterm')
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    triggers {
        githubPush()
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                sh 'git rev-parse --short HEAD > .git-sha && cat .git-sha'
            }
        }

        stage('Build & push to ECR (buildx)') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-ecr-creds'
                ]]) {
                    sh '''
                        set -eux
                        # Ensure ECR repo exists
                        aws ecr describe-repositories --repository-names ${ECR_REPO} --region ${AWS_REGION} \
                            || aws ecr create-repository --repository-name ${ECR_REPO} --region ${AWS_REGION}

                        # Login to ECR
                        aws ecr get-login-password --region ${AWS_REGION} \
                            | docker login --username AWS --password-stdin ${ECR_REGISTRY}

                        # buildx: build + push single-platform image in one shot.
                        # --provenance=false / --sbom=false strip the extra attestation
                        # manifests that confuse plain `docker push` on Docker 25+.
                        docker buildx build \
                            --platform linux/amd64 \
                            --provenance=false \
                            --sbom=false \
                            --build-arg APP_VERSION=${IMAGE_TAG} \
                            -t ${IMAGE_NAME}:${IMAGE_TAG} \
                            -t ${IMAGE_NAME}:latest \
                            --push \
                            .
                    '''
                }
            }
        }

        stage('Deploy (docker compose rollout)') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-ecr-creds'
                ]]) {
                    sh '''
                        set -eux
                        sudo mkdir -p ${DEPLOY_DIR}
                        sudo chown $(id -u):$(id -g) ${DEPLOY_DIR}
                        cp docker-compose.yml deploy.sh ${DEPLOY_DIR}/
                        cd ${DEPLOY_DIR}
                        chmod +x deploy.sh
                        ECR_REGISTRY=${ECR_REGISTRY} \
                        ECR_REPO=${ECR_REPO} \
                        IMAGE_TAG=${IMAGE_TAG} \
                        AWS_REGION=${AWS_REGION} \
                        ./deploy.sh
                    '''
                }
            }
        }

        stage('Smoke test') {
            steps {
                sh '''
                    set -eux
                    for i in 1 2 3 4 5 6 7 8 9 10; do
                        if curl -fs http://localhost:5000/health; then
                            echo "OK"; exit 0
                        fi
                        sleep 3
                    done
                    echo "Health check failed"; exit 1
                '''
            }
        }
    }

    post {
        always {
            sh 'docker image prune -f || true'
        }
        success {
            echo "Deployed ${IMAGE_NAME}:${IMAGE_TAG}"
        }
        failure {
            echo "Build/Deploy failed for ${IMAGE_NAME}:${IMAGE_TAG}"
        }
    }
}
