# 이 파일이 모든 인프라를 연결합니다.

provider "aws" {
  region = var.aws_region
}

# SSH 키 생성
resource "tls_private_key" "deployer" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# AWS에 공개키 등록
resource "aws_key_pair" "deployer" {
  key_name   = "k3s-deployer"
  public_key = tls_private_key.deployer.public_key_openssh
}

# 보안 그룹: 80번(HTTP)과 22번(SSH) 문을 엽니다.
resource "aws_security_group" "web_sg" {
  name = "web_server_sg"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 실제로는 본인 IP만 허용하는 게 좋습니다.
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
# 모니터링 서버 전용 보안 그룹 
resource "aws_security_group" "monitoring_sg" {
  name = "monitoring_server_sg"

  ingress {
    from_port   = 9090 # 프로메테우스 기본 포트
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22 # SSH 접속용 
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] 
  }
}
# EC2 설정에 보안 그룹 연결
# 통합된 EC2 생성 코드
resource "aws_instance" "web_server" {
  count                  = 2
  ami                    = "ami-040c33c6a51fd5d96" 
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name               = aws_key_pair.deployer.key_name

  tags = { 
    Name = "My-Web-Server-${count.index}" 
  }
}
resource "aws_instance" "monitoring_server" {
  ami                    = "ami-040c33c6a51fd5d96" # 동일한 Ubuntu 이미지 사용 [cite: 2, 5]
  instance_type          = "t3.micro"             # 프로메테우스는 메모리를 많이 쓰므로 t2.medium 추천
  vpc_security_group_ids = [aws_security_group.monitoring_sg.id]
  key_name               = aws_key_pair.deployer.key_name

  tags = {
    Name = "Monitoring-Server-Prometheus" # 모니터링 전용 태그 [cite: 3]
  }
}
# 1. 파이썬 코드를 람다용 zip 파일로 압축 (자동화)
data "archive_file" "start_zip" {
  type        = "zip"
  source_file = "${path.module}/ec2_start.py"
  output_path = "${path.module}/ec2_start.zip"
}

data "archive_file" "stop_zip" {
  type        = "zip"
  source_file = "${path.module}/ec2_stop.py"
  output_path = "${path.module}/ec2_stop.zip"
}

# 2. 람다용 IAM 역할(Role) 생성
resource "aws_iam_role" "lambda_role" {
  name = "ec2_scheduler_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# 3. EC2 제어 권한(Policy) 정의 및 연결
resource "aws_iam_role_policy" "ec2_policy" {
  name = "ec2_control_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:StartInstances", "ec2:StopInstances", "ec2:DescribeInstances"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# 4. 람다 함수 정의 (시작용)
resource "aws_lambda_function" "ec2_start_lambda" {
  filename         = data.archive_file.start_zip.output_path
  function_name    = "EC2_Start_Function"
  role             = aws_iam_role.lambda_role.arn
  handler          = "ec2_start.lambda_handler"
  runtime          = "python3.9"

  environment {
    variables = {
      # [중요!] 생성된 EC2 2대의 ID를 쉼표로 합쳐서 자동으로 전달합니다.
      INSTANCE_IDS = join(",", aws_instance.web_server[*].id)
    }
  }
}

# 5. 람다 함수 정의 (중지용)
resource "aws_lambda_function" "ec2_stop_lambda" {
  filename         = data.archive_file.stop_zip.output_path
  function_name    = "EC2_Stop_Function"
  role             = aws_iam_role.lambda_role.arn
  handler          = "ec2_stop.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.stop_zip.output_base64sha256

  environment {
    variables = {
      INSTANCE_IDS = join(",", aws_instance.web_server[*].id)
    }
  }
}

# 6. EventBridge (스케줄러) - 10시 시작
resource "aws_cloudwatch_event_rule" "start_rule" {
  name                = "ec2_start_rule"
  schedule_expression = "cron(0 1 * * ? *)" # UTC 01:00 = KST 10:00
}

resource "aws_cloudwatch_event_target" "start_target" {
  rule      = aws_cloudwatch_event_rule.start_rule.name
  target_id = "start_lambda"
  arn       = aws_lambda_function.ec2_start_lambda.arn
}

# 7. EventBridge (스케줄러) - 14시 중지
resource "aws_cloudwatch_event_rule" "stop_rule" {
  name                = "ec2_stop_rule"
  schedule_expression = "cron(0 5 * * ? *)" # UTC 05:00 = KST 14:00
}

resource "aws_cloudwatch_event_target" "stop_target" {
  rule      = aws_cloudwatch_event_rule.stop_rule.name
  target_id = "stop_lambda"
  arn       = aws_lambda_function.ec2_stop_lambda.arn
}

# 8. EventBridge가 람다를 호출할 수 있게 권한 부여
resource "aws_lambda_permission" "allow_start" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_start_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.start_rule.arn
}

resource "aws_lambda_permission" "allow_stop" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_stop_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop_rule.arn
}

# 9. 개인키를 로컬 파일로 저장
resource "local_file" "private_key" {
  content         = tls_private_key.deployer.private_key_pem
  filename        = "${path.module}/ansible/keys/deployer.pem"
  file_permission = "0600"
}

# 10. Ansible 인벤토리 파일 자동 생성
resource "local_file" "ansible_inventory" {
  content = <<-EOT
[master]
${aws_instance.web_server[0].public_ip} ansible_host=${aws_instance.web_server[0].public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=${local_file.private_key.filename}

[worker]
${aws_instance.web_server[1].public_ip} ansible_host=${aws_instance.web_server[1].public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=${local_file.private_key.filename}

[monitoring]
${aws_instance.monitoring_server.public_ip} ansible_host=${aws_instance.monitoring_server.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=${local_file.private_key.filename}

[k3s_cluster:children]
master
worker

[k3s_cluster:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=${local_file.private_key.filename}
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[monitoring:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=${local_file.private_key.filename}
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOT
  filename = "${path.module}/ansible/inventory/aws.ini"

  depends_on = [aws_instance.web_server, aws_instance.monitoring_server, local_file.private_key]
}