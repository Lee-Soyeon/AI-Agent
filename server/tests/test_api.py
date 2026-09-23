import time

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.llm import LlmResponse
from app.main import create_app

from .fakes import FakeBrowser, ScriptedLlm, call

AUTH = {"Authorization": "Bearer secret"}


def make(llm, browser=None):
    s = Settings(agent_token="secret")
    return create_app(s, browser=browser or FakeBrowser(), llm=llm)


def wait(client, task_id, pred, timeout=3.0):
    end = time.time() + timeout
    while time.time() < end:
        data = client.get(f"/tasks/{task_id}", headers=AUTH).json()
        if pred(data):
            return data
        time.sleep(0.02)
    raise AssertionError(f"timeout: {data}")


def test_token_required():
    with pytest.raises(RuntimeError):
        create_app(Settings(agent_token=""), browser=FakeBrowser(), llm=ScriptedLlm([]))
    with TestClient(make(ScriptedLlm([]))) as c:
        assert c.get("/health").status_code == 200
        assert c.post("/tasks", json={"prompt": "x"}).status_code == 401
        assert c.post("/tasks", json={"prompt": "x"}, headers={"Authorization": "Bearer nope"}).status_code == 401


def test_task_runs_in_background_and_waits_for_approval():
    llm = ScriptedLlm([
        call("open_url", {"url": "https://m.coupang.com"}, "a"),
        call("request_approval", {"kind": "purchase", "title": "생수 결제", "summary": "9,900원"}, "b"),
        call("click", {"element_id": 2}, "c"),
        call("finish", {"summary": "주문 완료"}, "d"),
    ])
    browser = FakeBrowser()
    with TestClient(make(llm, browser)) as c:
        t = c.post("/tasks", json={"prompt": "생수 주문"}, headers=AUTH).json()
        # 진행 중에는 두 번째 작업을 받지 않는다
        assert c.post("/tasks", json={"prompt": "또"}, headers=AUTH).status_code == 409

        data = wait(c, t["id"], lambda d: d["status"] == "waiting_approval")
        assert data["pending"]["type"] == "approval"
        assert data["pending"]["title"] == "생수 결제"
        assert c.get(f"/tasks/{t['id']}/screenshot", headers=AUTH).content.startswith(b"\xff\xd8")

        assert c.post(f"/tasks/{t['id']}/approval", json={"approved": True}, headers=AUTH).json() == {"ok": True}
        data = wait(c, t["id"], lambda d: d["status"] == "finished")
        assert data["result"] == "주문 완료"
        assert browser.clicked == [2]
        # since 로 새 로그만 받을 수 있다
        assert c.get(f"/tasks/{t['id']}?since={data['log_count']}", headers=AUTH).json()["logs"] == []
        assert c.get("/tasks/current", headers=AUTH).json()["id"] == t["id"]


def test_followup_and_cancel():
    llm = ScriptedLlm([
        LlmResponse(text="첫 답"),
        call("ask_user", {"question": "어느 것?"}),
    ])
    with TestClient(make(llm)) as c:
        t = c.post("/tasks", json={"prompt": "a"}, headers=AUTH).json()
        wait(c, t["id"], lambda d: d["status"] == "finished")
        c.post(f"/tasks/{t['id']}/followup", json={"prompt": "b"}, headers=AUTH)
        wait(c, t["id"], lambda d: d["status"] == "waiting_user")
        assert c.post(f"/tasks/{t['id']}/approval", json={"approved": True}, headers=AUTH).status_code == 409
        c.post(f"/tasks/{t['id']}/cancel", headers=AUTH)
        wait(c, t["id"], lambda d: d["status"] == "cancelled")


def test_live_websocket_requires_token_and_forwards_input(monkeypatch):
    import app.main as main

    class FakeCast:
        def __init__(self, browser, send):
            self.send = send

        async def start(self):
            await self.send({"type": "frame", "data": "AAA", "width": 412, "height": 915, "url": "https://x"})

        async def stop(self):
            pass

    monkeypatch.setattr(main, "Screencast", FakeCast)
    browser = FakeBrowser()
    with TestClient(make(ScriptedLlm([]), browser)) as c:
        with pytest.raises(Exception):
            with c.websocket_connect("/live?token=nope") as ws:
                ws.receive_json()
        with c.websocket_connect("/live?token=secret") as ws:
            assert ws.receive_json()["type"] == "frame"
            ws.send_json({"type": "tap", "x": 10, "y": 20})
            ws.send_json({"type": "type", "text": "hello"})
        time.sleep(0.1)
        assert browser.inputs == [{"type": "tap", "x": 10, "y": 20}, {"type": "type", "text": "hello"}]
