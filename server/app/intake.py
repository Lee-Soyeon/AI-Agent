"""내 것부터 넣기: 사용자가 올린 사진·파일·글을 LLM 이 읽고 "이걸로 할 수 있는 일" 칩 3개를 만든다.

실패하거나 느리면(8초) 레시피 카탈로그의 기본 칩으로 대체한다. 홈 화면이 멈추지 않는 것이 우선이다.
"""

from __future__ import annotations

import asyncio
import json
import logging
import re
from typing import Any

from . import recipes, ui_schema
from .llm import LlmProvider, Message

log = logging.getLogger(__name__)

TIMEOUT = 8.0
KINDS = ("photo", "file", "text")
QUESTION = "이걸로 뭘 할까요?"

SYSTEM = """사용자가 올린 내용(사진·파일·글)을 보고, 그것으로 AI 가 해 줄 수 있는 일 3개를 고른다.
반드시 아래 JSON 하나만 출력한다. 다른 말·코드 블록 금지.
{"summary": "<내용을 한 줄로>", "options": ["<일 1>", "<일 2>", "<일 3>"]}
규칙:
- options 는 정확히 3개. 각각 12자 이내, '빈 열 채우기' '쉽게 풀기' 처럼 동사형 명사로 끝낸다.
- 올린 내용에 실제로 쓸 수 있는 일만. 내용과 상관없는 일 금지.
- 결제·송금·로그인이 필요한 일은 고르지 않는다.
- 한국어."""


def _parse(text: str) -> dict[str, Any] | None:
    t = (text or "").strip()
    t = re.sub(r"^```(?:json)?\s*|\s*```$", "", t, flags=re.S).strip()
    try:
        v = json.loads(t)
    except json.JSONDecodeError:
        m = re.search(r"\{.*\}", t, flags=re.S)
        if not m:
            return None
        try:
            v = json.loads(m.group(0))
        except json.JSONDecodeError:
            return None
    if not isinstance(v, dict):
        return None
    opts = [str(o).strip()[:12] for o in (v.get("options") or []) if str(o).strip()]
    opts = list(dict.fromkeys(opts))[:3]
    if len(opts) < 2:
        return None
    return {"summary": str(v.get("summary") or "").strip()[:120], "options": opts}


def _user_message(kind: str, name: str | None, text: str | None, image_base64: str | None, mime: str | None) -> Message:
    head = {"photo": "사진을 올렸습니다.", "file": f"파일을 올렸습니다: {name or '(이름 없음)'}", "text": "글을 붙여 넣었습니다."}[kind]
    body = (text or "").strip()
    if len(body) > 4000:
        body = body[:4000] + "\n…(이하 생략)"
    images = [{"mime": mime or "image/jpeg", "data": image_base64}] if kind == "photo" and image_base64 else []
    return Message(role="user", text=f"{head}\n\n{body}".strip(), images=images)


def fallback(kind: str) -> dict[str, Any]:
    return {
        "ui": ui_schema.validate({"type": "chips", "question": QUESTION, "options": recipes.intake_defaults(kind), "allow_free": True}),
        "summary": "",
        "fallback": True,
    }


async def suggest(
    llm: LlmProvider,
    *,
    kind: str,
    name: str | None = None,
    text: str | None = None,
    image_base64: str | None = None,
    mime: str | None = None,
    timeout: float = TIMEOUT,
) -> dict[str, Any]:
    if kind not in KINDS:
        raise ValueError(f"kind 는 {', '.join(KINDS)} 중 하나입니다.")
    try:
        res = await asyncio.wait_for(llm.complete(SYSTEM, [_user_message(kind, name, text, image_base64, mime)], []), timeout)
        parsed = _parse(res.text or "")
    except Exception as e:  # noqa: BLE001 — 어떤 실패든 기본 칩으로
        log.warning("intake 실패, 기본 칩으로: %s", e)
        parsed = None
    if not parsed:
        return fallback(kind)
    tree = ui_schema.coerce({"type": "chips", "question": QUESTION, "options": parsed["options"], "allow_free": True})
    if tree["type"] != "chips":
        return fallback(kind)
    return {"ui": tree, "summary": parsed["summary"], "fallback": False}
