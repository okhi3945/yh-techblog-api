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

  jenkins_security_group_id = module.compute.jenkins_security_group_id
  jenkins_role_arn = module.compute.jenkins_role_arn
  aws_region = "ap-northeast-2"
}

# RDS 모듈
module "rds" {
  source = "./modules/05-rds"
  
  vpc_id              = module.network.vpc_id
  private_subnet_ids  = module.network.private_subnet_ids
  # Root 폴더에 variables.tf에 정의된 비밀번호 변수를 전달
  rds_password        = var.rds_db_password 
  # EKS 노드 SG를 RDS SG에 인바운드 규칙으로 허용하기 위해 전달
  # EKS 모듈의 Output인 'eks_node_sg.id'를 RDS 모듈로 전달
  eks_node_security_group_id = module.eks.eks_node_security_group_id
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

# RDS 접속 정보 Output
output "rds_endpoint" {
  value = module.rds.rds_endpoint
  description = "Ticketing PostgreSQL DB Endpoint Address"
}

output "rds_password" {
  value       = var.rds_db_password
  description = "The password for the RDS instance"
  sensitive   = true
}