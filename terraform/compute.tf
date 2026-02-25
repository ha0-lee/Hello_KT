# EC2 인스턴스, 보안 그룹 (실제 서버)

# 모니터링 서버 전용 보안 그룹 
# ==========================================
# Security Groups (No inline ingress rules)
# ==========================================

# -------------------------------
# Monitoring Security Group
# -------------------------------
resource "aws_security_group" "monitoring_sg" {
  name        = "${var.project_name}-monitoring-sg"
  description = "Security group for monitoring server (Bastion + Prometheus + Grafana)"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-Monitoring-SG"
    Environment = var.environment
    Role        = "Monitoring-Bastion"
  }
}

# -------------------------------
# Web Security Group (Master + Worker)
# -------------------------------
resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Security group for K3s Master and Worker nodes"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-Web-SG"
    Environment = var.environment
    Role        = "K3s-Cluster"
  }
}

# ==========================================
# Monitoring SG Ingress Rules
# ==========================================

resource "aws_security_group_rule" "monitoring_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.monitoring_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "SSH access"
}

resource "aws_security_group_rule" "monitoring_prometheus" {
  type              = "ingress"
  from_port         = 9090
  to_port           = 9090
  protocol          = "tcp"
  security_group_id = aws_security_group.monitoring_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Prometheus Access"
}

resource "aws_security_group_rule" "monitoring_grafana" {
  type              = "ingress"
  from_port         = 3000
  to_port           = 3000
  protocol          = "tcp"
  security_group_id = aws_security_group.monitoring_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Grafana Access"
}

# ==========================================
# Web SG Ingress Rules
# ==========================================

resource "aws_security_group_rule" "web_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.web_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTP Access"
}

resource "aws_security_group_rule" "web_ssh_from_monitoring" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.web_sg.id
  source_security_group_id = aws_security_group.monitoring_sg.id
  description              = "Allow SSH from Bastion only"
}

# ==========================================
# K3s / Monitoring Communication
# ==========================================

resource "aws_security_group_rule" "monitoring_to_node_exporter" {
  type                     = "ingress"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  security_group_id        = aws_security_group.web_sg.id
  source_security_group_id = aws_security_group.monitoring_sg.id
  description              = "Prometheus to Worker Node Exporter"
}

resource "aws_security_group_rule" "monitoring_to_cadvisor" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.web_sg.id
  source_security_group_id = aws_security_group.monitoring_sg.id
  description              = "Prometheus to Worker CAdvisor"
}

resource "aws_security_group_rule" "monitoring_to_ksm" {
  type                     = "ingress"
  from_port                = 30081
  to_port                  = 30081
  protocol                 = "tcp"
  security_group_id        = aws_security_group.web_sg.id
  source_security_group_id = aws_security_group.monitoring_sg.id
  description              = "Prometheus to Kube-state-metrics"
}

resource "aws_security_group_rule" "monitoring_to_kubelet" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.web_sg.id
  source_security_group_id = aws_security_group.monitoring_sg.id
  description              = "Monitoring to Kubelet"
}

resource "aws_security_group_rule" "monitoring_to_master_api" {
  type                     = "ingress"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.web_sg.id
  source_security_group_id = aws_security_group.monitoring_sg.id
  description              = "Monitoring to K8s API Server"
}

resource "aws_security_group_rule" "monitoring_to_loki" {
  type                     = "ingress"
  from_port                = 32000
  to_port                  = 32000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.web_sg.id
  source_security_group_id = aws_security_group.monitoring_sg.id
  description              = "Grafana (Monitoring) to Loki NodePort"
}

# ==========================================
# Internal K3s Communication
# ==========================================

resource "aws_security_group_rule" "allow_internal_all" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.web_sg.id
  source_security_group_id = aws_security_group.web_sg.id
  description              = "Allow all internal traffic between Master and Workers"
}
# ==========================================
# EC2 인스턴스 - Master Node
# ==========================================
resource "aws_instance" "Master_server" {
  ami                    = var.ubuntu_ami
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  subnet_id              = aws_subnet.private_1.id
  key_name               = var.key_name
  tags = {
    Name        = "${var.project_name}-Master-Node"
    Environment = var.environment
    Role        = "K3s-Master"
    Scheduler   = "Managed by Lambda"
  }
}
# ==========================================
# EC2 인스턴스 - Worker Nodes
# ==========================================
resource "aws_instance" "Worker_server" {
  count = var.worker_count

  ami                    = var.ubuntu_ami
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  subnet_id              = element([aws_subnet.private_2.id, aws_subnet.private_3.id], count.index)
  key_name               = var.key_name

  tags = {
    Name        = "${var.project_name}-Worker-Node-${count.index + 1}"
    Environment = var.environment
    Role        = "K3s-Worker"
    Scheduler   = "Managed by Lambda"
  }
}
# ==========================================
# EC2 인스턴스 - Monitoring Server (Bastion + Prometheus)
# ==========================================
resource "aws_instance" "monitoring_server" {
  ami                    = var.ubuntu_ami
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.monitoring_sg.id]
  subnet_id              = aws_subnet.public_1.id
  iam_instance_profile   = aws_iam_instance_profile.monitoring_profile.name
  key_name               = var.key_name

  tags = {
    Name        = "${var.project_name}-Monitoring-Server"
    Environment = var.environment
    Role        = "Bastion-Prometheus-Grafana"
    Scheduler   = "Managed by Lambda"
  }
}


