🔗 How Ansible Integrates with Application Deployment
1. Overall Deployment Pipeline

본 프로젝트는 다음과 같은 단계로 애플리케이션이 배포됩니다.

Terraform → Ansible → K3s → Pods → External Access
Detailed Flow
1. Terraform
   ├─ VPC / Subnet 생성
   ├─ EC2 (Master, Worker, Monitoring) 생성
   ├─ Security Group 구성
   └─ Ansible Inventory 자동 생성

2. Ansible
   ├─ K3s Master 설치
   ├─ K3s Worker Join
   ├─ Node Exporter 설치
   ├─ Monitoring Stack 구성
   └─ App Deployment (kubectl apply)

3. Kubernetes (K3s)
   ├─ Deployment 생성 (replicas=2)
   ├─ Service 생성 (NodePort 30080)
   └─ Worker 노드에 Pod 분산 실행
2. Terraform → Ansible 연결 구조

Terraform은 인프라를 생성한 후,
자동으로 Ansible Inventory 파일을 생성합니다.

resource "local_file" "ansible_inventory" {
  filename = "../ansible/inventory/aws.ini"
}

이 파일에는 다음 정보가 포함됩니다:

[master]
10.0.2.126

[worker]
10.0.3.27
10.0.4.185

[monitoring]
43.203.196.101

즉, Terraform이 생성한 EC2 IP가
Ansible 배포 대상으로 자동 연결됩니다.

3. Ansible Role Structure

애플리케이션 배포는 app_deploy Role에서 수행됩니다.

ansible/
 ├── site.yml
 └── roles/
      └── app_deploy/
           ├── tasks/main.yml
           └── templates/
                ├── namespace.yaml.j2
                ├── deployment.yaml.j2
                └── service.yaml.j2
4. Ansible → Kubernetes 연결 방식

Ansible은 Master 노드에서 다음 명령을 실행합니다:

kubectl apply -f namespace.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

즉,

Ansible은 단순히 EC2에 접속하는 것이 아니라

Master 노드에서 kubectl을 실행하여

Kubernetes 리소스를 생성합니다.

5. GHCR 이미지 Pull 과정

Deployment에서 지정된 이미지:

image: ghcr.io/<your-image>

K3s는 해당 이미지를 직접 Pull하여
Worker 노드에서 컨테이너를 실행합니다.

즉,

GHCR → K3s Node → Container Runtime(containerd) → Pod 실행
6. Execution Order Summary

실제 실행 순서는 다음과 같습니다:

# 1. 인프라 생성
terraform apply

# 2. K3s 설치
ansible-playbook site.yml --tags k3s

# 3. App 배포
ansible-playbook site.yml --tags deploy
7. Architecture Responsibility Separation
Layer	Responsibility
Terraform	Infrastructure Provisioning
Ansible	Server Configuration & App Deployment
K3s	Container Orchestration
GHCR	Container Image Registry
Nginx	External Reverse Proxy
