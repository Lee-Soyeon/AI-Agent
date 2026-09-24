from __future__ import annotations

from typing import Any

from app.browser import PageSnapshot
from app.llm import LlmResponse, Message, ToolCall, ToolSpec


class ScriptedLlm:
    def __init__(self, turns: list[LlmResponse]):
        self.turns = list(turns)
        self.seen: list[list[Message]] = []

    async def complete(self, system: str, messages: list[Message], tools: list[ToolSpec]) -> LlmResponse:
        self.seen.append([Message(**vars(m)) for m in messages])
        return self.turns.pop(0)


def call(name: str, args: dict[str, Any], id: str = "c") -> LlmResponse:
    return LlmResponse(tool_calls=[ToolCall(id, name, args)])


def last_tool_result(messages: list[Message]) -> str:
    return [m for m in messages if m.role == "tool"][-1].text or ""


class FakeBrowser:
    def __init__(self) -> None:
        self.labels = {1: "장바구니 담기", 2: "결제하기", 3: "비밀번호", 4: "카드번호"}
        self.done_after: int | None = None  # payment_done 이 몇 번째 확인부터 True 인지
        self.done_checks = 0
        self.clicked: list[int] = []
        self.visited: list[str] = []
        self.inputs: list[dict[str, Any]] = []

    async def navigate(self, url: str) -> None:
        self.visited.append(url)

    async def current_url(self) -> str:
        return "https://m.coupang.com/"

    async def snapshot(self) -> PageSnapshot:
        return PageSnapshot({
            "url": "https://m.coupang.com/", "title": "쿠팡", "text": "본문",
            "elements": [{"id": k, "tag": "button", "label": v} for k, v in self.labels.items()],
        })

    async def describe(self, eid: int) -> dict[str, Any]:
        return {
            "ok": eid in self.labels,
            "label": self.labels.get(eid, ""),
            "type": "password" if eid == 3 else "",
            "paymentField": eid == 4,
        }

    async def click(self, eid: int) -> dict[str, Any]:
        self.clicked.append(eid)
        return {"ok": True}

    async def type_text(self, eid: int, text: str, submit: bool = False) -> dict[str, Any]:
        return {"ok": True}

    async def scroll(self, direction: str) -> dict[str, Any]:
        return {"ok": True}

    async def go_back(self) -> None:
        pass

    async def screenshot(self) -> bytes | None:
        return b"\xff\xd8jpeg"

    async def payment_done(self) -> bool:
        self.done_checks += 1
        return self.done_after is not None and self.done_checks >= self.done_after

    async def user_input(self, event: dict[str, Any]) -> None:
        self.inputs.append(event)
