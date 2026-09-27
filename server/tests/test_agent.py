import asyncio
import json
from pathlib import Path

from app.agent import SNAPSHOT_HEADER, AgentRunner, Task, compact_history
from app.llm import LlmResponse, Message
from app.safety import ALLOWED, KIND_LABELS, SafetyPolicy, classify, site_of

from .fakes import FakeBrowser, ScriptedLlm, call, last_tool_result


async def run_with_decisions(runner: AgentRunner, task: Task, prompt: str, decisions: list):
    """에이전트를 돌리면서, 승인·질문·도움 요청이 오면 decisions 순서대로 답한다 (앱 역할)."""
    job = asyncio.create_task(runner.run(task, prompt))
    while not job.done():
        await asyncio.sleep(0.01)
        if task.pending and decisions:
            task.resolve(task.pending.type, decisions.pop(0))
    await job


def test_sensitive_labels_match_shared_table():
    """앱(safety.dart)과 같은 표로 검사해 두 규칙이 어긋나지 않게 한다."""
    table = json.loads((Path(__file__).parent / "sensitive_labels.json").read_text(encoding="utf-8"))
    wrong = [(label, want, classify(label)) for label, want in table["labels"] if classify(label) != want]
    assert not wrong, wrong
    assert list(KIND_LABELS) == table["approval_kinds"] == list(ALLOWED)


def test_grant_is_bound_to_kind_site_and_amount():
    p = SafetyPolicy()
    coupang = "https://m.coupang.com/cart"
    assert "request_approval(kind: purchase)" in p.authorize("결제하기", coupang)

    p.grant("send_email", "메일 전송 승인", coupang)
    assert "다시 승인" in p.authorize("결제하기", coupang)  # 종류가 다른 승인
    assert p.authorize("결제하기", coupang)  # 막히면서 승인도 소진됨

    p.grant("purchase", "생수 12개 · 8,900원", coupang)
    assert "gmarket.co.kr" in p.authorize("결제하기", "https://m.gmarket.co.kr/")  # 다른 사이트

    p.grant("purchase", "생수 12개 · 8,900원", coupang)
    assert "32,900원" in p.authorize("32,900원 결제하기", "https://checkout.coupang.com/")  # 금액이 바뀜

    p.grant("purchase", "생수 12개 · 8,900원", coupang)
    assert p.authorize("8,900원 결제하기", "https://checkout.coupang.com/") is None  # 같은 사이트·같은 금액

    p.grant("other", "카페 글 게시", "https://m.cafe.naver.com/")
    assert "kind: purchase" in p.authorize("결제하기", "https://m.cafe.naver.com/")  # 기타 승인으로는 결제 불가
    p.grant("booking", "CGV 2매 28,000원", "https://www.cgv.co.kr/")
    assert p.authorize("28,000원 결제하기", "https://m.cgv.co.kr/") is None  # 예약 승인은 마지막 결제까지
    assert p.authorize("장바구니 담기") is None


def test_site_of():
    assert site_of("https://m.coupang.com/x") == "coupang.com"
    assert site_of("https://m.11st.co.kr/") == "11st.co.kr"
    assert site_of("https://www.gov.kr/") == "gov.kr"
    assert site_of(None) is None


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


async def test_click_blocked_when_approved_amount_differs():
    llm = ScriptedLlm([
        call("request_approval", {"kind": "purchase", "title": "결제", "summary": "생수 9,900원"}, "a"),
        call("click", {"element_id": 2}, "b"),
        LlmResponse(text="끝"),
    ])
    browser = FakeBrowser()
    browser.labels[2] = "12,900원 결제하기"
    task = Task("x")
    await run_with_decisions(AgentRunner(llm, browser), task, "x", [{"approved": True}])
    assert browser.clicked == []
    assert "12,900원" in last_tool_result(llm.seen[2])
