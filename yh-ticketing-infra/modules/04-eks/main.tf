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

# 보안 그룹 흐름 따라 잡기
# 누가 누구에게 문을 열어주는 가를 생각해야함
resource "aws_security_group" "eks_node_sg" {
  name        = "ticketing-eks-node-sg"
  description = "Security group for all nodes in the cluster"
  vpc_id      = var.vpc_id


  # 워커 노드들에 흩어져 있는 Pod들이 서로 통신하는 것
  # Ingress가 들어오는 인바운드를 처리해주는 얘가 맞지만 cidr_blocks이 아닌 
  # self=true일 경우에는 보안 그룹을 입고 있는 리소스들끼리 라는 아주 특별한 조건임
  # cidr_blocks = ["0.0.0.0/0"] 설정 시, 전 세계 모든 컴퓨터가 우리 노드 접속 가능하지만
  # self = true 설정 시, 오직 이 ticketing-eks-node-sg를 부여 받은 노드들 끼리만 서로 통신하게 해줌
  ingress {
    description = "Allow all traffic within Node SG (Internal only)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true # 외부 IP가 아닌 동료 노드들만 들어올 수 있게 범위를 좁힘
    # 쿠버네티스 환경은 노드가 여러 개이기 때문에 A 노드의 앱이 B 노드의 앱과 통신하거나 Kubelet 등이 노드 건강 상태를
    # 체크하기 위해서는 이렇게 self=true로 노드들에게 들어갈 수 있는 보안그룹을 설정해줘야함
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
    endpoint_public_access = true
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true # 클러스터 생성자에게 관리자 권한 부여
  }

  tags = {
    Name = "Ticketing-EKS-Control-Plane"
  }
}

data "aws_iam_policy_document" "jenkins_oidc_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_eks_cluster.ticketing_cluster.identity[0].oidc[0].issuer, "https://", "")}:sub"
      # 'jenkins' 네임스페이스의 'jenkins-admin' 서비스 계정만 허용
      values   = ["system:serviceaccount:jenkins:jenkins-admin"] 
    }
    principals {
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(aws_eks_cluster.ticketing_cluster.identity[0].oidc[0].issuer, "https://", "")}"]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "jenkins_pod_role" {
  name               = "ticketing-jenkins-pod-role"
  assume_role_policy = data.aws_iam_policy_document.jenkins_oidc_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "jenkins_pod_ecr" {
  role       = aws_iam_role.jenkins_pod_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_role_policy_attachment" "jenkins_pod_eks" {
  role       = aws_iam_role.jenkins_pod_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

data "aws_caller_identity" "current" {}

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

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_cni_policy,
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
  # value       = aws_security_group.eks_node_sg.id
  value       = aws_eks_cluster.ticketing_cluster.vpc_config[0].cluster_security_group_id
}

output "jenkins_pod_role_arn" {
  value = aws_iam_role.jenkins_pod_role.arn
}