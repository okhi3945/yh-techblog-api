pipeline {
    agent any

    environment {
        AWS_REGION     = 'ap-northeast-2'
        
        ECR_URL        = '601559288376.dkr.ecr.ap-northeast-2.amazonaws.com/ticketing-api-repo'
        
        CLUSTER_NAME   = 'ticketing-eks-cluster'
        IMAGE_TAG      = "${env.BUILD_NUMBER}"
    }

    stages {

        // 1. Checkout => Github에서 소스코드 가져오기, scm에 github 레포지토리와 credentials에 설정해둔 ssh키로 접속하여 소스코드 가져옴
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        // Spring Boot를 위해 gradle을 사용하여 JAR 파일을 생성함
        stage('Build Artifact') {
            steps {
                // Gradle을 이용해 실행 가능한 JAR 파일 생성
                // -x test는 빌드 속도를 위해 테스트를 건너뛰는 옵션입니다.
                sh 'chmod +x gradlew'
                sh './gradlew clean build -x test'
            }
        }

        // Dockerfile을 읽어 Spring Boot의 도커 이미지를 만들어둠
        // docker-compose.yml은 k8s의 Yaml을 사용할 것임
        stage('Docker Build & Tag') {
            steps {
                // 프로젝트 루트의 Dockerfile을 읽어 이미지 빌드 및 태그 지정
                sh "docker build -t ${ECR_URL}:${IMAGE_TAG} ."
                sh "docker tag ${ECR_URL}:${IMAGE_TAG} ${ECR_URL}:latest"
            }
        }


        // 위에서 빌드한 Spring Boot의 도커 이미지를 ecr에 넣기 
        stage('Push to ECR') {
            steps {
                // AWS ECR 저장소에 로그인하고 빌드된 이미지를 전송(Push)
                sh "aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_URL}"
                sh "docker push ${ECR_URL}:${IMAGE_TAG}"
                sh "docker push ${ECR_URL}:latest"
            }
        }

        // eks를 사용하여 배포
        stage('Deploy to EKS') {
            steps {
                // EKS 클러스터 접속 설정(kubeconfig)을 업데이트
                sh "aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION}"
                
                // 쿠버네티스 매니페스트(YAML)가 준비되면 아래 주석을 해제하여 배포를 자동화합니다.
                // sh "kubectl apply -f k8s/"
                echo "EKS 인프라 준비 완료. k8s 매니페스트 배포 대기 중..."
            }
        }
    }

    post {
        success {
            echo "티켓팅 서비스 배포 성공 (Build #${env.BUILD_NUMBER})"
        }
        failure {
            echo "배포 실패. 젠킨스 콘솔 로그를 확인해 주세요."
        }
    }
}