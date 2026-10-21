import asyncio

from fastapi.testclient import TestClient

from app import intake
from app.config import Settings
from app.llm import LlmResponse, Message
from app.main import create_app
from app.usage import MeteredLlm, UsageMeter

from .fakes import FakeBrowser, ScriptedLlm

AUTH = {"Authorization": "Bearer secret"}


class SlowLlm:
    async def complete(self, system, messages, tools):
        await asyncio.sleep(5)
        return LlmResponse(text="{}")


async def test_suggest_parses_json_even_in_code_fence():
    llm = ScriptedLlm([LlmResponse(text='```json\n{"summary": "품목·단가 표", "options": ["빈 열 채우기", "합계 내기", "중복 찾기"]}\n```')])
    out = await intake.suggest(llm, kind="file", name="재고.xlsx", text="품목,단가\n물,900")
    assert out["fallback"] is False
    assert out["ui"]["type"] == "chips" and out["ui"]["options"] == ["빈 열 채우기", "합계 내기", "중복 찾기"]
    assert out["summary"] == "품목·단가 표"
    sent = llm.seen[0][0]
    assert sent.role == "user" and "재고.xlsx" in sent.text and "물,900" in sent.text and sent.images == []


async def test_photo_goes_as_image_and_garbage_falls_back():
    llm = ScriptedLlm([LlmResponse(text="그냥 말로 대답")])
    out = await intake.suggest(llm, kind="photo", image_base64="QUJD", mime="image/png")
    assert out["fallback"] is True and out["ui"]["type"] == "chips" and len(out["ui"]["options"]) == 3
    assert llm.seen[0][0].images == [{"mime": "image/png", "data": "QUJD"}]


async def test_timeout_falls_back_quickly():
    out = await intake.suggest(SlowLlm(), kind="text", text="안녕", timeout=0.05)
    assert out["fallback"] is True


async def test_llm_error_falls_back():
    class Boom:
        async def complete(self, *a):
            raise RuntimeError("down")

    out = await intake.suggest(Boom(), kind="text", text="x")
    assert out["fallback"] is True


def test_intake_endpoint_and_usage_limit(tmp_path):
    llm = ScriptedLlm([
        LlmResponse(text='{"summary": "s", "options": ["쉽게 풀기", "요약", "고치기"]}'),
        LlmResponse(text='{"summary": "s", "options": ["쉽게 풀기", "요약", "고치기"]}'),
    ])
    s = Settings(agent_token="secret", data_dir=tmp_path, daily_request_limit=1)
    with TestClient(create_app(s, browser=FakeBrowser(), llm=llm)) as c:
        assert c.post("/intake", json={"kind": "video"}, headers=AUTH).status_code == 400
        r = c.post("/intake", json={"kind": "text", "text": "시편 23편"}, headers=AUTH)
        assert r.status_code == 200 and r.json()["ui"]["options"][0] == "쉽게 풀기"
        u = c.get("/usage", headers=AUTH).json()
        assert u["today"] == 1 and u["daily_limit"] == 1 and u["exceeded"] is True
        r = c.post("/intake", json={"kind": "text", "text": "x"}, headers=AUTH)
        assert r.status_code == 429 and "오늘은 여기까지" in r.json()["detail"]
        assert c.post("/tasks", json={"prompt": "x"}, headers=AUTH).status_code == 429
        assert (tmp_path / "usage.json").exists()


async def test_metered_llm_counts_and_blocks(tmp_path):
    meter = UsageMeter(tmp_path / "u.json", daily_limit=2)
    llm = MeteredLlm(ScriptedLlm([LlmResponse(text="a"), LlmResponse(text="b")]), meter)
    await llm.complete("s", [Message(role="user", text="x")], [])
    await llm.complete("s", [Message(role="user", text="x")], [])
    assert meter.today() == 2 and meter.exceeded()
    try:
        await llm.complete("s", [], [])
        raise AssertionError("한도를 넘었는데 호출됨")
    except Exception as e:  # noqa: BLE001
        assert "오늘은 여기까지" in str(e)
    assert UsageMeter(tmp_path / "u.json").today() == 2  # 디스크에서 복원
