# 민수 디렉터리 작업 기록

## 디렉터리 구조 및 주요 파일
- **Ansible 플레이북**: [민수/ansible/site.yml] — 전체 구성 실행 진입점
- **Ansible 설정**: [민수/ansible/ansible.cfg] — 인벤토리/구성 관련 설정
- **Ansible 변수**: [민수/ansible/group_vars/all.yml]
- **Ansible 역할(예시)**:
  - [민수/ansible/roles/chrony/templates/chrony.conf.j2] — 시간 동기화 템플릿
  - [민수/ansible/roles/k3s] — k3s, k3s_master, k3s_worker 등

## 지금까지 작업 요약
- `Terraform`으로 AWS 인프라(네트워크, 컴퓨트 등) 정의가 준비되어 있음.
- `Ansible playbook`으로 생성된 인스턴스에 k3s 클러스터와 관련된 역할을 배포하도록 구성되어 있음.
- `chrony` 역할처럼 시스템 설정(시간 동기화 등)을 처리하는 역할 포함.

## 사용법
1. Terraform 초기화 및 적용

```bash
cd 민수/terraform
terraform init
terraform apply
```

2. (인스턴스 준비 후) Ansible로 구성 적용

```bash
cd 민수/ansible
ansible-playbook -i inventory/aws.ini site.yml
```

## 배포 및 검증 (Terraform → Ansible → SSH → kubectl)

1. Terraform으로 인프라 생성

```bash
cd 민수/terraform
terraform init
terraform apply
```

2. Ansible로 각 인스턴스에 필요한 소프트웨어 설치

```bash
cd 민수/ansible
ansible-playbook -i inventory/aws.ini site.yml
```

3. Bastion을 통한 SSH 터널(별명 설정)

`~/.ssh/config`에 Bastion과 내부 Master에 대한 별명(예시)을 추가합니다:

```
Host bastion
  HostName <BASTION_PUBLIC_IP_OR_DNS>
  User ubuntu
  IdentityFile ~/.ssh/<your_key.pem>

Host master
  HostName <MASTER_PRIVATE_IP>
  User ubuntu
  IdentityFile ~/.ssh/<your_key.pem>
  ProxyJump bastion
```

설정 저장 후 로컬에서 `ssh master`로 접속하면 자동으로 `bastion`을 통해 `master`로 접속됩니다.

4. k3s 클러스터 상태 확인

마스터에 접속한 뒤(또는 kubeconfig가 로컬에 설정된 경우) 다음 명령으로 노드 상태를 확인합니다:

```bash
kubectl get nodes
```

정상 동작 시 `STATUS`가 `Ready`로 표시되어야 합니다(마스터와 워커 모두).

## 권장 다음 단계
- `group_vars/all.yml`와 `variables.tf`의 민감 정보(키, 자격증명) 확인 및 보안 처리
- Terraform 상태 파일(.tfstate) 민감 정보 관리(원격 상태 또는 암호화 고려)
- 작은 스테이징 환경에서 `terraform apply` → `ansible-playbook` 순으로 전체 흐름 검증


## `chrony` 역할 세부
- **목적**: EC2 인스턴스의 시간 동기화를 안정적으로 구성하기 위한 Ansible 역할입니다. AWS Time Sync Service를 우선 사용하고, 외부 NTP 풀을 백업으로 둡니다.
- **주요 파일**:
  - [민수/ansible/roles/chrony/tasks/main.yml] — 패키지 설치, 템플릿 배포, 서비스 시작 및 상태 검증을 수행합니다.
  - [민수/ansible/roles/chrony/templates/chrony.conf.j2] — AWS 환경에 최적화된 `chrony` 설정 템플릿입니다. (AWS 내부 타임서버 `169.254.169.123` 우선 사용)
  - [민수/ansible/roles/chrony/handlers/main.yml] — 설정 변경 시 `chrony` 재시작 핸들러를 제공합니다.

- **동작 요약**:
  1. `chrony` 패키지 설치
  2. 템플릿을 `/etc/chrony/chrony.conf`로 배포하고 변경 시 핸들러로 서비스 재시작
  3. 서비스 활성화 및 시작
  4. `chronyc tracking` 명령으로 동기화 상태를 확인하고 결과를 출력
- **검증 방법**:
  - 플레이북 실행 후 다음 명령으로 동기화 상태 확인: `chronyc tracking`
  - Ansible의 `debug`가 `chronyc tracking` 출력을 보여주며 배포 성공 여부를 빠르게 확인할 수 있습니다.

---
작성자: 정리 자동화 — 현재 워크스페이스 기반 요약

# 정현 작업 기록

## `app_deploy` 역할 세부

- **목적**:  
  K3s 클러스터에 Lunch API 애플리케이션을 배포하기 위한 Ansible 역할입니다.  
  GitHub Container Registry(GHCR)에 푸시된 이미지를 사용하여 Deployment와 Service를 생성합니다.

- **주요 파일**:
  - [민수/ansible/roles/app_deploy/tasks/main.yml]  
    — Namespace 생성, Deployment/Service 템플릿 렌더링, kubectl apply, rollout 대기 및 상태 출력 수행
  - [민수/ansible/roles/app_deploy/templates/deployment.yaml.j2]  
    — Deployment 매니페스트 템플릿
  - [민수/ansible/roles/app_deploy/templates/service.yaml.j2]  
    — Service 매니페스트 템플릿 (NodePort 조건부 적용)
  - [민수/ansible/roles/app_deploy/templates/namespace.yaml.j2]  
    — Namespace 생성 템플릿
  - [민수/ansible/roles/app_deploy/defaults/main.yml]  
    — 앱 이름, 이미지, 포트, replicas 등 기본 변수 정의

- **동작 요약**:
  1. `/opt/lunch-app-k8s` 디렉터리에 Kubernetes 매니페스트 파일 생성
  2. Namespace 생성 (`lunch`)
  3. GHCR 이미지 기반 Deployment 생성
  4. NodePort 방식 Service 생성 (기본: 30080)
  5. `kubectl rollout status`로 배포 완료까지 대기
  6. 배포 완료 후 Pod/Service 상태 출력

- **현재 기본 설정값**:
  - Namespace: `lunch`
  - Deployment 이름: `lunch-api`
  - Replicas: 2
  - Container Port: 8000
  - Image: `ghcr.io/hjh6709/lunch_app_second/lunch-api:latest`
  - Service Type: NodePort
  - NodePort: 30080

- **검증 방법**:
  - 플레이북 실행 후 다음 명령으로 배포 상태 확인:

  ```bash
  kubectl -n lunch get deploy,svc,pods -o wide
