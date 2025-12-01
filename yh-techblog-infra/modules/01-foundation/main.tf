# backend_setup.tf
# S3와DynamoDB를 먼저 AWS에 생성하기 위한 파일

# Terraform 상태 파일을 저장할 S3 버킷 (이름은 전역적으로 고유해야 함)
resource "aws_s3_bucket" "tf_state" {
  bucket = "techblog-tfstate-yh-s3"
  lifecycle {
    prevent_destroy = true 
  }  
  tags = {
    Name = "TechBlog Terraform State"
  }
}

# S3 버킷 버전 관리 (실수로 상태 파일이 삭제되거나 덮어쓰이는 것을 방지)
resource "aws_s3_bucket_versioning" "tf_state_versioning" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Terraform 상태 파일을 잠가 동시 실행으로 인한 상태 손상을 막는 DynamoDB 테이블
resource "aws_dynamodb_table" "tf_locks" {
  name           = "techblog-tf-locks"
  billing_mode   = "PAY_PER_REQUEST" # 사용한 만큼만 지불
  hash_key       = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
  lifecycle {
    prevent_destroy = true 
  }
  tags = {
    Name = "TechBlog Terraform Lock Table"
  }
}

# ECR
resource "aws_ecr_repository" "techblog_api" {
  name                 = "techblog-api-repo"
  image_scanning_configuration {
    scan_on_push = true
  }
  image_tag_mutability = "MUTABLE"

  # Lifecycle 보호 설정: 이미지 저장소를 실수로 삭제하지 않도록 보호
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "TechBlog-API-Repository"
    Environment = "Dev"
  }
}

resource "aws_ecr_lifecycle_policy" "api_policy" {
  repository = aws_ecr_repository.techblog_api.name
  policy     = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 images"
        selection    = {
          tagStatus   = "untagged"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = {
           type = "expire"
        }
      },
    ]
  })
}

output "tf_state_bucket_name" {
  value = aws_s3_bucket.tf_state.id
}

output "tf_locks_table_name" {
  value = aws_dynamodb_table.tf_locks.name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.techblog_api.repository_url
}
