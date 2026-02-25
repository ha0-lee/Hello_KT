# 🍽️ 점메추 (점심 메뉴 추천)

> 오늘 점심 뭐 먹지? 고민은 여기까지만. 버튼 한 번이면 끝.

점심 메뉴 선택 장애를 해결해주는 간단한 웹 서비스입니다.

---

## 주요 기능

- 그냥 골라줘 — 등록된 메뉴 중 하나를 즉시 랜덤 추천
- 룰렛으로 고르기 — 메뉴가 빠르게 돌아가다 하나에 멈추는 룰렛 연출
- Swagger UI — `/docs` 경로에서 API 문서 자동 제공

## 기술 스택

| 구분 | 기술 |
|------|------|
| Backend | FastAPI (Python 3.11) |
| Server | Uvicorn |
| Frontend | Vanilla HTML/CSS/JS (단일 파일) |
| 컨테이너 | **Docker** |
| CI/CD | **GitHub Actions** → GHCR 자동 푸시 |

## 프로젝트 구조

```
Hello_KT/
├── app/
│   ├── main.py            # FastAPI 앱 (API 엔드포인트 정의)
│   ├── menus.json          # 메뉴 데이터 (JSON)
│   └── static/
│       └── index.html      # 프론트엔드 (SPA)
├── .github/
│   └── workflows/
│       └── ghcr.yml        # GHCR 빌드/푸시 워크플로우
├── Dockerfile
├── requirements.txt
└── README.md
```

## API 엔드포인트

| Method | Path | 설명 |
|--------|------|------|
| `GET` | `/` | 프론트엔드 페이지 |
| `GET` | `/health` | 헬스체크 (`{"ok": true}`) |
| `GET` | `/api/menus` | 전체 메뉴 목록 조회 |
| `GET` | `/api/random` | 메뉴 1개 랜덤 추천 |
| `GET` | `/api/spin` | 룰렛 결과 + 연출용 tick 데이터 반환 |

### `/api/spin` 파라미터

| 파라미터 | 타입 | 기본값 | 설명 |
|----------|------|--------|------|
| `seed` | string (optional) | `null` | 동일 seed → 동일 결과 (테스트용) |
| `ticks` | int | `18` | 룰렛이 지나가는 칸 수 (5~60) |

## 로컬 실행

### Docker (권장)

```bash
docker build -t lunch-api .
docker run -p 8000:8000 lunch-api
```

### 직접 실행

```bash
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

실행 후 http://localhost:8000 접속

## CI/CD

`main` 브랜치에 push하면 GitHub Actions가 자동으로 Docker 이미지를 빌드하여 **GHCR**(GitHub Container Registry)에 푸시합니다.

```
ghcr.io/<owner>/<repo>/lunch-api:latest
ghcr.io/<owner>/<repo>/lunch-api:<commit-sha>
```

## 메뉴 커스터마이즈

`app/menus.json` 파일을 수정하면 추천 메뉴 목록을 변경할 수 있습니다.

```json
{
    "version": 1,
    "menus": [
        "김치찌개",
        "돈까스",
        "제육볶음",
        "..."
    ]
}
```
