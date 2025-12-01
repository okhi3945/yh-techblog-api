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
