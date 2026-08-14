variable "aws_region" {
  description = "Sandbox 계정에서 사용할 리전"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
  default     = "trial"
}

variable "vpc_cidr" {
  description = "실험 전용 VPC CIDR"
  type        = string
  default     = "10.20.0.0/16"
}

variable "private_subnet_cidr" {
  description = "Trial EC2가 위치할 Private Subnet CIDR (다이어그램의 'VPC / Private Subnet')"
  type        = string
  default     = "10.20.1.0/24"
}

variable "availability_zone" {
  description = "가용 영역"
  type        = string
  default     = "us-east-1a"
}

variable "instance_type" {
  description = "Trial EC2 인스턴스 타입"
  type        = string
  default     = "t3.small"
}

variable "trial_ec2_count" {
  description = "다이어그램상 '한 번에 EC2 한 대만 사용' 원칙에 따른 기본값 1"
  type        = number
  default     = 1
}

variable "enable_flow_logs" {
  description = "VPC Flow Logs 활성화 여부 (다이어그램의 'VPC Flow Logs' 박스)"
  type        = bool
  default     = true
}

variable "enable_cloudtrail" {
  description = "CloudTrail 활성화 여부 (다이어그램의 'AWS CloudTrail' 박스)"
  type        = bool
  default     = true
}

variable "golden_ami_id" {
  description = "Golden AMI가 준비되면 해당 AMI ID를 입력. 비워두면 기본 Ubuntu 22.04를 사용"
  type        = string
  default     = ""
}

variable "canary_file_path" {
  description = "Host 레벨 Canary 파일 경로. auditd -w 규칙으로 감시한다 (아키텍처 문서 7절 Deception Resource 중 Host 계층에 대응)"
  type        = string
  default     = "/opt/trial/canary/protected-file.txt"
}
