# Main Configuration: 모듈 호출 및 Output 통합

# Foundation Module 호출 (S3/DynamoDB 생성)
# 이 모듈은 딱 한 번만 적용
module "foundation" {
  source = "./modules/01-foundation"
}

# Network Module 호출 (VPC, ECR, Networking 생성)
# 이 모듈이 메인 인프라를 구축하며, 이후 삭제/재생성 대상이 됨
module "network" {
  source = "./modules/02-network"
}

# Jenkins EC2 
module "compute" {
  source = "./modules/03-compute"
  
  vpc_id	= module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids

  # 루트 variables.tf에 정의된 public key 변수 전달
  ssh_public_key = var.public_ssh_key_content
}

# EKS 모듈 호출 (EKS Cluster, Node Group)
module "eks" {
  source = "./modules/04-eks"
  
  # Network 모듈에서 VPC와 서브넷 정보를 받아옴
  vpc_id               = module.network.vpc_id
  public_subnet_ids    = module.network.public_subnet_ids
  private_subnet_ids   = module.network.private_subnet_ids

  # AWS Region

  aws_region = "ap-northeast-2"
}

# Root Output: 다른 프로젝트에서 참조할 수 있도록 최종 Output 통합
output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "ecr_repository_url" {
  value = module.foundation.ecr_repository_url 
}

output "jenkins_public_ip" {
  value = module.compute.jenkins_public_ip
}

output "eks_kubeconfig_command" {
  value = module.eks.eks_kubeconfig_command
  description = "EKS 클러스터에 kubectl로 접속하기 위한 명령어 AWS CLI v2가 설치되어 있어야 함!!"
}
