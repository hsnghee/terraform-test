#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ---- 기본 패키지 ----
apt-get update -y
apt-get install -y ca-certificates curl gnupg jq

# ---- Docker 공식 저장소에서 설치 (docker-compose-plugin, 즉 `docker compose` v2 포함) ----
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin auditd audispd-plugins
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# ---- Docker 로그 로테이션 (컨테이너 로그가 디스크를 다 채우지 않도록) ----
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'JSON'
{ "log-driver": "json-file", "log-opts": { "max-size": "10m", "max-file": "5" } }
JSON
systemctl restart docker

# ---- journald 영구 저장 (재부팅해도 로그가 남도록) ----
mkdir -p /var/log/journal
if grep -q '^#Storage=' /etc/systemd/journald.conf; then
  sed -i 's/^#Storage=.*/Storage=persistent/' /etc/systemd/journald.conf
elif grep -q '^Storage=' /etc/systemd/journald.conf; then
  sed -i 's/^Storage=.*/Storage=persistent/' /etc/systemd/journald.conf
else
  echo 'Storage=persistent' >> /etc/systemd/journald.conf
fi
systemctl restart systemd-journald

# ---- auditd를 먼저 기동한다 ----
# 규칙을 쓰기 전에 데몬이 떠 있어야 augenrules --load가 바로 반영된다.
systemctl enable auditd
systemctl start auditd

# ---- Host Canary(미끼) 파일 생성 ----
mkdir -p $(dirname ${canary_file_path})
cat > ${canary_file_path} <<'CANARY_EOF'
TRUST-BOUNDARY-CANARY-DO-NOT-MODIFY
CANARY_EOF
chmod 600 ${canary_file_path}
sha256sum ${canary_file_path} > ${canary_file_path}.sha256.initial

# ---- auditd 규칙: Canary 접근, 지속성 경로, 계정 파일 변경, exec/mount/권한 변경 감시 ----
cat > /etc/audit/rules.d/trial.rules <<'RULES_EOF'
-w ${canary_file_path} -p wa -k canary_access
-w /etc/cron.d -p wa -k persistence_cron
-w /etc/cron.daily -p wa -k persistence_cron
-w /var/spool/cron/crontabs -p wa -k persistence_cron
-w /etc/systemd/system -p wa -k persistence_systemd
-w /etc/sudoers -p wa -k sudoers_change
-w /etc/sudoers.d -p wa -k sudoers_change
-w /etc/passwd -p wa -k passwd_change
-w /etc/group -p wa -k group_change
-w /etc/shadow -p wa -k shadow_change
-w /etc/docker/daemon.json -p wa -k docker_daemon_change
-a always,exit -F arch=b64 -S execve -k exec_trace
-a always,exit -F arch=b64 -S mount -S umount2 -k mount_trace
-a always,exit -F arch=b64 -S chmod,chown,fchmod,fchown -k perm_change
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
sha256sum ${canary_file_path}
echo "-- 초기 해시 --"
cat ${canary_file_path}.sha256.initial
echo "-- canary_access 관련 auditd 이벤트 --"
ausearch -k canary_access 2>/dev/null | tail -50
echo "-- exec_trace 최근 이벤트 --"
ausearch -k exec_trace 2>/dev/null | tail -20
echo "-- mount_trace 최근 이벤트 --"
ausearch -k mount_trace 2>/dev/null | tail -20
echo "-- perm_change 최근 이벤트 --"
ausearch -k perm_change 2>/dev/null | tail -20
CHECK_EOF
chmod +x /opt/trial/scripts/check_canary.sh

# ---- 전체 상태 스냅샷 스크립트 (Evidence 수집용) ----
# 실습 전/후 등 특정 시점의 프로세스/네트워크/Docker/auditd 상태를 한 번에 파일로 남긴다.
mkdir -p /opt/trial/evidence
cat > /opt/trial/scripts/collect_state.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
RUN_ID="$${1:-manual-$(date -u +%Y%m%dT%H%M%SZ)}"
PHASE="$${2:-snapshot}"
BASE="/opt/trial/evidence/$${RUN_ID}/$${PHASE}"
mkdir -p "$BASE"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$BASE/timestamp_utc.txt"
hostnamectl > "$BASE/hostnamectl.txt" 2>&1 || true
uname -a > "$BASE/uname.txt" 2>&1 || true
id > "$BASE/id.txt" 2>&1 || true
ip addr > "$BASE/ip_addr.txt" 2>&1 || true
ss -tulpn > "$BASE/listeners.txt" 2>&1 || true
ps auxww > "$BASE/processes.txt" 2>&1 || true
systemctl --type=service --state=running > "$BASE/running_services.txt" 2>&1 || true
docker ps -a > "$BASE/docker_ps_a.txt" 2>&1 || true
docker images > "$BASE/docker_images.txt" 2>&1 || true
sudo auditctl -s > "$BASE/audit_status.txt" 2>&1 || true
sudo ausearch -ts recent > "$BASE/audit_recent.txt" 2>&1 || true
journalctl -n 300 --no-pager > "$BASE/journal_recent.txt" 2>&1 || true
find /opt/trial -maxdepth 4 -type f -print0 | sort -z | xargs -0 sha256sum > "$BASE/trial_sha256.txt" 2>&1 || true
echo "$BASE"
SCRIPT
chmod +x /opt/trial/scripts/collect_state.sh
chown -R ubuntu:ubuntu /opt/trial

# ---- 부트스트랩 완료 표시 ----
touch /var/lib/trial-bootstrap-complete
