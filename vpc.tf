# ----------------------------------------------------------------------------
# 다이어그램의 "VPC / Private Subnet / Security Group / IAM" 박스
# 원칙(아키텍처 문서 13장): EC2는 Private Subnet, public IP 없음
# 인터넷 없이 관리 가능하도록 SSM용 VPC Interface Endpoint를 사용한다
# (관리 경로 = SSM Run Command / Port Forwarding, 다이어그램의 "AWS SSM" 박스)
# ----------------------------------------------------------------------------

resource "aws_vpc" "trial" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.trial.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone

  # 다이어그램 원칙: public IP 없음
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-subnet"
  }
}

# Private subnet 전용 라우팅 테이블 (인터넷 게이트웨이로 향하는 default route 없음)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.trial.id

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ----------------------------------------------------------------------------
# 보안 그룹: 다이어그램 원칙 "Security Group inbound 없음"
# 관리 경로는 SSM(아래 VPC Endpoint)만 사용하므로 인바운드 자체가 필요 없음
# ----------------------------------------------------------------------------
resource "aws_security_group" "trial_ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "Trial EC2 SG - no inbound, SSM managed only"
  vpc_id      = aws_vpc.trial.id

  egress {
    description = "Outbound - should be restricted to Model Proxy / SSM Endpoint in production"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ec2-sg"
  }
}

# VPC Endpoint용 보안 그룹 (Trial EC2 SG에서의 HTTPS만 허용)
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project_name}-vpce-sg"
  description = "SSM VPC Endpoint SG"
  vpc_id      = aws_vpc.trial.id

  ingress {
    description     = "HTTPS from Trial EC2 to SSM Endpoint"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.trial_ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-vpce-sg"
  }
}

# ----------------------------------------------------------------------------
# SSM 관리를 위한 VPC Interface Endpoint 3종
# (Private Subnet에 인터넷 경로가 없어도 SSM Run Command / Session Manager 사용 가능)
# ----------------------------------------------------------------------------
locals {
  ssm_endpoint_services = ["ssm", "ssmmessages", "ec2messages"]
}

resource "aws_vpc_endpoint" "ssm" {
  for_each = toset(local.ssm_endpoint_services)

  vpc_id              = aws_vpc.trial.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-vpce-${each.value}"
  }
}
