# Terraform - Trust Boundary 실험 인프라 (OS/Ubuntu 파트)

`EC2-Docker-Compose-통합-아키텍처.md`와 팀 다이어그램을 기반으로, **Terraform이 실제로 만들 수 있는 AWS 인프라 부분만** 코드화한 것입니다.

## 이 코드가 만드는 것 (다이어그램 대응)

| 다이어그램 요소 | Terraform 리소스 | 파일 |
|---|---|---|
| VPC / Private Subnet | `aws_vpc`, `aws_subnet` | `vpc.tf` |
| Security Group (inbound 없음) | `aws_security_group` | `vpc.tf` |
| AWS SSM (관리 경로) | `aws_vpc_endpoint`(ssm 3종) | `vpc.tf` |
| IAM (Trusted Orchestrator용 최소 권한) | `aws_iam_role`, `aws_iam_instance_profile` | `iam.tf` |
| Trial EC2 | `aws_instance` | `ec2.tf` |
| VPC Flow Logs | `aws_flow_log` | `logging.tf` |
| AWS CloudTrail | `aws_cloudtrail` | `logging.tf` |
| auditd 설치·규칙 (Canary 접근/지속성/sudoers/exec 감시) | `aws_instance.user_data` (부트스트랩 스크립트) | `ec2.tf` |
| Host Canary 파일 (`/opt/trial/canary/protected-file.txt`) | `aws_instance.user_data` (부트스트랩 스크립트) | `ec2.tf` |

## 이 코드가 만들지 않는 것 (별도 애플리케이션 개발 필요)

다이어그램의 아래 구성요소는 AWS 인프라가 아니라 **직접 작성해야 하는 프로그램**입니다. Terraform은 이들이 올라갈 자리(EC2, 네트워크, 권한)만 준비해줄 뿐입니다.

- Local Control Panel, Harness Controller, Model Adapter — 로컬/외부에서 도는 프론트엔드·오케스트레이션 코드
- Trusted Orchestrator의 판단 로직 — Terraform은 이 Orchestrator가 "호출하는" 도구일 뿐, Orchestrator 자체는 별도 서비스(Python 등)
- Policy Gateway, Host Executor, Container Executor — EC2 내부에서 도는 애플리케이션
- OpenRouter LLM 연동 (Model Adapter → 외부 API) — 별도 코드
- Read-only Evidence Collector, Independent Effect Verifier, Cleanup Verifier, Evidence Store — 검증 로직/저장소 애플리케이션
- Docker Compose Profile 자체의 세부 override (권한 Profile별 mount/capability 조합) — `docker-compose.yml` + override 파일로 별도 관리

이 부분들은 다음 단계에서 별도 리포지토리/디렉토리(예: `orchestrator/`, `agent/`, `gateway/`)로 개발하고, Terraform은 그 위에서 실행될 EC2와 권한만 제공하는 역할로 남습니다.

## 권한 로그 파이프라인 확인 (Agent 없이 수동 검증)

Agent/Gateway/Executor가 아직 없어도, EC2 부트스트랩 단계에서 auditd 설치·규칙 적용과 Host Canary 파일 준비까지는 끝나 있습니다. SSM으로 접속해서 사람이 직접 권한을 바꿔가며 로그가 실제로 남는지 확인할 수 있습니다.

```bash
aws ssm start-session --target <instance-id>
sudo /opt/trial/scripts/check_canary.sh
```

Canary 해시가 바뀌었는지, `auditd`가 `canary_access`/`exec_trace`/`persistence_cron`/`sudoers_change` 키로 이벤트를 실제로 잡아내는지부터 확인한 뒤, Agent가 들어왔을 때 같은 방식으로 비교하면 됩니다.

**주의**: `user_data`는 EC2가 처음 부팅될 때 한 번만 실행됩니다. 이미 떠 있는 인스턴스에는 이번 변경이 자동 반영되지 않으니, `terraform apply -replace=aws_instance.trial[0]`로 재생성하거나 `terraform destroy && terraform apply`로 새로 띄워야 합니다.

## 설계상 의도적으로 넣은 제약

- EC2는 **Private Subnet, public IP 없음** — 관리 접속은 SSM만 사용 (인터넷 게이트웨이/NAT 없이 SSM VPC Endpoint로 처리)
- Security Group **inbound 없음** — 문서 13장 원칙 그대로
- IAM Role은 **SSM 관리 권한만** 부여, Agent 작업용 AWS 권한은 포함하지 않음 (문서 6.4 원칙)
- EBS **암호화 + 인스턴스 종료 시 자동 삭제**
- IMDSv2 강제 (`http_tokens = "required"`)
- `trial_ec2_count = 1` — "한 번에 EC2 한 대만 사용" 원칙 반영

## 사용 방법

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

이 구성은 Private Subnet + public IP 없음이라, 브라우저로 바로 접속은 안 됩니다. 접속은 SSM으로 합니다.

```bash
aws ssm start-session --target <instance-id>
```
(`terraform apply` 결과의 `ssm_connect_command` 출력값을 그대로 복사해서 쓰면 됩니다.)

## Golden AMI 적용

Golden AMI가 준비되면:
```bash
terraform apply -var="golden_ami_id=ami-xxxxxxxx"
```

## 정리

```bash
terraform destroy
```

## 원격 state (아직 비활성화)

지금은 `terraform.tfstate`가 로컬 노트북에만 있어서, 팀원이 각자 apply를 돌리면 서로 다른 결과가 나오거나 충돌이 납니다. `backend.tf`에 S3 원격 state 설정 자리를 미리 만들어뒀고(지금은 주석 처리), 그 S3 버킷/DynamoDB 락 테이블을 만드는 `bootstrap/` 폴더도 별도로 준비해뒀습니다.

여러 명이 같이 apply하게 되는 시점에 이렇게 전환합니다:

```bash
cd bootstrap
terraform init
terraform apply
# 출력된 state_bucket_name / dynamodb_table_name을 ../backend.tf에 채워넣고 주석 해제

cd ..
terraform init -migrate-state
```

## mount 시스템콜 감시

Canary 파일 접근(`canary_access`)이나 프로세스 실행(`exec_trace`)뿐 아니라, 컨테이너/프로세스가 **새로운 마운트를 시도하는 것 자체**도 `mount_trace` 키로 감시하도록 auditd 규칙에 추가했습니다 (`ec2.tf`). `check_canary.sh`에서 같이 확인할 수 있습니다.

## 다음 단계 제안

1. 이 인프라 위에서 돌아갈 최소 Agent + Policy Gateway + Executor를 별도 코드로 작성 (Phase 1)
2. Docker Compose override 파일을 권한 Profile별로 분리 (`container-baseline.yml`, `container-mount-rw.yml` 등)
3. Trusted Orchestrator가 이 Terraform을 호출하는 방식(예: `terraform apply` 를 하위 프로세스로 실행하거나 Terraform Cloud API 사용) 설계
4. 팀원이 여러 명이서 apply하게 되면 `bootstrap/`으로 원격 state 전환
