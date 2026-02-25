🚀 Application Deployment Architecture (K3s)
1. Overview

본 프로젝트의 애플리케이션은 K3s 기반 Kubernetes 클러스터에 배포되며,
외부 사용자는 Monitoring 서버(Reverse Proxy) 를 통해 접근합니다.

App Image: GHCR (GitHub Container Registry)

Deployment 방식: Kubernetes Deployment

Service 타입: NodePort (30080)

Worker Node: 2대 (분산 실행)

2. Infrastructure Structure
Internet
   │
   ▼
Monitoring Server (Public Subnet)
   - Nginx (Reverse Proxy)
   - Bastion
   │
   ▼
Private Subnet (K3s Cluster)
   ├── Master Node (Control Plane)
   ├── Worker Node 1
   └── Worker Node 2

Master / Worker는 Private Subnet에 위치

외부 노출은 Monitoring Server만 허용

보안그룹을 통해 접근 제어

3. Deployment Flow
Step 1. Ansible → K3s Master

로컬 환경에서 Ansible을 실행하면:

Local PC
   │
   ▼ (SSH Proxy via Bastion)
Monitoring Server
   │
   ▼
K3s Master

Ansible app_deploy Role이 다음 리소스를 생성합니다:

Namespace

Deployment

Service

Step 2. Kubernetes Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lunch-api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: lunch-api
  template:
    metadata:
      labels:
        app: lunch-api
    spec:
      containers:
        - name: lunch-api
          image: ghcr.io/<your-image>
          ports:
            - containerPort: 80

replicas: 2

GHCR에서 이미지 Pull

Worker 노드 2대에 분산 배치

실제 배치 결과
lunch-api-xxxx   Running   ip-10-0-3-27
lunch-api-xxxx   Running   ip-10-0-4-185
4. Service Configuration (NodePort)
apiVersion: v1
kind: Service
metadata:
  name: lunch-api
spec:
  type: NodePort
  selector:
    app: lunch-api
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
의미

클러스터 내부 포트: 80

각 Worker 노드 외부 포트: 30080

접근 가능 주소:

10.0.3.27:30080
10.0.4.185:30080
5. External Access Architecture

외부 사용자는 Worker에 직접 접근하지 않습니다.

User Browser
   │
   ▼
http://<Monitoring-Public-IP>
   │
   ▼ (Nginx Reverse Proxy)
10.0.3.27:30080
10.0.4.185:30080
   │
   ▼
Pod (Container)
Nginx Upstream Configuration
upstream lunch_upstream {
  server 10.0.3.27:30080;
  server 10.0.4.185:30080;
}

server {
  listen 80;

  location / {
    proxy_pass http://lunch_upstream;
  }
}
6. Key Characteristics
🔐 Security

Worker 노드는 Private Subnet

외부 노출은 Monitoring Server만 허용

Security Group으로 NodePort 접근 제한

🔁 High Availability

replicas = 2

Worker 2대에 분산 실행

Worker 1대 장애 시 다른 노드에서 서비스 유지 가능

📦 Container-Based Deployment

GHCR 이미지 사용

Kubernetes Deployment 기반 운영

Infrastructure as Code (Terraform + Ansible)
