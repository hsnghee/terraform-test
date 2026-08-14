# 원격 state(S3) 설정 자리. 지금은 비활성화 상태 — 로컬 terraform.tfstate를 그대로 쓴다.
#
# 이유: 팀원 여러 명이 각자 apply를 돌리게 되면, 각자 노트북에 있는 로컬 tfstate만으로는
# "지금 AWS에 뭐가 이미 만들어져 있는지"를 서로 알 수 없어서 충돌/중복 생성이 일어난다.
# S3 backend를 쓰면 tfstate 자체를 공용 S3 버킷에 두고, DynamoDB로 동시 apply를 막을 수 있다.
#
# 활성화하는 방법:
# 1) bootstrap/ 폴더에서 `terraform apply`를 한 번 실행해서 S3 버킷 + DynamoDB 테이블을 만든다
# 2) 아래 블록의 주석을 풀고 bucket/dynamodb_table 값을 bootstrap 출력값으로 채운다
# 3) 이 폴더(terraform/)에서 `terraform init -migrate-state`를 실행한다
#    (로컬에 있던 tfstate 내용이 자동으로 S3로 옮겨진다)
#
# terraform {
#   backend "s3" {
#     bucket         = "<bootstrap apply 결과의 state_bucket_name>"
#     key            = "trial/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "<bootstrap apply 결과의 dynamodb_table_name>"
#     encrypt        = true
#   }
# }
