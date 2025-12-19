# Module 04-eks : EKS Cluster, Private Subnet에 매치, Public Subnet에는 EKS를 위한 NLB 배치

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

resource "aws_eks_access_entry" "jenkins_access_entry" {
  cluster_name      = aws_eks_cluster.ticketing_cluster.name
  principal_arn     = var.jenkins_role_arn
  kubernetes_groups = [] 
  type              = "STANDARD"
}

resource "aws_eks_access_policy_association" "jenkins_admin_policy" {
  cluster_name  = aws_eks_cluster.ticketing_cluster.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = var.jenkins_role_arn

  access_scope {
    type = "cluster"
  }
  depends_on = [aws_eks_access_entry.jenkins_access_entry]
}

resource "aws_security_group" "eks_node_sg" {
  name        = "ticketing-eks-node-sg"
  description = "Security group for all nodes in the cluster"
  vpc_id      = var.vpc_id

  # 컨트롤 플레인 및 젠킨스와의 통신용 (443 포트 허용)
  ingress {
    from_port    = 443
    to_port      = 443
    protocol     = "tcp"
    security_groups = [var.jenkins_security_group_id]
  }

  ingress {
    description = "Allow all traffic within Node SG (Internal only)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # 노드 간 통신 및 기본 아웃바운드 규칙 설정
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Ticketing-EKS-Node-SG"
  }
}

resource "aws_security_group_rule" "allow_jenkins_to_eks_api" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  # EKS 클러스터가 자동 생성한 보안 그룹 ID를 참조
  security_group_id        = aws_eks_cluster.ticketing_cluster.vpc_config[0].cluster_security_group_id
  source_security_group_id = var.jenkins_security_group_id
  description              = "Allow Jenkins to communicate with EKS API Server"
}

# EKS 클러스터 관리 정책 연결, 기본 관리 권한, AWS 리소스를 만들거나 수정하는데 필요한 기본적인 권한
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# EKS 클러스터 VPC CNI 정책 연결, VPC CNI가 작동할 수 있도록 VPC 내부의 리소스를 관리할 권한
# VPC CNI란 쿠버네티스에서 Pod에 IP 주소를 할당하고, 네트워크 규칙을 적용하는 표준 인터페이스
# Pod들이 서로 통신할 수 있게 만드는 가장 중요한 역할
resource "aws_iam_role_policy_attachment" "eks_vpc_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster_role.name
}

# EKS Cluster (Control Plane) 정의
resource "aws_eks_cluster" "ticketing_cluster" {
  name     = "ticketing-eks-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.34"

  vpc_config {
    subnet_ids = var.private_subnet_ids # EKS는 Private Subnet에 배치 (보안)
    endpoint_private_access = true # VPC 내부 접근 허용
    endpoint_public_access = false # 외부 접근 차단
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true # 클러스터 생성자에게 관리자 권한 부여
  }

  tags = {
    Name = "Ticketing-EKS-Control-Plane"
  }
}

# EKS Node Group용 IAM Role (Worker Nodes)
# 실제 워크로드(티켓팅 API Pod)가 실행되는 Worker Node에 AWS 리소스를 사용할 수 있는 신분증을 부여
# EC2에 있는 Worker Node가 다른 AWS 서비스에 접근하기 위한 IAM Role
resource "aws_iam_role" "eks_node_role" {
  name = "ticketing-eks-node-role"
  assume_role_policy = jsonencode({ 
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole" # 사용자가 현재 가지고 있는 권한 외에, 다른 IAM 역할(Role)의 권한을 일시적으로 빌려와 사용, EC2가 특정 리소스에 접근할 때 사용(Principal)
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# EKS Workder Node 필수 정책 연결
# Worker Node가 EKS 컨트롤 플레인에 등록하고, Kubelet과 통신하는 등 쿠버네티스 노드로서 작동하는 데 필요한 가장 기본적인 권한임 (eks_workerNodePolicy)
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

# 노드가 VPC CNI를 실행하고 Pod에 VPC IP를 할당하기 위해 VPC 자원(ENI 등)을 관리할 수 있는 권한 (EKS_CNI_Policy)
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

# EC2가 ReadOnly로 ECR 리소스에 이미지를 가져올 수 있는 권한을 설정해줌
# 노드에서 실행되는 Pod가 ECR에 저장된 티켓팅 API Docker 이미지를 읽고 Pull로 다운로드를 할 수 있게 해주는 권한임 (push 권한은 Jenkins한테만 부여)
resource "aws_iam_role_policy_attachment" "ec2_container_registry_readonly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly" # ECR에서 이미지 pull 권한
  role       = aws_iam_role.eks_node_role.name
}

# EKS Managed Node Group (Worker Nodes)
resource "aws_eks_node_group" "private_node_group" {
  cluster_name    = aws_eks_cluster.ticketing_cluster.name
  node_group_name = "ticketing-private-nodes"
  subnet_ids      = var.private_subnet_ids # 노드 그룹도 Private Subnet에 배치
  node_role_arn   = aws_iam_role.eks_node_role.arn
  instance_types  = ["t3.micro"]

  scaling_config {
    desired_size = 2 # 시작 노드 2개
    max_size     = 4
    min_size     = 2
  }

  # EKS 클러스터가 완전히 생성된 후에 노드 그룹이 생성되도록 명시적 의존성 설정
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_cni_policy,
    aws_security_group_rule.allow_jenkins_to_eks_api,
  ]

  tags = {
    Name = "Ticketing-EKS-Worker_Node"
  }
}

# EKS 설정 파일 접속에 필요한 정보를 output으로 내보냄
output "cluster_name" {
  value = aws_eks_cluster.ticketing_cluster.name
}

output "eks_kubeconfig_command" {
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.ticketing_cluster.name} --region ${var.aws_region}"
  description = "EKS 클러스터에 kubectl로 접속하기 위한 명령어"
}

output "node_group_name" {
    value = aws_eks_node_group.private_node_group.node_group_name
}

output "eks_node_security_group_id" {
  description = "Security Group ID for EKS Worker Nodes"
  value       = aws_security_group.eks_node_sg.id
}
