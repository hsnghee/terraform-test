# ----------------------------------------------------------------------------
# 다이어그램의 "VPC/Private Subnet/Security Group/IAM" 및 Trusted Orchestrator
# 문서 6.4 원칙: "Host 관리용 SSM 권한은 존재하지만, Agent 작업용 AWS 권한은 없음"
# 즉 이 Role은 SSM 관리 전용이며 Agent가 쓸 수 있는 AWS 리소스 권한은 포함하지 않는다
# ----------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "trial_ec2" {
  name               = "${var.project_name}-ec2-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

# SSM 관리(Session Manager, Run Command)에 필요한 AWS 관리형 정책만 부여
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.trial_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "trial_ec2" {
  name = "${var.project_name}-ec2-instance-profile"
  role = aws_iam_role.trial_ec2.name
}

# ----------------------------------------------------------------------------
# 참고: Agent 작업용 AWS 권한(aws_access_mode: none/broker-sts/direct-imds 등)은
# 여기 포함하지 않는다. 아키텍처 문서 6장에 따라 별도 승인된 확장 Profile에서만 추가한다.
# ----------------------------------------------------------------------------
