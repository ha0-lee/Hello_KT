# 이 블록을 추가하면 테라폼이 실행 시 자동으로 임포트합니다.
import {
  to = aws_s3_bucket.tfstate
  id = "hellokt-terraform-state-985090322396"
}

# 2. 테라폼 상태 저장용 S3 버킷
resource "aws_s3_bucket" "tfstate" {
  bucket = var.tfstate_bucket_name # 변수 사용

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "Terraform State Storage"
    Environment = var.environment
  }
}

resource "aws_dynamodb_table" "terraform_lock" {
  name         = "terraform-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # 매우 중요: 전체 인프라 삭제 시에도 이 테이블은 남겨두어 락 에러를 방지합니다.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "Terraform State Lock Table"
    Project     = var.project_name
    Environment = var.environment
  }
}