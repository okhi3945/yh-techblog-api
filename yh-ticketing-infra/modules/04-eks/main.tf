# Module 04-eks : EKS Cluster, Private Subnet에 매치, Public Subnet에는 EKS를 위한 NLB 배치

# vpc/subnet 정보
variable "vpc_id" { }
variable "private_subnet_ids" { }
variable "public_subnet_ids" { }

# EKS 클러스터용 IAM Role
# EKS 컨트롤 플레인이 AWS 리소스를 관리할 권한 정의
resource "aws_iam_role" "eks_cluster_role" {
  name = "ticketing-eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

# EKS 클러스터 관리 정책 연결, 기본 관리 권한, AWS 리소스를 만들거나 수정하는데 필요한 기본적인 권한
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# EKS 클러스터 VPC CNI 정책 연결, VPC CNI가 작동할 수 있도록 VPC 내부의 리소스를 관리할 권한
# VPC CNI란 쿠버네티스에서 Pod에 IP 주소를 할당하고, 네트워크 규칙을 적용하는 표준 인터페이스
# Pod들이 서로 통신할 수 있게 만드는 가장 중요한 역할
resource "aws_iam_role_plicy_attachment" "eks_vpc_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster_role.name
}
