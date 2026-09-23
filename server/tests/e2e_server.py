"""앱(Flutter) ↔ 서버 계약 테스트용: 실제 FastAPI 서버를 가짜 LLM·가짜 브라우저로 띄운다.

    python -m tests.e2e_server <port>
"""

import sys

import uvicorn

from app.config import Settings
from app.llm import LlmResponse
from app.main import create_app
from tests.fakes import FakeBrowser, ScriptedLlm, call

llm = ScriptedLlm([
    call("open_url", {"url": "https://m.coupang.com"}, "a"),
    call("request_approval", {"kind": "purchase", "title": "생수 결제", "summary": "삼다수 2L x12 9,900원"}, "b"),
    call("click", {"element_id": 2}, "c"),
    call("ask_user", {"question": "영수증을 메일로 받을까요?", "choices": ["예", "아니오"]}, "d"),
    call("finish", {"summary": "주문 완료"}, "e"),
    LlmResponse(text="후속 답변"),
])
app = create_app(Settings(agent_token="e2e-token"), browser=FakeBrowser(), llm=llm)

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=int(sys.argv[1]), log_level="warning")
