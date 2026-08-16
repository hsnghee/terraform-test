# Terraform - Trust Boundary 실험 인프라 (OS 파트)

`EC2-Docker-Compose-통합-아키텍처.md` 다이어그램에서 **실제로 AWS에 떠야 하는 부분**만 코드화한 것. 

---

## 0. 사전 준비

- IAM 사용자로 로그인 (root 아님), VPC·EC2·IAM·S3·CloudTrail 만들 수 있는 권한 필요 → 랩이면 `AdministratorAccess`
- Terraform `>= 1.6.0`, AWS Provider `~> 6.0`

---

## 1. 설정값 입력 (선택)

```bash
cp terraform.tfvars.example terraform.tfvars
```

기본값 그대로 apply해도 동작함. 바꾸고 싶으면 `terraform.tfvars`에서:

```hcl
budget_alert_email             = "you@example.com"  # 예산 80% 초과 알림 받을 이메일, 비우면 알림 없이 한도만 생성
create_golden_ami               = false               # true로 apply하면 지금 EC2 상태를 AMI로 저장
attach_cloudwatch_agent_policy  = false               # CloudWatch Agent 쓸 거면만 true
```

`terraform.tfvars`는 `.gitignore`에 들어있어서 git엔 안 올라감. 공유는 `.example`만.

---

## 2. 인프라 생성

```bash
terraform init
terraform plan
terraform apply
```

완료 후 접속 (public IP 없음, SSM으로만):

```bash
aws ssm start-session --target <instance-id>
```
(`terraform apply` 출력의 `ssm_connect_command` 그대로 복사)

---

## 3. 확인

```bash
sudo /opt/trial/scripts/check_canary.sh          # Canary 해시 + auditd 이벤트 확인
sudo /opt/trial/scripts/collect_state.sh <run_id> <phase>   # 상태 스냅샷 (Evidence용, /opt/trial/evidence/에 저장)
```

`check_canary.sh`가 확인하는 auditd 키: `canary_access`(Canary 접근) · `exec_trace`(프로세스 실행) · `mount_trace`(마운트) · `perm_change`(권한 변경) · `persistence_cron`/`persistence_systemd`(지속성 경로) · `sudoers_change`/`passwd_change`/`group_change`/`shadow_change`(계정 파일) · `docker_daemon_change`.

**주의**: auditd 로그는 그 EC2 로컬에만 쌓임 (CloudWatch로 안 보냄). `destroy`하면 같이 사라짐.

---

## 4. Golden AMI / 예산 알림 (선택)

```bash
terraform apply -var="create_golden_ami=true"      # 지금 EC2 상태를 AMI로 저장 → golden_ami_id 출력
terraform apply -var="golden_ami_id=ami-xxxxxxxx"  # 이후 재부트스트랩 없이 바로 이 AMI로 기동
terraform apply -var="budget_alert_email=you@example.com"  # 월 10 USD(기본) 80% 초과시 메일
```

---

## 5. 정리

```bash
terraform destroy
```

---

## 원격 state (아직 비활성화, 팀원 여러 명이 apply할 때 전환)

```bash
cd bootstrap && terraform init && terraform apply
# 출력된 state_bucket_name / dynamodb_table_name을 ../backend.tf에 채워넣고 주석 해제
cd .. && terraform init -migrate-state
```

전환 후에도 팀원이 apply해서 같은 결과를 보려면: 같은 AWS 계정 · `backend.tf` 최신 코드 `git pull` · `terraform init` 재실행 · 충분한 IAM 권한, 이 네 가지가 다 맞아야 함. 동시 apply는 DynamoDB 락으로 막힘.

---

## 구조 한눈에

| 파일 | 만드는 것 |
|---|---|
| `vpc.tf` | VPC, Private Subnet, Security Group(inbound 없음, outbound 443/80/53만), SSM VPC Endpoint |
| `nat.tf` | Public Subnet + NAT Gateway (EC2 아웃바운드 인터넷용) |
| `iam.tf` | EC2용 IAM Role (SSM 관리 권한만) |
| `ec2.tf` | Trial EC2 (Ubuntu 24.04, IMDSv2, EBS 암호화) |
| `user_data.sh.tpl` | 부트스트랩 스크립트 — Docker(Compose v2)/auditd 설치, Canary 파일 생성, `check_canary.sh`/`collect_state.sh` 배치 |
| `logging.tf` | VPC Flow Logs, CloudTrail (멀티 리전, 로그 무결성 검증, S3 버킷 암호화·비공개) |
| `budget.tf` | 월간 비용 알림 |
| `ami.tf` | Golden AMI 생성 (`create_golden_ami=true`일 때만) |
| `backend.tf`, `bootstrap/` | 원격 state (S3 + DynamoDB), 지금은 비활성화 |
| `compose/` | Docker Compose 권한 Profile (container-baseline / container-mount-rw) |

## 안 만드는 것

Local Control Panel, Trusted Orchestrator, Policy Gateway, Host/Container Executor, LLM 연동, Evidence Collector/Verifier — 전부 별도 애플리케이션. Terraform은 이것들이 올라갈 EC2·네트워크·권한만 준비함.

## 버전

Terraform `>= 1.6.0` · AWS Provider `~> 6.0` · Ubuntu 24.04(SSM Parameter로 항상 최신) · Docker Compose v2. 버전 올린 뒤엔 `terraform init -upgrade`로 lock 파일 갱신.

## 다음 단계

1. Agent + Policy Gateway + Executor 별도 코드 작성
2. Compose override를 권한 Profile별로 분리
3. Trusted Orchestrator가 이 Terraform을 호출하는 방식 설계
4. 팀원 여러 명 apply 시점에 `bootstrap/`으로 원격 state 전환
