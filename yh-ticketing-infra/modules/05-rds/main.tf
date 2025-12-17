# Module 05-rds => PostgreSQL DB 올리기, EKS 노드만 접근 가능한 Private DB 구축

# RDS 접속용 SG 정의
# EKS 워커 노드인 Pod에서만 PostgreSQL 포트(5432) 접근을 허용
resource "aws_security_group" "rds_sg" {
  name        = "ticketing-rds-sg"
  description = "Allow EKS Nodes to connect to RDS"
  vpc_id      = var.vpc_id

  # Ingress: EKS 워커 노드 보안 그룹으로부터의 5432 포트 접근 허용
  ingress {
    description     = "PostgreSQL from EKS Nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    # [핵심] EKS 노드 그룹의 보안 그룹 ID를 소스로 지정
    security_groups = [var.eks_node_security_group_id]
  }

  # Egress: DB는 외부로 나갈 필요가 없기 때문에 모두 차단 
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Ticketing-RDS-SG"
  }
}

# DB Subnet Group 생성 (Private Subnet 사용)
# 여러 AZ에 걸친 Subnet 그룹이 필요함
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "ticketing-rds-subnet-group"
  subnet_ids = var.private_subnet_ids
  tags = {
    Name = "Ticketing-RDS-Subnet-Group"
  }
}

# Free Tier로 RDS PostgreSQL 인스턴스 생성
resource "aws_db_instance" "ticketing_db" {
  allocated_storage      = 20 # 20 GB (최소 권장)
  engine                 = "postgres"
  engine_version         = "17.6" # 안정적인 PostgreSQL 버전
  instance_class         = "db.t3.micro" # Free Tier용 t3 micro
  db_name                = "ticketing_db"
  username               = "postgres" # 마스터 사용자 이름
  password               = var.rds_password # 루트 변수에서 받은 비밀번호 사용
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true # 테스트 환경이므로 최종 스냅샷 건너뛰기
  publicly_accessible    = false # Public 접근 차단 (Private Subnet에 있으므로)
  multi_az               = false # Multi-AZ는 비용이 발생하므로 단일 AZ로 설정

  tags = {
    Name = "Ticketing-PostgreSQL-DB"
  }
}

# Output: EKS Pod가 DB에 접속할 때 사용할 엔드포인트
output "rds_endpoint" {
  description = "RDS Instance Endpoint Address"
  value       = aws_db_instance.ticketing_db.address
}

output "rds_security_group_id" {
  value = aws_security_group.rds_sg.id
}
