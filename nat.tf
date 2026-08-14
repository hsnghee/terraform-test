# ----------------------------------------------------------------------------
# 문서 13장 원칙: "관리 통신: SSM·ECR·CloudWatch VPC Endpoint 또는 제한 NAT"
# SSM 관리 자체는 VPC Endpoint로 충분하지만, apt/docker pull 등 실제 패키지 설치는
# 인터넷 접근이 필요하므로 NAT Gateway를 통한 제한된 outbound 경로를 추가한다.
# (Trial EC2는 여전히 Private Subnet + public IP 없음을 유지)
# ----------------------------------------------------------------------------

variable "public_subnet_cidr" {
  description = "NAT Gateway가 위치할 Public Subnet CIDR"
  type        = string
  default     = "10.20.0.0/24"
}

resource "aws_internet_gateway" "trial" {
  vpc_id = aws_vpc.trial.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.trial.id
  cidr_block               = var.public_subnet_cidr
  availability_zone        = var.availability_zone
  map_public_ip_on_launch  = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.trial.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.trial.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "trial" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "${var.project_name}-nat"
  }

  depends_on = [aws_internet_gateway.trial]
}

# 기존 Private Subnet 라우팅 테이블(vpc.tf의 aws_route_table.private)에
# NAT를 통한 outbound 경로를 추가한다. Trial EC2는 여전히 public IP를 갖지 않는다.
resource "aws_route" "private_via_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id          = aws_nat_gateway.trial.id
}
