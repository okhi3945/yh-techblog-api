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

resource "aws_security_group" "eks_node_sg" {
  name        = "ticketing-eks-node-sg"
  description = "Security group for EKS Worker Nodes"
  vpc_id      = var.vpc_id

  # Ingress 1: 노드 그룹 내부 통신 허용 (Pod, Kubelet 통신)
  ingress {
    description = "Allow all traffic within Node SG"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true # 이 SG를 사용하는 모든 EC2 간 통신 허용
  }
  
  # Ingress 2: EKS Control Plane에서 Node로 들어오는 통신 허용 (Kubelet 포트 10250)
  ingress {
    description = "Allow EKS Control Plane"
    from_port   = 10250 
    to_port     = 10250 
    protocol    = "tcp"
    # VPC CIDR 블록 전체를 열어 EKS Control Plane이 통신할 수 있도록 함.
    cidr_blocks = ["10.0.0.0/16"] 
  }
  
  # Egress: 모든 아웃바운드 통신 허용 (AWS API, ECR, GitHub 접근을 위해 NAT Gateway 사용)
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


resource "aws_launch_template" "eks_node_lt" {
  name_prefix   = "ticketing-eks-node-lt-"
  image_id      = data.aws_ami.eks_optimized.id # EKS 최적화 AMI 사용
  instance_type = "t3.micro" 
  
  # 보안 그룹을 Launch Template의 네트워크 인터페이스에 연결
  network_interfaces {
    security_groups = [aws_security_group.eks_node_sg.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "Ticketing-EKS-Worker-Template"
    }
  }
}

data "aws_ami" "eks_optimized" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amazon-eks-node-*"] 
  }
  # x86_64
  filter {
    name   = "architecture"
    values = ["x86_64"] 
  }
}

# EKS Managed Node Group (Worker Nodes)
resource "aws_eks_node_group" "private_node_group" {
  cluster_name    = aws_eks_cluster.ticketing_cluster.name
  node_group_name = "ticketing-private-nodes"
  subnet_ids      = var.private_subnet_ids # 노드 그룹도 Private Subnet에 배치
  node_role_arn   = aws_iam_role.eks_node_role.arn
  
  remote_access {
    ec2_ssh_key = "jenkins-key" 
  }

  scaling_config {
    desired_size = 2 # 시작 노드 2개
    max_size     = 4
    min_size     = 2
  }
  launch_template {
    name    = aws_launch_template.eks_node_lt.name
    version = "$Latest" # 최신 버전 사용 지시
  }
  # EKS 클러스터가 완전히 생성된 후에 노드 그룹이 생성되도록 명시적 의존성 설정
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_cni_policy,
    aws_security_group.eks_node_sg,
    aws_launch_template.eks_node_lt,
  ]

  tags = {
    Name = "Ticketing-EKS-Worker_Node"
  }
}

resource "aws_eks_cluster" "ticketing_cluster_auth" {
  name = aws_eks_cluster.ticketing_cluster.name
}

resource "aws_eks_addon" "aws_auth_configmap" {
  cluster_name = aws_eks_cluster.ticketing_cluster.name
  addon_name   = "aws-auth"
  addon_version = "v1" # v1은 kube-system 네임스페이스의 ConfigMap 이름입니다.
  resolve_conflicts = "OVERWRITE"

  configuration_values = jsonencode({
    mapRoles = [
      {
        rolearn  = aws_iam_role.eks_node_role.arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      }
    ]
  })
  
  # 이 ConfigMap은 EKS 클러스터가 완전히 생성된 후에만 적용되어야 합니다.
  depends_on = [
    aws_eks_cluster.ticketing_cluster,
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
  ]
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
