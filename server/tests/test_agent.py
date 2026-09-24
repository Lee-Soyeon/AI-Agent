import asyncio

from app.agent import SNAPSHOT_HEADER, AgentRunner, Task, compact_history
from app.llm import LlmResponse, Message
from app.safety import SafetyPolicy

from .fakes import FakeBrowser, ScriptedLlm, call, last_tool_result


async def run_with_decisions(runner: AgentRunner, task: Task, prompt: str, decisions: list):
    """에이전트를 돌리면서, 승인·질문·도움 요청이 오면 decisions 순서대로 답한다 (앱 역할)."""
    job = asyncio.create_task(runner.run(task, prompt))
    while not job.done():
        await asyncio.sleep(0.01)
        if task.pending and decisions:
            task.resolve(task.pending.type, decisions.pop(0))
    await job


def test_sensitive_patterns():
    p = SafetyPolicy()
    for s in ["결제하기", "32,900원 결제하기", "보내기", "Send", "예약 확정", "회원 탈퇴"]:
        assert p.is_sensitive(s), s
    for s in ["장바구니 담기", "구매하기", "보낸편지함", "Sent", "예약 가능 시간 보기"]:
        assert not p.is_sensitive(s), s


async def test_payment_click_blocked_until_approved_and_only_once():
    llm = ScriptedLlm([
        call("click", {"element_id": 1}, "a"),
        call("click", {"element_id": 2}, "b"),
        call("request_approval", {"kind": "purchase", "title": "결제", "summary": "생수 9,900원"}, "c"),
        call("click", {"element_id": 2}, "d"),
        call("click", {"element_id": 2}, "e"),
        call("finish", {"summary": "완료"}, "f"),
    ])
    browser = FakeBrowser()
    task = Task("생수 사줘")
    await run_with_decisions(AgentRunner(llm, browser), task, task.prompt, [{"approved": True}])

    assert task.status == "finished"
    assert task.result == "완료"
    assert browser.clicked == [1, 2]
    assert "차단됨" in last_tool_result(llm.seen[2])
    assert "차단됨" in last_tool_result(llm.seen[5])
    assert task.screenshot_version > 0


async def test_rejection_feedback_goes_back_to_llm():
    llm = ScriptedLlm([
        call("request_approval", {"kind": "purchase", "title": "결제", "summary": "..."}),
        LlmResponse(text="취소했습니다."),
    ])
    task = Task("사줘")
    await run_with_decisions(AgentRunner(llm, FakeBrowser()), task, "사줘", [{"approved": False, "feedback": "2개로"}])
    assert "2개로" in last_tool_result(llm.seen[1])
    assert task.result == "취소했습니다."


async def test_help_and_question_pause_then_continue():
    llm = ScriptedLlm([
        call("request_user_help", {"reason": "로그인해 주세요"}, "a"),
        call("ask_user", {"question": "몇 개?", "choices": ["1", "2"]}, "b"),
        LlmResponse(text="끝"),
    ])
    task = Task("x")
    statuses = []
    task.listeners.append(lambda: statuses.append(task.status))
    await run_with_decisions(AgentRunner(llm, FakeBrowser()), task, "x", [True, "2"])
    assert "waiting_user" in statuses
    assert "사용자가 직접 처리를 마쳤습니다" in last_tool_result(llm.seen[1])
    assert "사용자 답변: 2" in last_tool_result(llm.seen[2])


async def test_password_field_refused():
    llm = ScriptedLlm([call("type_text", {"element_id": 3, "text": "hunter2"}), LlmResponse(text="끝")])
    task = Task("x")
    await AgentRunner(llm, FakeBrowser()).run(task, "x")
    assert "비밀번호" in last_tool_result(llm.seen[1])


async def test_cancel_while_waiting_for_approval():
    llm = ScriptedLlm([call("request_approval", {"kind": "other", "title": "t", "summary": "s"})])
    task = Task("x")
    job = asyncio.create_task(AgentRunner(llm, FakeBrowser()).run(task, "x"))
    while task.pending is None:
        await asyncio.sleep(0.01)
    task.cancel()
    await job
    assert task.status == "cancelled"


def test_compact_history_keeps_last_two_snapshots():
    msgs = [
        Message(role="tool", text=f"결과\n\n{SNAPSHOT_HEADER}\nURL: https://a/{i}\n긴 본문", tool_call_id=str(i))
        for i in range(4)
    ]
    compact_history(msgs)
    assert "생략됨 — https://a/0" in msgs[0].text
    assert "생략됨" in msgs[1].text
    assert "긴 본문" in msgs[2].text and "긴 본문" in msgs[3].text


HANDOFF = call("handoff_payment", {"title": "쿠팡 결제: 콜라", "summary": "제로 콜라 24캔 19,800원 · 쿠페이"}, "h")


async def test_payment_handoff_completes_automatically_when_done_page_appears(monkeypatch):
    llm = ScriptedLlm([HANDOFF, LlmResponse(text="주문 완료")])
    browser = FakeBrowser()
    browser.done_after = 2
    runner = AgentRunner(llm, browser)
    orig = runner._watch_payment
    monkeypatch.setattr(runner, "_watch_payment", lambda task: orig(task, interval=0.01))
    task = Task("콜라 사줘")
    job = asyncio.create_task(runner.run(task, task.prompt))
    while task.pending is None:
        await asyncio.sleep(0.005)
    assert task.pending.type == "payment" and task.status == "waiting_approval"
    assert "19,800원" in task.to_json()["pending"]["summary"]
    await job  # 사용자가 아무것도 안 눌러도 완료 페이지가 감지되면 넘어간다
    assert task.result == "주문 완료"
    assert "결제를 마쳤습니다" in last_tool_result(llm.seen[1])
    assert browser.clicked == []  # 결제 버튼은 에이전트가 누르지 않는다
    assert any("자동 감지" in e.text for e in task.logs)


async def test_payment_handoff_manual_results():
    for decision, expected in [
        ({"approved": False, "feedback": "12캔으로"}, "12캔으로"),
        ({"approved": True, "completed": False}, "결제를 마치지 않고"),
        ({"approved": True, "completed": True}, "결제를 마쳤습니다"),
    ]:
        llm = ScriptedLlm([HANDOFF, LlmResponse(text="끝")])
        task = Task("x")
        await run_with_decisions(AgentRunner(llm, FakeBrowser()), task, "x", [decision])
        assert expected in last_tool_result(llm.seen[1]), decision


async def test_payment_fields_are_refused():
    llm = ScriptedLlm([call("type_text", {"element_id": 4, "text": "1234"}), LlmResponse(text="끝")])
    await AgentRunner(llm, FakeBrowser()).run(Task("x"), "x")
    assert "handoff_payment" in last_tool_result(llm.seen[1])
