# Hello_KT

**Terraform + Ansible + K3s + Monitoring + Nginx Reverse Proxy**

---

## 1. 프로젝트 개요

AWS 상에 **Private K3s 클러스터(Master 1 + Worker 2)**를 구성하고,
**Monitoring 서버(Public EC2)**를 Bastion + 모니터링(Prometheus/Grafana) + Reverse Proxy(Nginx)로 사용하여
외부(80)에서 내부 서비스(NodePort 30080)로 접속 가능한 인프라를 구축한 프로젝트입니다.

| 구분 | 내용 |
|------|------|
| Infra | Terraform |
| Provisioning | Ansible (roles 기반) |
| Kubernetes | K3s (Private Subnet) |
| Application | FastAPI 점심 메뉴 추천 서비스 |
| CI/CD | GitHub Actions → GHCR 이미지 자동 빌드 |
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

### 3.1 Application

```
app/
├─ main.py                  # FastAPI 백엔드 (184줄)
│                            # - 앱 생성, 정적 파일 마운트
│                            # - Pydantic 응답 모델 (MenuResponse, SpinResponse)
│                            # - load_menus(): menus.json 로드 함수
│                            # - 5개 엔드포인트 (/, /health, /api/menus, /api/random, /api/spin)
│
├─ menus.json               # 메뉴 데이터 (10개 메뉴, version 필드 포함)
│                            # - 매 요청마다 파일을 읽어서 반영 (앱 재시작 불필요)
│
└─ static/
   └─ index.html            # 프론트엔드 SPA (415줄, HTML+CSS+JS 단일 파일)
                             # - "그냥 골라줘" → /api/random 호출
                             # - "룰렛으로 고르기" → /api/spin 호출 + 80ms 간격 애니메이션
                             # - XSS 방지 (escapeHtml), 에러 토스트, 로딩 상태 관리

.github/workflows/
└─ ghcr.yml                 # GitHub Actions CI/CD (34줄)
                             # - 트리거: main 브랜치 push
                             # - 빌드 후 GHCR에 latest + commit-sha 태그로 푸시
                             # - GITHUB_TOKEN 자동 사용 (별도 시크릿 불필요)

Dockerfile                  # 컨테이너 빌드 정의 (13줄)
                             # - python:3.11 베이스
                             # - requirements.txt 먼저 복사 (레이어 캐시 활용)
                             # - EXPOSE 8000, uvicorn으로 실행

requirements.txt            # fastapi==0.115.6, uvicorn[standard]==0.30.6
```

### 3.2 Terraform

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

### 3.3 Ansible

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
   ├─ k3s_master/                   # K3s Master 설치
   ├─ k3s_worker/                   # K3s Worker Join
   ├─ node_exporter/                # 메트릭 수집 에이전트 (9100)
   ├─ monitoring/                   # Prometheus + Grafana (Docker Compose)
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

## 4. Application — 점심 메뉴 추천 서비스

### 4.1 개요

"오늘 점심 뭐 먹지?" 고민을 해결하는 웹 서비스입니다.
FastAPI 백엔드가 메뉴 데이터(`menus.json`)를 읽어 랜덤 추천 또는 룰렛 연출 결과를 반환하고,
단일 HTML 프론트엔드가 API를 호출하여 결과를 화면에 표시합니다.

| 구분 | 기술 | 버전/비고 |
|------|------|-----------|
| Backend | FastAPI | 0.115.6 |
| ASGI Server | Uvicorn | 0.30.6 (standard extras) |
| Runtime | Python | 3.11 |
| Frontend | Vanilla HTML + CSS + JS | 단일 파일 415줄 |
| Container | Docker | python:3.11 base |
| Registry | GHCR | GitHub Container Registry |
| CI/CD | GitHub Actions | main push 시 자동 빌드 |

---

### 4.2 백엔드 상세 (`app/main.py`, 184줄)

#### 앱 생성 및 설정

```python
app = FastAPI(title="점심 메뉴 추천 서비스")
```

- `title`은 `/docs` Swagger UI에 표시됨
- `/static` 경로에 정적 파일 디렉토리 마운트 (`StaticFiles`)
- `menus.json` 경로는 `Path(__file__).parent / "menus.json"` (main.py 기준 상대경로)

#### Pydantic 응답 모델

```python
class MenuResponse(BaseModel):
    menu: str                    # 단일 추천 메뉴

class SpinResponse(BaseModel):
    result: str                  # 최종 선택된 메뉴
    ticks: list[str]             # 룰렛이 지나간 메뉴 목록 (프론트 연출용)
    duration_ms: int             # 서버 측 실행 시간
```

Swagger 문서에서 응답 스키마가 자동으로 표시됩니다.

#### 데이터 로드 함수

```python
def load_menus() -> list[str]:
```

- `menus.json`을 **매 요청마다** 읽어서 리스트 반환
- 파일이 없거나 `menus` 배열이 비어있으면 `RuntimeError` 발생
- 앱 재시작 없이 `menus.json`만 교체하면 메뉴가 즉시 반영됨

#### API 엔드포인트 (5개)

| Method | Path | 함수명 | 설명 |
|--------|------|--------|------|
| `GET` | `/` | `root()` | `index.html`을 `FileResponse`로 반환 |
| `GET` | `/health` | `health()` | `{"ok": true}` — K8s Probe, ALB 헬스체크용 |
| `GET` | `/api/menus` | `get_menus()` | 전체 메뉴 목록 + 개수 반환 |
| `GET` | `/api/random` | `random_menu()` | `random.choice()`로 1개 메뉴 추천 |
| `GET` | `/api/spin` | `spin_menu()` | 룰렛 결과 + tick 배열 + 실행시간 반환 |

#### `/api/spin` 동작 상세

```
파라미터:
  seed (optional) — 동일 seed면 동일 결과 (테스트/데모용)
  ticks (기본 18, 범위 5~60) — 룰렛이 지나가는 칸 수

동작 순서:
  1. load_menus()로 메뉴 로드
  2. 독립 RNG 객체 생성 (random.Random()) — 전역 random 오염 방지
  3. seed 처리:
     - seed 없음 → time.time_ns() 사용 (매번 다른 결과)
     - seed 있음 → SHA-256 해시 → 상위 16자리 hex를 정수로 변환하여 seed 설정
  4. ticks - 1개의 랜덤 메뉴 tick 목록 생성
  5. 마지막 1개가 최종 결과 (result)
  6. 서버 측 실행 시간(ms) 계산하여 응답
```

응답 예시:

```json
{
  "result": "피자",
  "ticks": ["김치찌개", "스테이크", "탕수육", "...", "피자"],
  "duration_ms": 1
}
```

---

### 4.3 프론트엔드 상세 (`app/static/index.html`, 415줄)

HTML + CSS + JavaScript가 단일 파일에 포함된 SPA(Single Page Application)입니다.

#### UI 디자인

- **SVG 노이즈 오버레이** — `body:before`에 `feTurbulence` SVG 필터로 미세한 텍스처 적용
- CSS 변수로 전체 테마 관리 (`--bg1`, `--card`, `--text`, `--muted`, `--line`, `--shadow`, `--radius`)
- 모바일 반응형 (`@media max-width: 420px` — 카드 패딩, 폰트 크기 축소)

#### 화면 구성

```
┌─ .badge ──────────────────────┐
│  🍽️ Lunch Picker 점·메·추     │
└───────────────────────────────┘

┌─ .card ───────────────────────┐
│  h1: 오늘 점심 뭐 먹지?       │
│  .sub: 고민은 여기까지만...    │
│                               │
│  ┌─ .btn.primary ──────────┐  │
│  │  ⚡ 그냥 골라줘           │  │  → pickRandom() 호출
│  │     빠르게 하나만 추천    │  │
│  └─────────────────────────┘  │
│                               │
│  ┌─ .btn.secondary ────────┐  │
│  │  🎡 룰렛으로 고르기      │  │  → spinRoulette() 호출
│  │     재밌게 돌려서 결정    │  │
│  └─────────────────────────┘  │
│                               │
│  ── ── ── ── ── ── ── ── ──  │
│                               │
│  .result 영역                 │
│  → "🍽️ 돈까스" (결과 표시)    │
│                               │
│  © 2026 점·메·추    개발자용  │ ← /docs 링크
│                               │
│  .toast (하단 알림)           │
└───────────────────────────────┘
```

#### JavaScript 함수 (4개)

**`pickRandom()`** — "그냥 골라줘" 버튼

```
1. setLoading(true) → 버튼 비활성화 + "잠깐만요…" 토스트
2. fetch("/api/random") 호출
3. 응답의 data.menu를 showPick()으로 결과 영역에 표시
4. 에러 시 "잠시 후 다시 시도해 주세요." 토스트
5. finally에서 setLoading(false) → 버튼 복원
```

**`spinRoulette()`** — "룰렛으로 고르기" 버튼

```
1. setLoading(true)
2. fetch("/api/spin?ticks=22") 호출 (22칸 룰렛)
3. 응답의 ticks 배열을 80ms 간격(setInterval)으로 순회하며
   결과 영역에 메뉴를 빠르게 교체 표시 (룰렛이 돌아가는 연출)
4. 마지막 tick 도달 → clearInterval → 최종 result 표시
5. "룰렛 완료!" 토스트 표시
6. ticks가 비어있으면 연출 없이 바로 result 표시
```

**`escapeHtml(str)`** — XSS 방지

```
& → &amp;  < → &lt;  > → &gt;  " → &quot;  ' → &#039;
```

API 응답의 메뉴 이름을 innerHTML에 넣기 전에 반드시 이스케이프 처리합니다.

**`setLoading(isLoading)`** — 로딩 상태 관리

```
true → 두 버튼에 .loading 클래스 추가 (opacity 0.65 + pointer-events: none)
false → .loading 제거, 토스트 숨김
```

#### 스타일 특징

- 버튼 hover: `filter: brightness(1.08)` + 보더 색상 변화
- 버튼 active: `translateY(1px) scale(0.998)` 눌림 효과
- 결과 표시: `@keyframes pop` 애니메이션 (아래에서 위로 페이드인)
- 토스트: 카드 하단에 `position: absolute`로 뜨는 알림 (opacity 전환)

---

### 4.4 메뉴 데이터 (`app/menus.json`)

```json
{
    "version": 1,
    "menus": [
        "김치찌개",
        "돈까스",
        "제육볶음",
        "비빔밥",
        "순대국밥",
        "피자",
        "짜장면",
        "탕수육",
        "햄버거",
        "스테이크"
    ]
}
```

- `version` 필드로 데이터 포맷 버전 관리
- 메뉴 추가/수정/삭제 시 이 파일만 수정하면 됨
- 앱이 매 요청마다 파일을 읽으므로 **재시작 없이 반영**

---

### 4.5 Dockerfile

```dockerfile
FROM python:3.11

WORKDIR /app

# 1단계: 의존성 먼저 설치 (레이어 캐시 활용)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 2단계: 앱 소스 복사
COPY app ./app

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**빌드 전략:**
- `requirements.txt`를 먼저 COPY → `pip install` → Docker 레이어 캐시 활용
- 소스코드(`app/`)는 이후에 COPY → 코드만 바뀌면 의존성 재설치 없이 빠른 빌드
- `--no-cache-dir`로 pip 캐시 제거 → 이미지 크기 절감

**컨테이너 실행 시:**
- Uvicorn이 `0.0.0.0:8000`에서 Listen
- K8s Deployment의 `containerPort: 8000`과 매핑

---

### 4.6 CI/CD 워크플로우 (`.github/workflows/ghcr.yml`)

```yaml
name: Build and push to GHCR

on:
  push:
    branches:
      - main              # main 브랜치 push 시에만 실행

permissions:
  contents: read          # 소스 코드 읽기
  packages: write         # GHCR 이미지 푸시 권한

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout source
        uses: actions/checkout@v4

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}    # 자동 제공 (별도 시크릿 불필요)

      - name: Build and push Docker image
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: |
            ghcr.io/${{ github.repository }}/lunch-api:latest
            ghcr.io/${{ github.repository }}/lunch-api:${{ github.sha }}
```

**동작 흐름:**
```
개발자가 main 브랜치에 push
    ↓
GitHub Actions 트리거
    ↓
① actions/checkout@v4 → 소스 체크아웃
    ↓
② docker/login-action@v3 → GHCR 로그인
   (GITHUB_TOKEN 자동 사용, 별도 시크릿 설정 불필요)
    ↓
③ docker/build-push-action@v6 → Docker 빌드 & 푸시
    ↓
생성되는 이미지:
  ghcr.io/<owner>/<repo>/lunch-api:latest       ← 항상 최신 코드
  ghcr.io/<owner>/<repo>/lunch-api:<commit-sha> ← 특정 커밋 롤백 가능
```

**태그 전략:**
- `latest` — `app_deploy` role의 기본값이 이 태그를 사용
- `<commit-sha>` — 문제 발생 시 `defaults/main.yml`의 `app_image` 태그를 특정 커밋으로 변경하여 롤백

---

### 4.7 로컬 실행

```bash
# 방법 1: Docker로 실행
docker build -t lunch-api .
docker run -p 8000:8000 lunch-api

# 방법 2: 직접 실행
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

```bash
# 접속 확인
http://localhost:8000           # 프론트엔드 (점심 뭐 먹지?)
http://localhost:8000/docs      # Swagger API 문서
http://localhost:8000/health    # 헬스체크
http://localhost:8000/api/menus # 전체 메뉴 목록
http://localhost:8000/api/random # 랜덤 추천
http://localhost:8000/api/spin?ticks=10&seed=test # 룰렛 (고정 결과)
```

---

### 4.8 K8s 배포 설정 (`app_deploy` role)

Ansible `app_deploy` role이 아래 변수로 K8s 리소스를 생성합니다 (`defaults/main.yml`):

```yaml
app_name: lunch-api
app_namespace: lunch
app_image: ghcr.io/hjh6709/lunch_app_second/lunch-api:latest
app_replicas: 2
container_port: 8000
service_type: NodePort
service_port: 80
node_port: 30080
```

**생성되는 K8s 리소스:**

| 리소스 | 이름 | 주요 설정 |
|--------|------|-----------|
| Namespace | `lunch` | 앱 전용 네임스페이스 |
| Deployment | `lunch-api` | replicas=2, image=GHCR latest, containerPort=8000 |
| Service | `lunch-api` | type=NodePort, port=80→8000, nodePort=30080 |

**포트 매핑 전체 흐름:**
```
외부 사용자
  → Nginx (:80)
    → Worker (:30080)  ← NodePort
      → Service (:80)
        → Pod (:8000)  ← containerPort
          → Uvicorn
```

---

### 4.9 앱 → 인프라 전체 연결 흐름 (End-to-End)

```
① 개발자가 코드 수정 후 main 브랜치에 push
    ↓
② GitHub Actions가 Docker 이미지 빌드
    ↓
③ GHCR에 이미지 푸시 (latest + commit-sha 태그)
    ↓
④ Ansible app_deploy role 실행 (--tags deploy)
    ↓
⑤ K3s Master에서 kubectl apply 실행
   (namespace.yaml → deployment.yaml → service.yaml)
    ↓
⑥ K3s Worker가 GHCR에서 이미지 Pull
   (Worker → NAT Gateway → Internet → GHCR)
    ↓
⑦ Pod 2개 생성 (각 Worker에 1개씩 분산)
   Uvicorn이 0.0.0.0:8000에서 Listen
    ↓
⑧ NodePort Service가 :30080 → :8000 매핑
    ↓
⑨ Nginx(:80)가 Worker1:30080 + Worker2:30080으로 Reverse Proxy
   (라운드로빈 부하분산)
    ↓
⑩ 외부에서 http://<MONITORING_PUBLIC_IP>/ 로 접속 가능
```

---

## 5. Ansible Roles 설명

### 5.1 chrony

EC2 시간 동기화 설정 (AWS Time Sync + Ubuntu NTP pool).
`/etc/chrony/chrony.conf` 템플릿 배포 후 서비스 재시작.

### 5.2 k3s_master

K3s server 설치, 토큰 생성 및 Worker에 공유.
`/home/ubuntu/.kube/config` kubeconfig 설정.
옵션: Traefik/ServiceLB disable, Master taint 적용.

### 5.3 k3s_worker

Master 토큰 + endpoint로 K3s agent 설치 및 클러스터 Join.
kubelet Ready 대기 후 서비스 활성화.

### 5.4 node_exporter

Master/Worker 노드에 Node Exporter 컨테이너 실행 (포트 9100).
`site.yml`에서 `hosts: k3s_cluster`로 실행.

### 5.5 monitoring

Monitoring 서버에 Docker Compose 기반 스택 구성.
Prometheus(9090) + Grafana(3000) + Node Exporter(9100).
Prometheus 설정에서 Master/Worker를 scrape 대상에 포함.

### 5.6 app_deploy

GHCR 이미지 기반 K8s 배포.
Namespace(`lunch`) → Deployment(`lunch-api`, replicas=2) → Service(NodePort 30080).
`kubectl rollout status`로 배포 완료 확인.

### 5.7 nginx_proxy

Monitoring 서버에 Nginx 설치.
80포트로 들어오는 요청을 Worker NodePort(30080) upstream으로 프록시.
외부 접속의 entrypoint 역할.

---

## 6. Ansible Inventory 핵심 포인트

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

- `./key/Hello_kt.pem`은 `ansible/` 폴더 기준 **상대경로** (환경 독립적)
- Private 노드는 Monitoring 서버를 **Bastion(ProxyCommand)**으로 경유하여 접속

---

## 7. 실행 방법

### 7.1 Terraform Apply

```bash
cd terraform
terraform init
terraform apply
```

### 7.2 Ansible 준비

```bash
cd ../ansible
chmod 600 ./key/Hello_kt.pem
```

### 7.3 접속 확인 (가장 먼저)

```bash
ansible -i inventory/aws.ini master -m ping
```

> `pong`이 돌아오면 정상

### 7.4 전체 실행 (한 번에)

```bash
ansible-playbook -i inventory/aws.ini site.yml
```

---

## 8. 단계별 실행 (태그)

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

## 9. 정상 동작 확인

### 9.1 K3s 노드 Ready 확인

```bash
ansible -i inventory/aws.ini master -b -m shell \
  -a "kubectl get nodes -o wide"
```

### 9.2 앱 배포 상태 확인

```bash
ansible -i inventory/aws.ini master -b -m shell \
  -a "kubectl -n lunch get deploy,svc,pods -o wide"
```

### 9.3 Node Exporter 확인 (Worker 내부)

```bash
ansible -i inventory/aws.ini worker -b -m shell \
  -a "curl -s http://localhost:9100/metrics | head"
```

### 9.4 Prometheus scrape 확인

```bash
ansible -i inventory/aws.ini monitoring -b -m shell \
  -a "curl -s http://localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | [.labels.job,.discoveredLabels.__address__,.health] | @tsv' | head"
```

> `health`가 `up`이면 정상

### 9.5 외부 접속 확인

```bash
# 브라우저
http://<MONITORING_PUBLIC_IP>/

# CLI
curl -I http://<MONITORING_PUBLIC_IP>/
```

---

## 10. 접속 정보

| 서비스 | URL | 비고 |
|--------|-----|------|
| **Lunch App** | `http://<MONITORING_PUBLIC_IP>/` | Nginx Reverse Proxy 경유 |
| **Swagger API 문서** | `http://<MONITORING_PUBLIC_IP>/docs` | FastAPI 자동 생성 |
| **Grafana** | `http://<MONITORING_PUBLIC_IP>:3000` | 초기 계정 `admin` / `admin` |
| **Prometheus** | `http://<MONITORING_PUBLIC_IP>:9090` | |

---

## 11. 트러블슈팅

### 11.1 Permission denied (publickey)

```bash
# 키 권한 확인
chmod 600 ./key/Hello_kt.pem

# aws.ini 의 ansible_ssh_private_key_file 경로가 ./key/Hello_kt.pem 인지 확인
```

### 11.2 로컬에서 10.0.x.x 접속이 안 됨

Private IP는 로컬에서 직접 접근 불가 (정상).
Monitoring 서버(Bastion) 경유 또는 Ansible로 내부에서 확인해야 합니다.

### 11.3 GHCR 이미지 Pull 실패

GHCR 패키지가 Private인 경우 `imagePullSecrets` 설정이 필요하거나,
GitHub 패키지 설정에서 Public으로 변경해야 합니다.
또한 NAT Gateway가 비활성화 상태면 Worker가 외부에 접근할 수 없으므로 `enable-nat.sh`로 활성화 필요.

---

## 12. 보안 / 운영 메모

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

## 13. 현재 진행 상황

- [x] Terraform 인프라 구성
- [x] Private K3s 클러스터 구성 (Master 1 + Worker 2)
- [x] Monitoring 서버 구성 (Prometheus / Grafana)
- [x] Node Exporter 수집 정상 (health: up)
- [x] FastAPI 점심 메뉴 추천 앱 개발 (백엔드 + 프론트엔드)
- [x] GitHub Actions → GHCR 이미지 자동 빌드 (CI/CD)
- [x] GHCR 이미지 K8s 배포 (replicas=2, NodePort=30080)
- [x] Nginx Reverse Proxy로 외부 접속 완료
- [ ] 도메인 연결 / HTTPS (추후)

---

## 14. 자동 생성 파일 흐름 (Terraform → Ansible 연결 구조)

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

## 15. site.yml 실행 흐름 (Step 1 ~ Step 8)

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

## 16. Nginx Upstream 구조 설명

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

## 17. 기술 스택

`AWS (EC2, VPC, SG)` · `Terraform` · `Ansible` · `K3s` · `FastAPI` · `Docker / GHCR` · `GitHub Actions` · `Prometheus / Grafana` · `Nginx`
