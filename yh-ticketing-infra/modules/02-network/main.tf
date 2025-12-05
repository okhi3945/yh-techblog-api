# Module 02-network: VPC, Subnet, Route, ECR 리소스 정의

# VPC 생성
resource "aws_vpc" "ticketing_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "TechBlog-VPC"
  }
}

# 인터넷 게이트웨이 (IGW)
resource "aws_internet_gateway" "ticketing_igw" {
  vpc_id = aws_vpc.ticketing_vpc.id
  tags = {
    Name = "TechBlog-IGW"
  }
}

# 가용 영역 (AZ) 목록 조회
data "aws_availability_zones" "available" {
  state = "available"
}

# Public Subnets 정의 (AZ 2개 사용)
resource "aws_subnet" "public_subnet" {
  count             = 2
  vpc_id            = aws_vpc.ticketing_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.ticketing_vpc.cidr_block, 8, count.index) # 10.0.0.0/24, 10.0.1.0/24
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "TechBlog-Public-Subnet-${data.aws_availability_zones.available.names[count.index]}"
  }
}

# Private Subnets 정의 (AZ 2개 사용)
resource "aws_subnet" "private_subnet" {
  count             = 2
  vpc_id            = aws_vpc.ticketing_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.ticketing_vpc.cidr_block, 8, count.index + 2) # 10.0.2.0/24, 10.0.3.0/24
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "TechBlog-Private-Subnet-${data.aws_availability_zones.available.names[count.index]}"
  }
}

# Public Route Table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.ticketing_vpc.id
  tags = {
    Name = "TechBlog-Public-RT"
  }
}

# Public Route: 0.0.0.0/0 (모든 트래픽) -> IGW
resource "aws_route" "public_internet_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.ticketing_igw.id
}

# Public Subnets과 Public Route Table 연결
resource "aws_route_table_association" "public_association" {
  count          = 2
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# EIP (Elastic IP) - NAT Gateway용
resource "aws_eip" "ticketing_nat_eip" {
  domain = "vpc"
  tags = {
    Name = "TechBlog-NAT-EIP"
  }
}

# NAT Gateway 생성 (Public Subnet-A에 위치)
resource "aws_nat_gateway" "ticketing_nat" {
  allocation_id = aws_eip.ticketing_nat_eip.id
  subnet_id     = aws_subnet.public_subnet[0].id # Public Subnet 중 첫 번째 (AZ-A)에 배치
  tags = {
    Name = "TechBlog-NAT-Gateway"
  }
  # NAT Gateway가 EIP에 의존하도록 명시적으로 설정 (안정성)
  depends_on = [aws_internet_gateway.ticketing_igw]
}

# Private Route Table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.ticketing_vpc.id
  tags = {
    Name = "TechBlog-Private-RT"
  }
}

# Private Route: 0.0.0.0/0 (모든 트래픽) -> NAT Gateway
resource "aws_route" "private_nat_route" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.ticketing_nat.id
}

# Private Subnets과 Private Route Table 연결
resource "aws_route_table_association" "private_association" {
  count          = 2
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}


# Output: 외부에서 참조할 VPC 정보

output "vpc_id" {
  value = aws_vpc.ticketing_vpc.id
}

output "public_subnet_ids" {
  value = aws_subnet.public_subnet[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private_subnet[*].id
}
