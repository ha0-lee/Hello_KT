# 변수 설정 파일 
variable "aws_region" {
  description = "AWS 리전 설정"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "프로젝트 이름 (리소스 태그에 사용)"
  type        = string
  default     = "kt-k3s"
}

variable "environment" {
  description = "환경 구분 (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# ==========================================
# NAT Gateway 제어 변수 (비용 절감용)
# ==========================================
variable "enable_nat_gateway" {
  description = <<-EOT
    NAT Gateway 활성화 여부
    - true: NAT Gateway 생성 (시간당 $0.059)
    - false: NAT Gateway 삭제 (비용 절감)
    
    주의: NAT를 비활성화하면 Private Subnet의 EC2들이 인터넷 접속 불가
    EIP는 항상 유지되므로 IP 주소는 변경되지 않음
  EOT
  type        = bool
  default     = false
}

# ==========================================
# 네트워크 설정
# ==========================================
variable "vpc_cidr" {
  description = "VPC CIDR 블록"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "사용할 가용 영역"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c"]
}

# ==========================================
# EC2 설정
# ==========================================
variable "worker_count" {
  description = "Worker 노드 개수"
  type        = number
  default     = 2
}

variable "instance_type" {
  description = "EC2 인스턴스 타입"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "SSH 키 페어 이름"
  type        = string
  default     = "Hello_kt"
}

variable "ubuntu_ami" {
  description = "Ubuntu AMI ID (ap-northeast-2)"
  type        = string
  default     = "ami-040c33c6a51fd5d96" # Ubuntu 22.04 LTS
}

# ==========================================
# Lambda Scheduler 설정
# ==========================================
variable "ec2_start_time" {
  description = "EC2 시작 시간 (UTC cron 표현식)"
  type        = string
  default     = "cron(0 1 * * ? *)" # UTC 01:00 = KST 10:00
}

variable "ec2_stop_time" {
  description = "EC2 중지 시간 (UTC cron 표현식)"
  type        = string
  default     = "cron(0 5 * * ? *)" # UTC 05:00 = KST 14:00
}

variable "tfstate_bucket_name" {
  description = "Terraform 상태 파일을 저장할 S3 버킷 이름"
  type        = string
  default     = "hellokt-terraform-state-985090322396" # 실제 사용 중인 이름
}