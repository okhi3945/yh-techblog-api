# EC2 Jenkins for CI/CD
# 티켓팅 프로젝트의 CI/CD 파이프라인을 운영할 서버 구축을 목표로 하는 모듈

# jenkins용 보안그룹 정의
resource "aws_security_group" "jenkins_sg" {
  name		= "ticketing-jenkins-master-sg"
  description	= "jenkins_SG"
  vpc_id	= var.vpc_id # Network 모듈에서 받아온 VPC ID를 var. 으로 사용
  
  # Ingress 규칙 : 외부에서 Jenkins 서버로 들어오는 규칙
  ingress {
	description = "web(out) to jenkins, inbound 8080"
	from_port   = 8080
	to_port     = 8080
	protocol    = "tcp"
	cidr_blocks = ["0.0.0.0/0"] # 실습을 위해서 임시로 모든 IP를 허용함
  }

  # 22포트로 들어오는 포트를 열어 SSH로 관리 접속을 허용
  ingress {
	description	= "SSH 22 to jenkins, inbound 22"
	from_port	= 22
	to_port		= 22
	protocol	= "tcp"
	cidr_blocks	= ["0.0.0.0/0"] # 실습을 위해 임시로 모든 IP 허용
  }

  # 아웃바운드 jenkins 서버에서 ECR이랑 github에 접근하기 위해서 모든 아웃바운드 허용함
  egress {
    from_port	= 0
    to_port	= 0
    protocol	= "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
	Name = "Ticketing-Jenkins-Master-SG"
  }
}

# Jenkins IAM ROLE (Jenkins EC2에서 ECR에 접근할 수 있도록 권한 부여)
# Jenkins가 AWS 서비스(ECR, EKS)에 접근할 수 있는 권한 정의
resource "aws_iam_role" "jenkins_role" {
  name	 = "ticketing-jenkins-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole",
	Effect = "Allow",
	Principal = {
	  Service = "ec2.amazonaws.com"
        },
       },
      ]
    })
}

# ECR에 이미지 푸시할 권한 부여
resource "aws_iam_role_policy_attachment" "jenkins_ecr_access" {
  role		= aws_iam_role.jenkins_role.name
  policy_arn	= "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser" # ECR에 Docker 이미지를 올릴 수 있는 권한
}

# EC2와 role 연결
resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "ticketing-jenkins-ec2-profile"
  role = aws_iam_role.jenkins_role.name
}

# Jenkins에서 EKS 클러스터를 조회하고, 관리할 수 있는 권한 부여
resource "aws_iam_role_policy_attachment" "jenkins_eks_admin" {
  role       = aws_iam_role.jenkins_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy" 
}

resource "aws_iam_role_policy" "jenkins_eks_describe" {
  name = "jenkins-eks-describe-policy"
  role = aws_iam_role.jenkins_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:AccessKubernetesApi"
        ]
        Resource = "*"
      }
    ]
  })
}

# AMI Data Source => Ubuntu 22.04 LTS 이미지 ID를 동적으로 가져와서 EC2에 설정하기 위함
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  owners = ["099720109477"] # Canonical AMI Owner ID
}

# SSH 접속용 키페어 Key Pair
resource "aws_key_pair" "jenkins_key" {
  key_name = "jenkins-key" # 사용할 SSH 키 이름
  public_key = var.ssh_public_key 
} 

# Jenkins EC2 Instance
resource "aws_instance" "jenkins_master" {
  ami		= data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  key_name	= aws_key_pair.jenkins_key.key_name

  subnet_id = var.public_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  associate_public_ip_address = true

  # Jenkins, Java, Docker 자동 설치 스크립트 - 사용자 데이터
  user_data = <<-EOF
              #!/bin/bash
              # 1. 패키지 업데이트
              sudo apt update -y
              
              # 2. Java 17 설치 (Jenkins 필수 요소)
              sudo apt install openjdk-17-jre -y
              
              # 3. Jenkins 저장소 키 등록
              curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
              
              # 4. Jenkins 저장소 소스 리스트 추가
              echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
              
              # 5. 패키지 목록 재업데이트 (저장소 반영)
              sudo apt update -y
              
              # 6. Jenkins 설치 (설치 시 서비스 파일이 시스템에 등록됨)
              sudo apt install jenkins -y
              
              # 7. Docker 설치 및 권한 부여
              sudo apt install docker.io -y
              sudo usermod -aG docker jenkins 
              sudo usermod -aG docker ubuntu 
              
              # 8. Jenkins 서비스 활성화 및 시작 (설치 후이므로 서비스 파일이 존재함)
              sudo systemctl enable jenkins
              sudo systemctl start jenkins
              
              # 9. 불필요한 패키지 정리
              sudo apt autoremove -y
              EOF
  iam_instance_profile = aws_iam_instance_profile.jenkins_profile.name

  tags = {
    Name = "Ticketing-Jenkins-Master-Server"
  }
}

# Output
output "jenkins_public_ip" {
  description = "Jenkins Master 서버의 Public IP"
  value	      = aws_instance.jenkins_master.public_ip
}

output "jenkins_security_group_id" {
  value = aws_security_group.jenkins_sg.id
}
