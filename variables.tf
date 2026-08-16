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
  description = "Trial EC2가 위치할 Private Subnet CIDR"
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
  description = "한 번에 EC2 한 대만 사용한다는 원칙에 따른 기본값 1"
  type        = number
  default     = 1
}

variable "enable_flow_logs" {
  description = "VPC Flow Logs 활성화 여부"
  type        = bool
  default     = true
}

variable "enable_cloudtrail" {
  description = "CloudTrail 활성화 여부"
  type        = bool
  default     = true
}

variable "golden_ami_id" {
  description = "Golden AMI가 준비되면 해당 AMI ID를 입력. 비워두면 기본 Ubuntu 24.04를 사용"
  type        = string
  default     = ""
}

variable "canary_file_path" {
  description = "Host에 만들어둘 미끼(Canary) 파일 경로. auditd가 이 경로를 감시한다"
  type        = string
  default     = "/opt/trial/canary/protected-file.txt"
}

variable "cloudtrail_bucket_force_destroy" {
  description = "terraform destroy 시 CloudTrail 로그 버킷을 비우고 같이 삭제할지 여부"
  type        = bool
  default     = true
}

variable "create_golden_ami" {
  description = "현재 Trial EC2 상태를 Golden AMI로 저장할지 여부"
  type        = bool
  default     = false
}

variable "attach_cloudwatch_agent_policy" {
  description = "EC2 IAM Role에 CloudWatch Agent 정책을 추가로 붙일지 여부"
  type        = bool
  default     = false
}

variable "budget_limit_usd" {
  description = "월간 AWS 예산 한도 (USD)"
  type        = number
  default     = 10
}

variable "budget_alert_email" {
  description = "예산 초과 알림을 받을 이메일. 비워두면 알림을 만들지 않음"
  type        = string
  default     = ""
}
