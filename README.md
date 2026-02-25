🍱 Lunch Menu Recommendation Service

FastAPI 기반 점심 메뉴 추천 서비스입니다.
랜덤 추천 및 룰렛 방식 추천 기능을 제공합니다.

📌 프로젝트 개요

이 서비스는 다음을 목표로 개발되었습니다:

FastAPI 기반 REST API 구현

정적 파일(Frontend) + API 서버 통합 구조

Kubernetes 배포를 고려한 헬스체크 엔드포인트 구성

Seed 기반 랜덤 처리로 재현 가능한 테스트 지원

GHCR + k3s 배포 환경 연동

🏗 기술 스택

Backend: FastAPI

Validation: Pydantic

Container: Docker

Registry: GHCR

Orchestration: Kubernetes (k3s)

Infra: AWS (EC2, VPC, NAT, Bastion)

📂 프로젝트 구조
app/
 ├── main.py        # FastAPI 애플리케이션
 ├── menus.json     # 메뉴 데이터
 └── static/        # 정적 파일 (index.html 등)
🚀 주요 기능
1️⃣ 루트 페이지
GET /

static/index.html 반환

2️⃣ 헬스 체크
GET /health

응답 예시:

{
  "ok": true
}

Kubernetes Liveness/Readiness Probe용

ALB Target Group 헬스체크용

3️⃣ 랜덤 추천
GET /api/random

응답 예시:

{
  "menu": "김치찌개"
}
4️⃣ 전체 메뉴 조회
GET /api/menus

응답 예시:

{
  "count": 5,
  "menus": ["김치찌개", "돈까스", "비빔밥"]
}
5️⃣ 룰렛 방식 추천
GET /api/spin
Query Parameters
파라미터	설명
seed	동일 seed 입력 시 동일 결과
ticks	룰렛 회전 횟수 (5~60)

응답 예시:

{
  "result": "돈까스",
  "ticks": ["비빔밥", "라면", "김밥", "돈까스"],
  "duration_ms": 3
}
🎯 설계 포인트
✅ Seed 기반 랜덤 처리

테스트 환경에서 동일 결과 재현 가능

해시 기반 시드 처리로 안정성 확보

✅ Health Endpoint 제공

Kubernetes 운영 환경 고려

ALB 헬스체크 대응 가능

✅ Static + API 통합

단일 컨테이너로 프론트/백엔드 제공

배포 단순화

🐳 Docker 실행 방법
docker build -t lunch-app .
docker run -p 8000:8000 lunch-app

브라우저 접속:

http://localhost:8000
