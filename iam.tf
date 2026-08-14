# EC2용 IAM Role: SSM 관리 권한만 부여한다.
# Agent가 사용할 AWS 권한은 여기 포함하지 않는다.

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

# 참고: Agent가 쓸 AWS 권한은 여기 없음. 필요해지면 별도로 검토해서 추가해야 한다.
