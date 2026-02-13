# AWS 및 키 페어 설정

provider "aws" {
  region = var.aws_region
}
# SSH 키 쌍 생성
resource "tls_private_key" "deployer" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
# AWS에 Public Key 등록
resource "aws_key_pair" "deployer" {
  key_name   = "Hello_kt"
  public_key = tls_private_key.deployer.public_key_openssh
}

# Private Key를 파일로 저장
resource "local_file" "ssh_key" {
  content         = tls_private_key.deployer.private_key_pem
  filename        = "${path.module}/../ansible/key/Hello_kt.pem"
  file_permission = "0600"
}