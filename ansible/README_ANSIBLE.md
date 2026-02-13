# Ansible 코드 설명서

## 목적
- 이 문서는 `민수/ansible`에 있는 플레이북과 역할들이 무엇을 하는지, 실행 방법 및 검증 절차를 전달하기 위해 작성되었습니다.

## 주요 파일
- **플레이북 진입점**: [민수/ansible/site.yml]
- **Ansible 설정**: [민수/ansible/ansible.cfg]
- **인벤토리**: [민수/ansible/inventory](예: `inventory/aws.ini`)
- **전역 변수**: [민수/ansible/group_vars/all.yml]

## 실행 순서 (요약)
- 1) Terraform으로 인스턴스 생성: `cd 민수/terraform && terraform init && terraform apply`
- 2) Ansible로 구성 배포: `cd 민수/ansible && ansible-playbook -i inventory/aws.ini site.yml`

## 역할(roles) 개요
- **`chrony`** (`민수/ansible/roles/chrony`):
  - 목적: EC2에 시간 동기화 설정을 적용
  - 주요 동작: `chrony` 설치, 템플릿(`/etc/chrony/chrony.conf`) 배포, 서비스 시작 및 `chronyc tracking`으로 검증
- **`k3s` / `k3s_master` / `k3s_worker`** (`민수/ansible/roles/k3s*`):
  - 목적: k3s 기반 쿠버네티스 클러스터 구축(마스터/워커 분리)
  - `k3s_master` 주요 동작: 설치 스크립트 다운로드, k3s 서버 설치, 토큰 추출 및 `KUBECONFIG` 설정, `/usr/local/bin/kubectl get nodes`로 기본 검증
  - `k3s_worker` 주요 동작: 마스터로부터 토큰/엔드포인트 획득, 에이전트 설치, 서비스 활성화 및 포트/파일 체크로 검증
  - 공통: swap 비활성화, 필요한 커널 모듈 적재(overlay, br_netfilter), sysctl 설정

## 핸들러(Handlers)
- 역할별 핸들러들은 설정 변경 시 서비스를 안전하게 재시작하거나 설정을 리로드합니다. 예:
  - `chrony` 재시작: [민수/ansible/roles/chrony/handlers/main.yml]
  - `k3s`/`k3s-agent` 재시작 및 sysctl reload: [민수/ansible/roles/k3s/handlers/main.yml]

## 변수와 커스터마이징
- 전역 변수 파일: [민수/ansible/group_vars/all.yml]
  - `k3s_version`, `k3s_install_url`, `k3s_server_options` 등 주요 값이 정의되어 있습니다.
  - TLS SAN 설정 등 일부 값은 인벤토리 그룹(예: `monitoring`)에 의존합니다.

## SSH/Bastion 접근 (운영 검증용)
- 권장: `~/.ssh/config`에 Bastion과 내부 호스트에 대한 `ProxyJump` 설정을 추가하여 `ssh master`로 바로 접속하도록 구성

예시:
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

## 검증(권장 절차)
- Ansible 플레이북 완료 후 마스터에 접속하여 kubeconfig가 제대로 설정되었는지 확인:

```bash
ssh master
kubectl get nodes
```

- 모든 노드가 `Ready` 상태인지 확인합니다. 문제가 있으면 해당 노드의 `journalctl -u k3s` 또는 `systemctl status k3s`/`k3s-agent` 로그를 확인하세요.

## 자주 발생하는 문제 및 대응
- 설치 스크립트 다운로드 실패: 네트워크/프록시 확인, `k3s_install_retry_count`/`_delay` 변수 조정
- 토큰 공유 실패: 마스터에서 토큰 파일(`/var/lib/rancher/k3s/server/node-token`) 생성 여부 확인 및 `add_host` 블록 동작 확인
- 권한 문제: kubeconfig 복사 시 소유자/권한(`/home/ubuntu/.kube/config` 0600) 확인

## 참고 및 추가 정보
- 플레이북이나 역할을 수정할 때는 로컬 스테이징 환경에서 먼저 실행해 검증하세요.
- 더 상세한 로그가 필요하면 Ansible에 `-vvv` 옵션을 추가해 실행하세요.

---
자동 요약 — 인프라팀 전달용 간단 가이드