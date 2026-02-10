from fastapi import FastAPI, Query
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel
from pathlib import Path
import json
import random
import time
import hashlib

app = FastAPI(title="점심 메뉴 추천 서비스")

STATIC_DIR = Path(__file__).parent / "static"

app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

DATA_PATH = Path(__file__).parent / "menus.json"

class MenuResponse(BaseModel):
    menu: str

class SpinResponse(BaseModel):
    result: str
    ticks: list[str]   # 룰렛이 돌아가며 지나간 메뉴들(프론트 연출용)
    duration_ms: int  # 룰렛이 돌아간 시간(프론트 연출용)

def load_menus() -> list[str]:
    if not DATA_PATH.exists():
        raise RuntimeError("메뉴 데이터 파일이 없습니다.")
    data = json.loads(DATA_PATH.read_text(encoding="utf-8"))
    menus = data.get("menus", [])
    if not menus:
        raise RuntimeError("메뉴 데이터가 더이상 없습니다.")
    return menus

@app.get("/")
def root():
    return FileResponse(STATIC_DIR / "index.html")

@app.get("/health")

def health():
    return {"ok": True}

@app.get("/api/random", response_model=MenuResponse)
def random_menu():
    menus = load_menus()
    return { "menu": random.choice(menus)}

@app.get("/api/menus")
def get_menus():
    menus = load_menus()
    return {"count": len(menus), "menus": menus}

@app.get("/api/spin", response_model=SpinResponse)
def spin_menu(
    seed: str | None = Query(default=None, description="같은 seed면 결과를 고정하고 싶을 때 사용"),
    ticks: int = Query(default=18, ge=5, le=60, description="룰렛이 지나가는 칸 수 (프론트 연출용)"),
):
    menus = load_menus()

    # seed가 있으면 같은 결과가 나오도록 (데모/테스트용)
    rng = random.Random()
    if seed is None:
        rng.seed(time.time_ns())
    else:
        # 문자열 seed를 안정적인 정수 seed로 변환
        h = hashlib.sha256(seed.encode("utf-8")).hexdigest()
        rng.seed(int(h[:16], 16))

    start = time.time()

    # 룰렛 지나가는 목록
    tick_list = [rng.choice(menus) for _ in range(ticks - 1)]

    # 마지막은 최종 결과(룰렛 멈추는 느낌)
    result = rng.choice(menus)
    tick_list.append(result)

    duration_ms = int((time.time() - start) * 1000)

    return {
        "result": result,
        "ticks": tick_list,
        "duration_ms": duration_ms,
    }
