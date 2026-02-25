# Hello_KT

**Terraform + Ansible + K3s + Monitoring + Nginx Reverse Proxy**

---

## 1. 프로젝트 개요

AWS 상에 Private K3s 클러스터(Master 1 + Worker 2)를 구성하고,
Monitoring 서버(Public EC2)를 Bastion + 모니터링(Prometheus/Grafana) + Reverse Proxy(Nginx)로 사용하여
외부(80)에서 내부 서비스(NodePort 30080)로 접속 가능한 인프라를 구축한 프로젝트입니다.

| 구분 | 내용 |
|------|------|
| Infra | Terraform |
| Provisioning | Ansible (roles 기반) |
| Kubernetes | K3s (Private Subnet) |
| App Deploy | GHCR 이미지 → Deployment(replicas=2) + NodePort(30080) |
| External Access | Internet → Monitoring Nginx(80) → Workers:30080 → Pods |
| Monitoring | Prometheus(9090) + Grafana(3000) + Node Exporter(9100) |

---

## 2. 아키텍처

```
Internet
  │
  ▼
┌─────────────────────────────────────────────────────┐
│  Monitoring Server  (Public Subnet 10.0.1.0/24)     │
│                                                     │
│  Nginx (:80) ─────────────────────────────┐         │
│  Prometheus (:9090)                       │         │
│  Grafana (:3000)                          │         │
│  Node Exporter (:9100)                    │         │
│  Bastion (ProxyCommand)                   │         │
└───────────────────────────────────────────│─────────┘
                                            │ VPC 내부
┌───────────────────────────────────────────│─────────┐
│  K3s Cluster  (Private Subnets)           │         │
│                                           ▼         │
│  ┌─ Master  (10.0.2.0/24  AZ-a) ───────────────┐   │
│  │  K3s API Server (:6443)                      │   │
│  └──────────────────────────────────────────────┘   │
│                                                     │
│  ┌─ Worker 1  (10.0.3.0/24  AZ-b) ─────────────┐   │
│  │  Lunch API Pod  ←  NodePort :30080           │   │
│  └──────────────────────────────────────────────┘   │
│                                                     │
│  ┌─ Worker 2  (10.0.4.0/24  AZ-c) ─────────────┐   │
│  │  Lunch API Pod  ←  NodePort :30080           │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

---

## 3. 레포 구조

### 3.1 Terraform

```
terraform/
├─ provider.tf          # AWS provider, SSH 키 생성
├─ network.tf           # VPC / Subnet / Route / NAT / IGW
├─ compute.tf           # EC2 인스턴스, Security Group
├─ backend.tf           # S3 remote state
├─ dynamodb.tf          # DynamoDB lock table
├─ iam.tf               # IAM Role & Instance Profile
├─ automation.tf        # Lambda + EventBridge (EC2 자동 시작/중지)
├─ ansible_gen.tf       # ✅ Ansible Inventory 자동 생성
├─ output.tf            # 접속 정보 출력
├─ variables.tf         # 변수 정의
├─ ec2_start.py         # Lambda 시작 함수
├─ ec2_stop.py          # Lambda 중지 함수
├─ enable-nat.sh        # NAT Gateway 활성화
└─ disable-nat.sh       # NAT Gateway 비활성화
```

### 3.2 Ansible

```
ansible/
├─ ansible.cfg
├─ site.yml                         # 메인 플레이북 (전체 실행 흐름)
├─ group_vars/
│  └─ all.yml                       # 전역 변수 (K3s 버전/옵션 등)
├─ inventory/
│  └─ aws.ini                       # ✅ Terraform이 자동 생성
├─ key/
│  └─ Hello_kt.pem                  # SSH 키 (⚠️ 절대 커밋 금지)
└─ roles/
   ├─ chrony/                       # 시간 동기화
   │  ├─ tasks/main.yml
   │  ├─ handlers/main.yml
   │  └─ templates/chrony.conf.j2
   ├─ k3s_master/                   # K3s Master 설치
   │  ├─ tasks/main.yml
   │  └─ handlers/main.yml
   ├─ k3s_worker/                   # K3s Worker Join
   │  ├─ tasks/main.yml
   │  └─ handlers/main.yml
   ├─ node_exporter/                # 메트릭 수집 에이전트 (9100)
   │  ├─ tasks/main.yml
   │  └─ handlers/main.yml
   ├─ monitoring/                   # Prometheus + Grafana (Docker Compose)
   │  ├─ tasks/main.yml
   │  ├─ handlers/main.yml
   │  └─ templates/
   │     ├─ docker-compose.yml.j2
   │     └─ prometheus.yml.j2
   ├─ app_deploy/                   # Lunch App K8s 배포
   │  ├─ defaults/main.yml
   │  ├─ tasks/main.yml
   │  └─ templates/
   │     ├─ namespace.yaml.j2
   │     ├─ deployment.yaml.j2
   │     └─ service.yaml.j2
   └─ nginx_proxy/                  # Nginx Reverse Proxy (80 → 30080)
      ├─ defaults/main.yml
      ├─ tasks/main.yml
      ├─ handlers/main.yml
      └─ templates/lunch.conf.j2
```

---

## 4. Ansible Roles 설명

### 4.1 chrony

EC2 시간 동기화 설정 (AWS Time Sync + Ubuntu NTP pool).
`/etc/chrony/chrony.conf` 템플릿 배포 후 서비스 재시작.

### 4.2 k3s_master

K3s server 설치, 토큰 생성 및 Worker에 공유.
`/home/ubuntu/.kube/config` kubeconfig 설정.
옵션: Traefik/ServiceLB disable, Master taint 적용.

### 4.3 k3s_worker

Master 토큰 + endpoint로 K3s agent 설치 및 클러스터 Join.
kubelet Ready 대기 후 서비스 활성화.

### 4.4 node_exporter

Master/Worker 노드에 Node Exporter 컨테이너 실행 (포트 9100).
`site.yml`에서 `hosts: k3s_cluster`로 실행.

### 4.5 monitoring

Monitoring 서버에 Docker Compose 기반 스택 구성.
Prometheus(9090) + Grafana(3000) + Node Exporter(9100).
Prometheus 설정에서 Master/Worker를 scrape 대상에 포함.

### 4.6 app_deploy

GHCR 이미지 기반 K8s 배포.
Namespace(`lunch`) → Deployment(`lunch-api`, replicas=2) → Service(NodePort 30080).
`kubectl rollout status`로 배포 완료 확인.

### 4.7 nginx_proxy

Monitoring 서버에 Nginx 설치.
80포트로 들어오는 요청을 Worker NodePort(30080) upstream으로 프록시.
외부 접속의 entrypoint 역할.

---

## 5. Ansible Inventory 핵심 포인트

Terraform이 `ansible/inventory/aws.ini`를 자동 생성하며, 다음 구조를 갖습니다:

```ini
[master]
10.0.2.x

[worker]
10.0.3.x
10.0.4.x

[monitoring]
<PUBLIC_IP>

[k3s_cluster:children]
master
worker

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=./key/Hello_kt.pem
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[k3s_cluster:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ProxyCommand="ssh -W %h:%p -q ubuntu@<MONITORING_IP> -i ./key/Hello_kt.pem"'
```

- `./key/Hello_kt.pem`은 `ansible/` 폴더 기준 상대경로 (환경 독립적)
- Private 노드는 Monitoring 서버를 **Bastion(ProxyCommand)**으로 경유하여 접속

---

## 6. 실행 방법

### 6.1 Terraform Apply

```bash
cd terraform
terraform init
terraform apply
```

### 6.2 Ansible 준비

```bash
cd ../ansible
chmod 600 ./key/Hello_kt.pem
```

### 6.3 접속 확인 (가장 먼저)

```bash
ansible -i inventory/aws.ini master -m ping
```

> `pong`이 돌아오면 정상

### 6.4 전체 실행 (한 번에)

```bash
ansible-playbook -i inventory/aws.ini site.yml
```

---

## 7. 단계별 실행 (태그)

```bash
# ① 시간 동기화
ansible-playbook -i inventory/aws.ini site.yml --tags chrony

# ② K3s Master 설치
ansible-playbook -i inventory/aws.ini site.yml --tags k3s-master

# ③ K3s Worker 설치
ansible-playbook -i inventory/aws.ini site.yml --tags k3s-worker

# ④ Node Exporter (Master + Worker)
ansible-playbook -i inventory/aws.ini site.yml --tags node-exporter

# ⑤ Monitoring Stack (Prometheus + Grafana)
ansible-playbook -i inventory/aws.ini site.yml --tags monitoring-stack

# ⑥ 클러스터 검증
ansible-playbook -i inventory/aws.ini site.yml --tags verify

# ⑦ 모니터링 검증
ansible-playbook -i inventory/aws.ini site.yml --tags verify-monitoring

# ⑧ Lunch App 배포 (GHCR → K3s)
ansible-playbook -i inventory/aws.ini site.yml --tags deploy

# ⑨ Nginx Reverse Proxy (외부 접속)
ansible-playbook -i inventory/aws.ini site.yml --tags nginx
```

---

## 8. 정상 동작 확인

### 8.1 K3s 노드 Ready 확인

```bash
ansible -i inventory/aws.ini master -b -m shell \
  -a "kubectl get nodes -o wide"
```

### 8.2 앱 배포 상태 확인

```bash
ansible -i inventory/aws.ini master -b -m shell \
  -a "kubectl -n lunch get deploy,svc,pods -o wide"
```

### 8.3 Node Exporter 확인 (Worker 내부)

```bash
ansible -i inventory/aws.ini worker -b -m shell \
  -a "curl -s http://localhost:9100/metrics | head"
```

### 8.4 Prometheus scrape 확인

```bash
ansible -i inventory/aws.ini monitoring -b -m shell \
  -a "curl -s http://localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | [.labels.job,.discoveredLabels.__address__,.health] | @tsv' | head"
```

> `health`가 `up`이면 정상

### 8.5 외부 접속 확인

```bash
# 브라우저
http://<MONITORING_PUBLIC_IP>/

# CLI
curl -I http://<MONITORING_PUBLIC_IP>/
```

---

## 9. 접속 정보

| 서비스 | URL | 비고 |
|--------|-----|------|
| **Lunch App** | `http://<MONITORING_PUBLIC_IP>/` | Nginx Reverse Proxy 경유 |
| **Grafana** | `http://<MONITORING_PUBLIC_IP>:3000` | 초기 계정 `admin` / `admin` |
| **Prometheus** | `http://<MONITORING_PUBLIC_IP>:9090` | |

---

## 10. 트러블슈팅

### 10.1 Permission denied (publickey)

```bash
# 키 권한 확인
chmod 600 ./key/Hello_kt.pem

# aws.ini 의 ansible_ssh_private_key_file 경로가 ./key/Hello_kt.pem 인지 확인
```

### 10.2 로컬에서 10.0.x.x 접속이 안 됨

Private IP는 로컬에서 직접 접근 불가 (정상).
Monitoring 서버(Bastion) 경유 또는 Ansible로 내부에서 확인해야 합니다.

---

## 11. 보안 / 운영 메모

- `.pem` 파일은 **절대 커밋하지 않음** (`.gitignore` 처리 완료)
- Private 노드는 Public IP 없이 운영
- Reverse Proxy(Nginx)를 통해 외부 노출 범위를 최소화
- NAT Gateway는 비용 절감을 위해 작업 후 비활성화 권장

```bash
# NAT 비활성화 (비용 절감)
cd terraform && bash disable-nat.sh

# NAT 활성화 (패키지 설치 등 인터넷 필요 시)
cd terraform && bash enable-nat.sh
```

---

## 12. 현재 진행 상황

- [x] Terraform 인프라 구성
- [x] Private K3s 클러스터 구성 (Master 1 + Worker 2)
- [x] Monitoring 서버 구성 (Prometheus / Grafana)
- [x] Node Exporter 수집 정상 (health: up)
- [x] GHCR 이미지 배포 (replicas=2, NodePort=30080)
- [x] Nginx Reverse Proxy로 외부 접속 완료
- [ ] 도메인 연결 / HTTPS (추후)

---

## 13. 자동 생성 파일 흐름 (Terraform → Ansible 연결 구조)

이 프로젝트는 Terraform과 Ansible이 완전히 분리된 구조가 아니라,
**Terraform이 Ansible 실행에 필요한 파일을 자동 생성**하도록 설계되어 있습니다.

### 흐름

```
terraform apply
    ↓
EC2 인스턴스 생성
    ↓
Private / Public IP 확정
    ↓
ansible_gen.tf 실행
    ↓
ansible/inventory/aws.ini 자동 생성
```

### 자동 생성 파일: `ansible/inventory/aws.ini`

`terraform/ansible_gen.tf`에서 아래 리소스를 통해 생성됩니다:

```hcl
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory/aws.ini"
}
```

생성되는 내용 예시:

```ini
[master]
10.0.2.126

[worker]
10.0.3.27
10.0.4.185

[monitoring]
43.203.196.101
```

- Master/Worker는 **Private IP**
- Monitoring은 **Public IP**
- Bastion(ProxyCommand) 설정 포함
- SSH 키 경로는 `./key/Hello_kt.pem` (상대경로)

### 왜 이게 중요한가?

- EC2 IP는 `terraform apply` 때마다 달라질 수 있음
- Inventory를 수동으로 수정하면 오류 가능성 증가
- Terraform이 IP를 직접 참조해서 생성 → **항상 정확한 인벤토리 유지**

> **즉, `terraform apply` → 바로 `ansible-playbook` 실행 가능.**
> 이것이 이 프로젝트의 핵심 자동화 연결 포인트입니다.

---

## 14. site.yml 실행 흐름 (Step 1 ~ Step 8)

`ansible/site.yml`은 단순 플레이북이 아니라,
**인프라 → 클러스터 → 모니터링 → 앱 → 프록시** 순서로 설계되어 있습니다.

### Step 1. 시간 동기화 (chrony)

```
--tags chrony
```

모든 서버 대상. 시간 오차를 방지하여 Kubernetes 안정성 확보.

### Step 2. K3s Master 설치

```
--tags k3s-master
```

Master 노드에 K3s server 설치. 토큰 생성 및 kubeconfig 설정.

### Step 3. K3s Worker Join

```
--tags k3s-worker
```

Worker 2대가 Master에 Join. 클러스터 구성 완료.

### Step 4. Node Exporter 설치

```
--tags node-exporter
```

대상: `k3s_cluster` (Master + Worker). 포트 9100에서 metrics 제공.

### Step 5. Monitoring Stack 설치

```
--tags monitoring-stack
```

Monitoring 서버에 Docker Compose 기반 스택 구성:
Prometheus(9090) + Grafana(3000) + Node Exporter.

### Step 6. 클러스터 검증

```
--tags verify
```

노드 3개 Ready 확인, 테스트 Deployment 실행 후 삭제, 전체 상태 출력.

### Step 7. Lunch App 배포

```
--tags deploy
```

GHCR 이미지 Pull → Deployment(replicas=2) → NodePort(30080) 생성.

### Step 8. Nginx Reverse Proxy 구성

```
--tags nginx
```

Monitoring 서버에 Nginx 설치.
80 → Worker:30080 upstream 설정. **외부 접속 가능 상태 완성.**

---

## 15. Nginx Upstream 구조 설명

### 현재 설정 구조

```nginx
upstream lunch_upstream {
    server 10.0.3.27:30080;    # Worker 1
    server 10.0.4.185:30080;   # Worker 2
    keepalive 32;
}

server {
    listen 80;
    location / {
        proxy_pass http://lunch_upstream;
    }
}
```

### 트래픽 흐름

```
Internet
  ↓
Monitoring Server (Nginx :80)
  ↓  라운드로빈
  ├─ Worker 1 :30080
  └─ Worker 2 :30080
       ↓
     Pod (replicas=2)
```

### 이 구조의 장점

**① Private 노드 직접 노출 안 함**
Worker는 Public IP가 없고, Monitoring 서버만 외부에 노출됩니다.

**② 부하 분산**
Nginx가 두 Worker에 라운드로빈으로 분배하고,
K8s Service가 Pod 레벨에서 한 번 더 분산 → **이중 부하 분산 구조**.

**③ Worker 교체가 쉬움**
`terraform apply`로 Worker IP가 바뀌면:

```
ansible_gen.tf → inventory 갱신 → nginx_proxy role → upstream 재생성
```

자동으로 반영 가능.

**④ Ingress 없이도 외부 접속 가능**
Ingress Controller 없이도 Reverse Proxy 구조로 외부 접속을 구현하여,
인프라 구조 학습에 적합한 설계입니다.

---

## 16. 기술 스택

`AWS (EC2, VPC, SG)` · `Terraform` · `Ansible` · `K3s` · `Docker / GHCR` · `Prometheus / Grafana` · `Nginx`

