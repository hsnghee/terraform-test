# ----------------------------------------------------------------------------
# 다이어그램의 "VPC Flow Logs" / "AWS CloudTrail" 박스
# Independent Verification Plane이 참조할 원시 증거(Evidence) 소스 중
# AWS 레벨에서 나오는 부분을 담당한다.
# ----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count             = var.enable_flow_logs ? 1 : 0
  name              = "/${var.project_name}/vpc-flow-logs"
  retention_in_days = 30
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0
  name  = "${var.project_name}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0
  name  = "${var.project_name}-flow-logs-policy"
  role  = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "trial" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id               = aws_vpc.trial.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination       = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  iam_role_arn          = aws_iam_role.flow_logs[0].arn
}

# ----------------------------------------------------------------------------
# CloudTrail: 팀 공용 계정에서 "누가 언제 무슨 작업을 했는지" 감사 로그
# 실습 단계에서는 S3 버킷 하나만 별도로 두고 여기서는 트레일 자체만 구성한다.
# ----------------------------------------------------------------------------

resource "aws_s3_bucket" "cloudtrail" {
  count         = var.enable_cloudtrail ? 1 : 0
  bucket_prefix = "${var.project_name}-cloudtrail-"
  force_destroy = true
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail[0].arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail[0].arn}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "trial" {
  count = var.enable_cloudtrail ? 1 : 0

  name                          = "${var.project_name}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail[0].id
  include_global_service_events = true
  is_multi_region_trail         = false

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}
