# IAM Roles, Policies, Instance Profiles
# 모니터링 서버와 Lambda용 IAM 설정

# ==========================================
# 모니터링 서버용 IAM Role
# ==========================================
resource "aws_iam_role" "monitoring_role" {
  name = "${var.project_name}-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.project_name}-Monitoring-Role"
    Environment = var.environment
    Purpose     = "Monitoring Server EC2 Role"
  }
}

# EC2 읽기 권한 부여 (Prometheus가 EC2 정보 수집용)
resource "aws_iam_role_policy_attachment" "ec2_read" {
  role       = aws_iam_role.monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}

# EC2에 Role을 부착하기 위한 Instance Profile
resource "aws_iam_instance_profile" "monitoring_profile" {
  name = "${var.project_name}-monitoring-profile"
  role = aws_iam_role.monitoring_role.name

  tags = {
    Name        = "${var.project_name}-Monitoring-Profile"
    Environment = var.environment
  }
}