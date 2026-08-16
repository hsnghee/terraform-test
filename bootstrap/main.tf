# tfstate를 저장할 S3 버킷 + 동시 apply를 막아주는 DynamoDB 락 테이블을 만드는
# 별도의 작은 프로젝트. 메인 terraform 코드(../)와는 독립된 root module이다.
#
# (닭이 먼저냐 달걀이 먼저냐 문제: 메인 코드가 S3 backend를 쓰려면 그 S3 버킷이
# 먼저 있어야 하는데, 그 버킷 자체는 이 bootstrap을 로컬 state로 한 번 apply해서 만든다)
#
# 사용법 (팀에서 딱 한 번만 실행하면 됨):
#   cd bootstrap
#   terraform init
#   terraform apply
#   -> 출력된 state_bucket_name / dynamodb_table_name 값을 ../backend.tf에 채워넣기

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "Sandbox 계정에서 사용할 리전"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "tfstate를 저장할 S3 버킷 이름 (AWS 계정 전체에서 유일해야 함). 비워두면 자동 생성"
  type        = string
  default     = ""
}

resource "random_id" "suffix" {
  count       = var.state_bucket_name == "" ? 1 : 0
  byte_length = 4
}

locals {
  bucket_name = var.state_bucket_name != "" ? var.state_bucket_name : "trial-tfstate-${random_id.suffix[0].hex}"
}

resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "trial-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

output "state_bucket_name" {
  value = aws_s3_bucket.tfstate.bucket
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.tfstate_lock.name
}
