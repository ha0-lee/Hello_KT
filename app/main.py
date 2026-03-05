# FastAPI 핵심 모듈
from fastapi import FastAPI, Query
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse

# 데이터 검증용 모델
from pydantic import BaseModel

# 파일 경로 관리
from pathlib import Path

# 데이터 처리용 모듈
import json
import random
import time
import hashlib


# FastAPI 애플리케이션 생성
# title은 Swagger 문서에 표시됨
app = FastAPI(title="점심 메뉴 추천 서비스")


# -------------------------------
# 📁 정적 파일 경로 설정
# -------------------------------

# 현재 파일(main.py)이 있는 디렉토리 기준으로 static 폴더 지정
STATIC_DIR = Path(__file__).parent / "static"

# /static 경로로 정적 파일 제공
# ex) /static/index.html
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


# -------------------------------
# 📁 메뉴 데이터 파일 경로
# -------------------------------

# menus.json 파일 경로
DATA_PATH = Path(__file__).parent / "menus.json"


# -------------------------------
# 📦 응답 모델 정의 (Swagger 문서 자동화용)
# -------------------------------

class MenuResponse(BaseModel):
    menu: str  # 단일 추천 메뉴


class SpinResponse(BaseModel):
    result: str              # 최종 선택된 메뉴
    ticks: list[str]         # 룰렛이 돌아가며 지나간 메뉴 목록 (프론트 연출용)
    duration_ms: int         # 룰렛 실행 시간 (프론트 연출용)


# -------------------------------
# 📥 메뉴 데이터 로드 함수
# -------------------------------

def load_menus() -> list[str]:
    """
    menus.json 파일을 읽어서 메뉴 리스트를 반환
    파일이 없거나 비어있으면 에러 발생
    """
    if not DATA_PATH.exists():
        raise RuntimeError("메뉴 데이터 파일이 없습니다.")

    data = json.loads(DATA_PATH.read_text(encoding="utf-8"))
    menus = data.get("menus", [])

    if not menus:
        raise RuntimeError("메뉴 데이터가 더이상 없습니다.")

    return menus


# -------------------------------
# 🏠 루트 페이지
# -------------------------------

@app.get("/")
def root():
    """
    기본 접속 시 index.html 반환
    """
    return FileResponse(STATIC_DIR / "index.html")


# -------------------------------
# ❤️ 헬스체크 API (ALB, Kubernetes용)
# -------------------------------

@app.get("/health")
def health():
    """
    서버 상태 확인용 엔드포인트
    ALB Target Group, Kubernetes Liveness/Readiness Probe에 사용 가능
    """
    return {"ok": True}


# -------------------------------
# 🎲 단순 랜덤 메뉴 추천 API
# -------------------------------

@app.get("/api/random", response_model=MenuResponse)
def random_menu():
    """
    단순 랜덤 추천
    """
    menus = load_menus()
    return {"menu": random.choice(menus)}


# -------------------------------
# 📋 전체 메뉴 조회 API
# -------------------------------

@app.get("/api/menus")
def get_menus():
    """
    전체 메뉴 목록 반환
    """
    menus = load_menus()
    return {
        "count": len(menus),
        "menus": menus
    }


# -------------------------------
# 🎡 룰렛 방식 추천 API
# -------------------------------

@app.get("/api/spin", response_model=SpinResponse)
def spin_menu(
    seed: str | None = Query(
        default=None,
        description="같은 seed면 결과를 고정하고 싶을 때 사용 (테스트/데모용)"
    ),
    ticks: int = Query(
        default=18,
        ge=5,
        le=60,
        description="룰렛이 지나가는 칸 수 (프론트 연출용)"
    ),
):
    """
    룰렛 애니메이션을 위한 API
    - seed를 사용하면 항상 같은 결과가 나오도록 고정 가능
    - ticks는 룰렛이 몇 번 지나가는지 제어
    """

    menus = load_menus()

    # 랜덤 객체 생성 (전역 random 대신 독립 RNG 사용)
    rng = random.Random()

    # seed가 없으면 현재 시간 기반
    if seed is None:
        rng.seed(time.time_ns())
    else:
        # 문자열 seed를 해시하여 안정적인 정수로 변환
        h = hashlib.sha256(seed.encode("utf-8")).hexdigest()
        rng.seed(int(h[:16], 16))

    start = time.time()

    # 룰렛이 지나가는 목록 생성
    tick_list = [rng.choice(menus) for _ in range(ticks - 1)]

    # 마지막은 최종 선택 메뉴
    result = rng.choice(menus)
    tick_list.append(result)

    # 실행 시간 계산
    duration_ms = int((time.time() - start) * 1000)

    return {
        "result": result,
        "ticks": tick_list,
        "duration_ms": duration_ms,
    }