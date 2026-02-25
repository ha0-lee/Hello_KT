# Terraform Outputs
# 배포 후 필요한 정보들을 출력

# ==========================================
# NAT Gateway 존재 여부 확인
# ==========================================
locals {
  # try-catch로 안전하게 리소스 존재 확인
  nat_gateway_exists = try(aws_nat_gateway.nat_gw.id, null) != null
  nat_eip_exists     = try(aws_eip.nat_eip.id, null) != null
  nat_route_exists   = try(aws_route.private_internet_route.id, null) != null
}

# ==========================================
# VPC 정보
# ==========================================
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR 블록"
  value       = aws_vpc.main.cidr_block
}

# ==========================================
# NAT Gateway 정보
# ==========================================
output "nat_gateway_status" {
  description = "NAT Gateway 활성화 여부"
  value       = local.nat_gateway_exists ? "✅ Enabled - Private 서브넷이 인터넷 접속 가능" : "❌ Disabled - Private 서브넷은 인터넷 접속 불가 (비용 절감 중)"
}

output "nat_gateway_id" {
  description = "NAT Gateway ID (활성화된 경우)"
  value       = local.nat_gateway_exists ? aws_nat_gateway.nat_gw.id : "NAT Gateway가 비활성화되어 있습니다"
}

output "nat_eip_address" {
  description = "NAT Gateway의 Elastic IP (활성화된 경우)"
  value       = local.nat_eip_exists ? aws_eip.nat_eip.public_ip : "NAT Gateway가 비활성화되어 있습니다"
}

output "nat_cost_info" {
  description = "NAT Gateway 비용 정보"
  value       = local.nat_gateway_exists ? "💰 현재 시간당 $0.045 + 데이터 비용 발생 중" : "💰 비용 절감 중 (NAT Gateway 없음)"
}

output "nat_control_commands" {
  description = "NAT Gateway 제어 명령어"
  value = {
    현재상태 = local.nat_gateway_exists ? "✅ 활성화" : "❌ 비활성화"
    활성화  = "bash nat_create.sh"
    비활성화 = "bash nat_destroy.sh"
    상태확인 = "terraform state list | grep nat"
  }
}

# ==========================================
# EC2 인스턴스 정보
# ==========================================
output "master_instance_id" {
  description = "Master 노드 인스턴스 ID"
  value       = aws_instance.Master_server.id
}

output "master_private_ip" {
  description = "Master 노드 Private IP"
  value       = aws_instance.Master_server.private_ip
}

output "worker_instance_ids" {
  description = "Worker 노드들의 인스턴스 ID"
  value       = aws_instance.Worker_server[*].id
}

output "worker_private_ips" {
  description = "Worker 노드들의 Private IP"
  value       = aws_instance.Worker_server[*].private_ip
}

output "monitoring_instance_id" {
  description = "Monitoring 서버 인스턴스 ID"
  value       = aws_instance.monitoring_server.id
}

output "monitoring_public_ip" {
  description = "Monitoring 서버 Public IP (Bastion + Prometheus + Grafana)"
  value       = aws_instance.monitoring_server.public_ip
}

# ==========================================
# 접속 정보
# ==========================================
output "ssh_bastion" {
  description = "Bastion(Monitoring) 서버 SSH 접속 명령어"
  value       = "ssh -i Hello_kt.pem ubuntu@${aws_instance.monitoring_server.public_ip}"
}

output "ssh_master_via_bastion" {
  description = "Master 노드 SSH 접속 명령어 (Bastion 경유)"
  value       = "ssh -i Hello_kt.pem -o ProxyCommand='ssh -W %h:%p -q ubuntu@${aws_instance.monitoring_server.public_ip} -i Hello_kt.pem' ubuntu@${aws_instance.Master_server.private_ip}"
}

output "prometheus_url" {
  description = "Prometheus Web UI URL"
  value       = "http://${aws_instance.monitoring_server.public_ip}:9090"
}

output "grafana_url" {
  description = "Grafana Web UI URL"
  value       = "http://${aws_instance.monitoring_server.public_ip}:3000"
}

# ==========================================
# Lambda Scheduler 정보
# ==========================================
output "lambda_start_function" {
  description = "EC2 시작 Lambda 함수 이름"
  value       = aws_lambda_function.ec2_start_lambda.function_name
}

output "lambda_stop_function" {
  description = "EC2 중지 Lambda 함수 이름"
  value       = aws_lambda_function.ec2_stop_lambda.function_name
}

output "scheduler_info" {
  description = "EC2 자동 스케줄 정보"
  value = {
    start_time = "매일 10:00 KST (UTC 01:00)"
    stop_time  = "매일 14:00 KST (UTC 05:00)"
    managed_instances = concat(
      aws_instance.Worker_server[*].id,
      [aws_instance.Master_server.id],
      [aws_instance.monitoring_server.id]
    )
  }
}

# ==========================================
# Ansible 정보
# ==========================================
output "ansible_inventory_path" {
  description = "Ansible 인벤토리 파일 경로"
  value       = "${path.module}/ansible/inventory/aws.ini"
}

output "ansible_command" {
  description = "Ansible 실행 예시 명령어"
  value       = "ansible-playbook -i ansible/inventory/aws.ini playbooks/your-playbook.yml"
}

# ==========================================
# 빠른 참조 가이드
# ==========================================
output "quick_guide" {
  description = "빠른 사용 가이드"
  value       = <<-EOT
  
  ╔═══════════════════════════════════════════════════════════════╗
  ║           🚀 K3s Cluster 배포 완료                            ║
  ╚═══════════════════════════════════════════════════════════════╝
  
  📍 NAT Gateway 상태: ${local.nat_gateway_exists ? "✅ 활성화" : "❌ 비활성화"}
  
  🔧 NAT Gateway 제어:
     활성화:   bash nat_create.sh
     비활성화: bash nat_destroy.sh
     상태확인: terraform state list | grep nat
  
  🖥️  서버 접속:
     Bastion: ssh -i Hello_kt.pem ubuntu@${aws_instance.monitoring_server.public_ip}
     Master: (Bastion 경유 필요)
  
  📊 모니터링:
     Prometheus: http://${aws_instance.monitoring_server.public_ip}:9090
     Grafana: http://${aws_instance.monitoring_server.public_ip}:3000
  
  ⏰ 자동 스케줄:
     시작: 매일 10:00 KST
     중지: 매일 14:00 KST
  
  💰 비용 절감:
     NAT 활성화 시: 시간당 $0.045 (하루 약 $1.08)
     작업 종료 후 'bash nat_destroy.sh' 실행 권장!
  
  ⚠️  주의사항:
     - NAT 비활성화 시 Private 서브넷은 인터넷 접속 불가
     - VPC 내부 통신과 Bastion 접속은 항상 가능
     - 패키지 설치 등 인터넷 필요 작업 전에 NAT 활성화 필요
  
  EOT
}