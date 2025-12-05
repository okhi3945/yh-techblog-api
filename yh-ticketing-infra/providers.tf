# providers.tf

terraform {
  # Terraform의 최소 버전 지정
  required_version = ">= 1.0.0"

  # AWS Provider 정의 및 버전 명시, 사용할 클라우드 Provider 지정
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # 최신 안정화 버전 사용
    }
  }

  # 원격 상태 저장소 (Backend) 설정
  # Terraform 상태 파일을 S3 버킷에 안전하게 저장하여 팀 협업과 안정성을 확보
#  backend "s3" {
#    bucket         = "ticketing-tfstate-yh-s3"
#    key            = "dev/ticketing-eks.tfstate" # 상태 파일 경로 (S3 버킷 내에서 상태 파일의 경로 및 이름)
#    region         = "ap-northeast-2"
#    encrypt        = true # 상태 파일 암호화
#    dynamodb_table = "ticketing-tf-locks" # DynamoDB 테이블을 사용하여 상태 파일에 대한 잠금(Locking) 기능을 활성화 (동시 실행 방지)
#   }
}

# AWS Provider 구성
provider "aws" {
  region = "ap-northeast-2" # 서울 리전
}
