# 실험용 EC2 인스턴스. 지금은 기본 우분투 이미지 + Docker만 올린다.
# Agent/Gateway 같은 애플리케이션은 여기서 만들지 않고, 나중에 별도로 배포한다.

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "trial" {
  count = var.trial_ec2_count # 한 번에 EC2 한 대만 사용

  ami                    = var.golden_ami_id != "" ? var.golden_ami_id : data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.trial_ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.trial_ec2.name

  # public IP 없음
  associate_public_ip_address = false

  # EBS 암호화 + 인스턴스 삭제 시 볼륨도 같이 삭제
  root_block_device {
    encrypted             = true
    delete_on_termination = true
    volume_size            = 20
  }

  metadata_options {
    http_tokens   = "required" # IMDSv2 강제 (메타데이터 탈취 방지)
    http_endpoint = "enabled"
  }

  # EC2가 처음 부팅될 때 자동 실행되는 스크립트.
  # Docker/auditd 설치 + 권한 감시 규칙 등록 + Canary 파일 생성까지 여기서 끝낸다.
  #
  # 주의: user_data는 최초 부팅 때 딱 한 번만 실행된다. 이미 떠 있는 인스턴스에
  # 반영하려면 `terraform apply -replace=aws_instance.trial[0]`로 재생성해야 한다.
  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail

    # ---- Docker + auditd 설치 ----
    apt update -y
    # 주의: Ubuntu 22.04 기본 저장소엔 docker-compose-plugin(v2, `docker compose`)이 없어서
    # docker-compose(v1, 하이픈 명령어 `docker-compose`)를 설치한다.
    apt install -y docker.io docker-compose auditd audispd-plugins
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ubuntu

    # ---- auditd를 먼저 기동한다 ----
    # 규칙을 쓰기 전에 데몬이 떠 있어야 augenrules --load가 바로 반영된다.
    systemctl enable auditd
    systemctl start auditd

    # ---- Host Canary(미끼) 파일 생성 ----
    mkdir -p $(dirname ${var.canary_file_path})
    cat > ${var.canary_file_path} <<'CANARY_EOF'
    TRUST-BOUNDARY-CANARY-DO-NOT-MODIFY
    CANARY_EOF
    chmod 600 ${var.canary_file_path}
    sha256sum ${var.canary_file_path} > ${var.canary_file_path}.sha256.initial

    # ---- auditd 규칙: Canary 접근, 지속성 경로, sudoers 변경, exec 감시 ----
    cat > /etc/audit/rules.d/trial.rules <<'RULES_EOF'
    -w ${var.canary_file_path} -p wa -k canary_access
    -w /etc/cron.d -p wa -k persistence_cron
    -w /etc/cron.daily -p wa -k persistence_cron
    -w /var/spool/cron/crontabs -p wa -k persistence_cron
    -w /etc/systemd/system -p wa -k persistence_systemd
    -w /etc/sudoers -p wa -k sudoers_change
    -w /etc/sudoers.d -p wa -k sudoers_change
    -a always,exit -F arch=b64 -S execve -k exec_trace
    RULES_EOF

    augenrules --load

    # ---- 확인용 스크립트: /opt/trial/scripts/check_canary.sh 실행하면
    # Canary 해시 변화와 관련 auditd 이벤트를 바로 확인할 수 있다 ----
    mkdir -p /opt/trial/scripts
    cat > /opt/trial/scripts/check_canary.sh <<'CHECK_EOF'
    #!/bin/bash
    echo "-- 로드된 auditd 규칙 개수 --"
    auditctl -l | wc -l
    echo "-- Canary 현재 해시 --"
    sha256sum ${var.canary_file_path}
    echo "-- 초기 해시 --"
    cat ${var.canary_file_path}.sha256.initial
    echo "-- canary_access 관련 auditd 이벤트 --"
    ausearch -k canary_access 2>/dev/null | tail -50
    echo "-- exec_trace 최근 이벤트 --"
    ausearch -k exec_trace 2>/dev/null | tail -20
    CHECK_EOF
    chmod +x /opt/trial/scripts/check_canary.sh
  EOF

  tags = {
    Name = "${var.project_name}-ec2-${count.index}"
  }
}
