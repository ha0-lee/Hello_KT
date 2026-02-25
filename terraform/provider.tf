# AWS 및 키 페어 설정
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
# SSH 키 생성
resource "tls_private_key" "deployer" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# AWS에 공개키 등록
resource "aws_key_pair" "hello_kt_key" {
  key_name   = "Hello_kt"
  public_key = tls_private_key.deployer.public_key_openssh
}

# [추가 필수] 테라폼이 만든 열쇠를 내 컴퓨터에 실물 .pem 파일로 저장
resource "local_file" "ssh_key" {
  content         = tls_private_key.deployer.private_key_pem
  filename        = "${path.module}/Hello_kt.pem"
  file_permission = "0600"
}
