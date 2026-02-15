# EC2 인스턴스, 보안 그룹 (실제 서버)

# 모니터링 서버 전용 보안 그룹 
resource "aws_security_group" "monitoring_sg" {
  name   = "monitoring_server_sg"
  vpc_id = aws_vpc.main.id
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
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Grafana Access"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
# 웹 서버용 보안 그룹 (마스터/워커 노드 공용)
resource "aws_security_group" "web_sg" {
  name   = "web_server_sg"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # 배스쳔 서버에서만 SSH 허용
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.monitoring_sg.id]
    description     = "Allow SSH from Bastion only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Web SG에 Monitoring SG로부터의 접근 허용 규칙 추가
resource "aws_security_group_rule" "master_to_worker_node_exporter" {
  type                     = "ingress"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  security_group_id        = aws_security_group.web_sg.id
  source_security_group_id = aws_security_group.monitoring_sg.id
  description              = "Prometheus to Worker Node Exporter"
}
resource "aws_security_group_rule" "master_to_worker_cAvisor" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.web_sg.id
  source_security_group_id = aws_security_group.monitoring_sg.id
  description              = "Prometheus to Worker CAdvisor"
}
resource "aws_security_group_rule" "master_to_worker_kubelet" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.web_sg.id
  source_security_group_id = aws_security_group.monitoring_sg.id
  description              = "Master to Worker Kubelet API"
}

resource "aws_security_group_rule" "monitoring_to_master_api" {
  type                     = "ingress"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.web_sg.id        # 대상: Master/Worker
  source_security_group_id = aws_security_group.monitoring_sg.id # 출발: Monitoring
  description              = "Monitoring to K8s API Server"
}
# 동일 SG(web_sg)를 가진 서버끼리는 모든 통신 허용 (K8s 통신용)
resource "aws_security_group_rule" "allow_internal_all" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1" # All traffic
  security_group_id        = aws_security_group.web_sg.id
  source_security_group_id = aws_security_group.web_sg.id
  description              = "Allow all internal traffic between Master and Workers"
}
# EC2 설정에 보안 그룹 연결
# 통합된 EC2 생성 코드
resource "aws_instance" "Worker_server" {
  count                  = 2
  ami                    = "ami-040c33c6a51fd5d96"
  instance_type          = "t3.small"
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  # 계획에 맞춰 private_2와 private_3에 배치
  subnet_id = element([aws_subnet.private_2.id, aws_subnet.private_3.id], count.index)
  key_name  = aws_key_pair.deployer.key_name
  tags = {
    Name = "Worker-Node-${count.index + 1}"
  }
}
resource "aws_instance" "Master_server" {
  ami                    = "ami-040c33c6a51fd5d96"
  instance_type          = "t3.small"
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  subnet_id              = aws_subnet.private_1.id
  key_name               = aws_key_pair.deployer.key_name
  tags = {
    Name = "Master-Node"
  }
}
resource "aws_instance" "monitoring_server" {
  ami                    = "ami-040c33c6a51fd5d96" # 동일한 Ubuntu 이미지 사용
  instance_type          = "t3.small"              # 프로메테우스는 메모리를 많이 쓰므로 t2.medium 추천
  vpc_security_group_ids = [aws_security_group.monitoring_sg.id]
  subnet_id              = aws_subnet.public_1.id
  iam_instance_profile   = aws_iam_instance_profile.monitoring_profile.name
  key_name               = aws_key_pair.deployer.key_name
  tags = {
    Name = "Monitoring-Server" # 모니터링 전용 태그
  }
}

# 146 ~ 154 한정현 30080 포트 인바인드 규칙 추가
resource "aws_security_group_rule" "open_lunch_nodeport_public" {
  type              = "ingress"
  from_port         = 30080
  to_port           = 30080
  protocol          = "tcp"
  security_group_id = aws_security_group.web_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Open Lunch NodePort 30080 to public"
}


# 1. 모니터링 서버용 역할
resource "aws_iam_role" "monitoring_role" {
  name = "monitoring_server_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# 2. EC2 정보를 읽을 수 있는 권한 부여 (Read Only)
resource "aws_iam_role_policy_attachment" "ec2_read" {
  role       = aws_iam_role.monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}

# 3. EC2에 이 신분증을 부착할 '프로필' 생성
resource "aws_iam_instance_profile" "monitoring_profile" {
  name = "monitoring_instance_profile"
  role = aws_iam_role.monitoring_role.name
}
