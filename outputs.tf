output "vpc_id" {
  value = aws_vpc.trial.id
}

output "private_subnet_id" {
  value = aws_subnet.private.id
}

output "trial_ec2_instance_ids" {
  value = aws_instance.trial[*].id
}

output "trial_ec2_private_ips" {
  description = "Private IP만 존재 (public IP 없음). 접속은 SSM Session Manager로."
  value       = aws_instance.trial[*].private_ip
}

output "ssm_connect_command" {
  description = "인스턴스별 SSM 접속 명령어 예시"
  value       = [for id in aws_instance.trial[*].id : "aws ssm start-session --target ${id}"]
}

output "canary_file_path" {
  description = "Host Canary 파일 경로 (auditd -w 규칙 대상). SSM 접속 후 /opt/trial/scripts/check_canary.sh 실행해서 확인"
  value       = var.canary_file_path
}

output "golden_ami_id" {
  description = "create_golden_ami = true로 apply한 경우에만 값이 생김"
  value       = try(aws_ami_from_instance.golden[0].id, null)
}

output "cloudtrail_bucket" {
  description = "CloudTrail 로그가 쌓이는 S3 버킷 이름"
  value       = try(aws_s3_bucket.cloudtrail[0].bucket, null)
}
