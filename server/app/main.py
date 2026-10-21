"""AI Agent 서버: 앱이 보낸 작업을 서버 브라우저로 백그라운드 실행한다.

실행:  AGENT_TOKEN=... ANTHROPIC_API_KEY=... uvicorn app.main:create_app --factory --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

import asyncio
import logging
import secrets
from contextlib import asynccontextmanager
from typing import Any

from fastapi import Depends, FastAPI, Header, HTTPException, Query, WebSocket, WebSocketDisconnect
from fastapi.responses import Response
from pydantic import BaseModel

from . import catalog
from .agent import AgentRunner, Task
from .browser import BrowserManager, Screencast
from .config import Settings
from .llm import LlmProvider, create_provider
from .store import TaskStore

log = logging.getLogger(__name__)


class TaskIn(BaseModel):
    prompt: str


class ApprovalIn(BaseModel):
    approved: bool
    feedback: str | None = None


class PaymentIn(BaseModel):
    approved: bool
    completed: bool = False
    feedback: str | None = None


class AnswerIn(BaseModel):
    text: str


class OpenIn(BaseModel):
    url: str


def create_app(
    settings: Settings | None = None,
    *,
    browser: Any = None,
    llm: LlmProvider | None = None,
) -> FastAPI:
    settings = settings or Settings()
    settings.validate()
    store = TaskStore(settings.data_dir / "tasks")
    tasks = store.load_all()
    for t in tasks.values():
        store.watch(t)
    state: dict[str, Any] = {"tasks": tasks, "current": None}

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        if browser is None:
            b = BrowserManager(settings.data_dir / "browser-profile", headless=settings.headless,
                               chromium_path=settings.chromium_path)
            await b.start()
            state["browser"] = b
        else:
            state["browser"] = browser
        state["llm"] = llm or create_provider(
            settings.llm_provider,
            settings.llm_model,
            anthropic_key=settings.anthropic_api_key,
            openai_key=settings.openai_api_key,
            gemini_key=settings.gemini_api_key,
            anthropic_workspace_id=settings.anthropic_workspace_id,
            xai_key=settings.xai_api_key,
            openrouter_key=settings.openrouter_api_key,
        )
        yield
        for t in state["tasks"].values():
            t.cancel()
        store.flush(state["tasks"])
        if browser is None:
            await state["browser"].stop()

    app = FastAPI(title="AI Agent Server", lifespan=lifespan)

    def check_token(token: str | None) -> None:
        if settings.allow_no_auth and not settings.agent_token:
            return
        if not token or not secrets.compare_digest(token, settings.agent_token):
            raise HTTPException(401, "인증 실패")

    def auth(authorization: str | None = Header(default=None)) -> None:
        check_token(authorization.removeprefix("Bearer ").strip() if authorization else None)

    def get_task(task_id: str) -> Task:
        t = state["tasks"].get(task_id)
        if not t:
            raise HTTPException(404, "작업을 찾을 수 없습니다.")
        return t

    def busy() -> bool:
        cur: Task | None = state["current"]
        return bool(cur and cur.status in ("running", "waiting_approval", "waiting_user"))

    def launch(task: Task, message: str) -> None:
        runner = AgentRunner(state["llm"], state["browser"], max_steps=settings.max_steps)
        task.runner = asyncio.create_task(runner.run(task, message))

    @app.get("/services", dependencies=[Depends(auth)])
    async def list_services() -> dict[str, Any]:
        return {"services": catalog.services()}

    @app.get("/health")
    async def health() -> dict[str, Any]:
        return {"ok": True}

    @app.post("/tasks", dependencies=[Depends(auth)])
    async def create_task(body: TaskIn) -> dict[str, Any]:
        if busy():
            raise HTTPException(409, "이미 진행 중인 작업이 있습니다. 끝나거나 취소한 뒤 시도하세요.")
        task = Task(body.prompt.strip())
        state["tasks"][task.id] = task
        store.watch(task)
        state["current"] = task
        launch(task, task.prompt)
        return task.to_json()

    @app.get("/tasks", dependencies=[Depends(auth)])
    async def list_tasks() -> list[dict[str, Any]]:
        """지난 작업(대화) 목록, 최근에 바뀐 순."""
        return sorted((t.summary() for t in state["tasks"].values()), key=lambda t: t["updated_at"], reverse=True)

    @app.get("/tasks/current", dependencies=[Depends(auth)])
    async def current_task() -> dict[str, Any] | None:
        cur: Task | None = state["current"]
        return cur.to_json() if cur else None

    @app.get("/tasks/{task_id}", dependencies=[Depends(auth)])
    async def read_task(task_id: str, since: int = 0) -> dict[str, Any]:
        return get_task(task_id).to_json(since)

    @app.post("/tasks/{task_id}/approval", dependencies=[Depends(auth)])
    async def approve(task_id: str, body: ApprovalIn) -> dict[str, Any]:
        if not get_task(task_id).resolve("approval", body.model_dump()):
            raise HTTPException(409, "승인을 기다리는 중이 아닙니다.")
        return {"ok": True}

    @app.post("/tasks/{task_id}/payment", dependencies=[Depends(auth)])
    async def payment(task_id: str, body: PaymentIn) -> dict[str, Any]:
        if not get_task(task_id).resolve("payment", body.model_dump()):
            raise HTTPException(409, "결제를 기다리는 중이 아닙니다.")
        return {"ok": True}

    @app.post("/tasks/{task_id}/answer", dependencies=[Depends(auth)])
    async def answer(task_id: str, body: AnswerIn) -> dict[str, Any]:
        if not get_task(task_id).resolve("question", body.text):
            raise HTTPException(409, "질문을 기다리는 중이 아닙니다.")
        return {"ok": True}

    @app.post("/tasks/{task_id}/help_done", dependencies=[Depends(auth)])
    async def help_done(task_id: str) -> dict[str, Any]:
        if not get_task(task_id).resolve("help", True):
            raise HTTPException(409, "사용자 도움을 기다리는 중이 아닙니다.")
        return {"ok": True}

    @app.post("/tasks/{task_id}/followup", dependencies=[Depends(auth)])
    async def followup(task_id: str, body: TaskIn) -> dict[str, Any]:
        task = get_task(task_id)
        if busy():
            raise HTTPException(409, "이미 진행 중인 작업이 있습니다.")
        state["current"] = task
        launch(task, body.prompt.strip())
        return task.to_json()

    @app.post("/tasks/{task_id}/cancel", dependencies=[Depends(auth)])
    async def cancel(task_id: str) -> dict[str, Any]:
        get_task(task_id).cancel()
        return {"ok": True}

    @app.delete("/tasks/{task_id}", dependencies=[Depends(auth)])
    async def delete_task(task_id: str) -> dict[str, Any]:
        task = get_task(task_id)
        if busy() and state["current"] is task:
            raise HTTPException(409, "진행 중인 작업은 삭제할 수 없습니다. 먼저 취소하세요.")
        del state["tasks"][task_id]
        task.listeners.clear()
        if state["current"] is task:
            state["current"] = None
        store.delete(task_id)
        return {"ok": True}

    @app.get("/tasks/{task_id}/screenshot", dependencies=[Depends(auth)])
    async def screenshot(task_id: str) -> Response:
        shot = get_task(task_id).screenshot
        if not shot:
            raise HTTPException(404, "아직 스크린샷이 없습니다.")
        return Response(shot, media_type="image/jpeg")

    @app.post("/browser/open", dependencies=[Depends(auth)])
    async def open_url(body: OpenIn) -> dict[str, Any]:
        """사용자가 로그인하려고 사이트를 열 때 (에이전트 작업 중에는 불가)."""
        if busy() and not (state["current"].pending and state["current"].pending.type in ("help", "payment")):
            raise HTTPException(409, "에이전트가 브라우저를 쓰는 중입니다.")
        await state["browser"].navigate(body.url)
        return {"ok": True, "url": await state["browser"].current_url()}

    @app.websocket("/live")
    async def live(ws: WebSocket, token: str | None = Query(default=None)) -> None:
        """서버 브라우저 화면을 실시간으로 보내고, 앱의 탭·입력을 브라우저에 전달한다."""
        try:
            check_token(token)
        except HTTPException:
            await ws.close(code=4401)
            return
        await ws.accept()
        send_lock = asyncio.Lock()

        async def send(msg: dict[str, Any]) -> None:
            async with send_lock:
                await ws.send_json(msg)

        cast = Screencast(state["browser"], send)
        await cast.start()
        try:
            while True:
                event = await ws.receive_json()
                try:
                    await state["browser"].user_input(event)
                except Exception as e:  # noqa: BLE001
                    await send({"type": "error", "message": str(e)})
        except WebSocketDisconnect:
            pass
        finally:
            await cast.stop()

    return app
