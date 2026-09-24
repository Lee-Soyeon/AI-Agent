"""공급자(OpenAI / Anthropic / Gemini)와 무관한 도구 호출 LLM 인터페이스. 앱의 lib/llm 과 같은 구조."""

from __future__ import annotations

import asyncio
import json
import time
from dataclasses import dataclass, field
from typing import Any, Protocol

import httpx


@dataclass
class ToolSpec:
    name: str
    description: str
    parameters: dict[str, Any]


@dataclass
class ToolCall:
    id: str
    name: str
    arguments: dict[str, Any]


@dataclass
class Message:
    role: str  # "user" | "assistant" | "tool"
    text: str | None = None
    tool_calls: list[ToolCall] = field(default_factory=list)
    tool_call_id: str | None = None
    tool_name: str | None = None
    raw: Any = None  # 공급자 원본 (Claude 블록, Gemini parts) — 다음 요청에 그대로 되돌려 보냄


@dataclass
class LlmResponse:
    text: str | None = None
    tool_calls: list[ToolCall] = field(default_factory=list)
    raw: Any = None

    def to_message(self) -> Message:
        return Message(role="assistant", text=self.text, tool_calls=self.tool_calls, raw=self.raw)


class LlmError(Exception):
    def __init__(self, message: str, status: int | None = None):
        super().__init__(message)
        self.status = status


class LlmProvider(Protocol):
    async def complete(self, system: str, messages: list[Message], tools: list[ToolSpec]) -> LlmResponse: ...


def _args(raw: Any) -> dict[str, Any]:
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, str) and raw.strip():
        try:
            v = json.loads(raw)
            return v if isinstance(v, dict) else {}
        except json.JSONDecodeError:
            return {}
    return {}


async def _post(client: httpx.AsyncClient, url: str, headers: dict[str, str], body: dict[str, Any]) -> dict[str, Any]:
    res = await client.post(url, headers=headers, json=body, timeout=120)
    if res.status_code >= 300:
        msg = res.text
        try:
            err = res.json().get("error")
            msg = err.get("message", msg) if isinstance(err, dict) else msg
        except Exception:  # noqa: BLE001
            pass
        raise LlmError(msg[:500], res.status_code)
    return res.json()


# ---------------- OpenAI (Chat Completions) ----------------


class OpenAiProvider:
    def __init__(self, api_key: str, model: str, client: httpx.AsyncClient | None = None):
        self.api_key, self.model = api_key, model
        self.client = client or httpx.AsyncClient()

    @staticmethod
    def build_body(model: str, system: str, messages: list[Message], tools: list[ToolSpec]) -> dict[str, Any]:
        out: list[dict[str, Any]] = [{"role": "system", "content": system}]
        for m in messages:
            if m.role == "user":
                out.append({"role": "user", "content": m.text or ""})
            elif m.role == "assistant":
                msg: dict[str, Any] = {"role": "assistant", "content": m.text}
                if m.tool_calls:
                    msg["tool_calls"] = [
                        {
                            "id": c.id,
                            "type": "function",
                            "function": {"name": c.name, "arguments": json.dumps(c.arguments, ensure_ascii=False)},
                        }
                        for c in m.tool_calls
                    ]
                out.append(msg)
            else:
                out.append({"role": "tool", "tool_call_id": m.tool_call_id, "content": m.text or ""})
        body: dict[str, Any] = {"model": model, "messages": out}
        if tools:
            body["tools"] = [
                {"type": "function", "function": {"name": t.name, "description": t.description, "parameters": t.parameters}}
                for t in tools
            ]
            body["tool_choice"] = "auto"
        return body

    @staticmethod
    def parse(data: dict[str, Any]) -> LlmResponse:
        msg = (data.get("choices") or [{}])[0].get("message", {})
        calls = [
            ToolCall(c["id"], c["function"]["name"], _args(c["function"].get("arguments")))
            for c in msg.get("tool_calls") or []
        ]
        return LlmResponse(text=msg.get("content"), tool_calls=calls)

    async def complete(self, system: str, messages: list[Message], tools: list[ToolSpec]) -> LlmResponse:
        data = await _post(
            self.client,
            "https://api.openai.com/v1/chat/completions",
            {"authorization": f"Bearer {self.api_key}"},
            self.build_body(self.model, system, messages, tools),
        )
        return self.parse(data)


# ---------------- Anthropic (Messages) ----------------


class AnthropicProvider:
    def __init__(
        self,
        api_key: str,
        model: str,
        client: httpx.AsyncClient | None = None,
        max_tokens: int = 4096,
        workspace_id: str = "",
    ):
        self.api_key, self.model, self.max_tokens = api_key, model, max_tokens
        self.workspace_id = workspace_id
        self.client = client or httpx.AsyncClient()

    @staticmethod
    def build_body(
        model: str, max_tokens: int, system: str, messages: list[Message], tools: list[ToolSpec]
    ) -> dict[str, Any]:
        out: list[dict[str, Any]] = []
        for m in messages:
            if m.role == "user":
                block = {"type": "text", "text": m.text or ""}
                if out and out[-1]["role"] == "user":
                    out[-1]["content"].append(block)
                else:
                    out.append({"role": "user", "content": [block]})
            elif m.role == "assistant":
                content = m.raw if isinstance(m.raw, list) else [
                    *([{"type": "text", "text": m.text}] if m.text else []),
                    *[{"type": "tool_use", "id": c.id, "name": c.name, "input": c.arguments} for c in m.tool_calls],
                ]
                out.append({"role": "assistant", "content": content})
            else:
                block = {"type": "tool_result", "tool_use_id": m.tool_call_id, "content": m.text or ""}
                last = out[-1] if out else None
                if last and last["role"] == "user" and all(b["type"] == "tool_result" for b in last["content"]):
                    last["content"].append(block)
                else:
                    out.append({"role": "user", "content": [block]})
        body: dict[str, Any] = {"model": model, "max_tokens": max_tokens, "system": system, "messages": out}
        if tools:
            body["tools"] = [{"name": t.name, "description": t.description, "input_schema": t.parameters} for t in tools]
        return body

    @staticmethod
    def parse(data: dict[str, Any]) -> LlmResponse:
        content = data.get("content") or []
        texts = [b.get("text", "") for b in content if b.get("type") == "text"]
        calls = [ToolCall(b["id"], b["name"], _args(b.get("input"))) for b in content if b.get("type") == "tool_use"]
        return LlmResponse(text="\n".join(texts) if texts else None, tool_calls=calls, raw=content)

    def headers(self) -> dict[str, str]:
        h = {"x-api-key": self.api_key, "anthropic-version": "2023-06-01"}
        if self.workspace_id:
            h["anthropic-workspace-id"] = self.workspace_id
        return h

    async def complete(self, system: str, messages: list[Message], tools: list[ToolSpec]) -> LlmResponse:
        data = await _post(
            self.client,
            "https://api.anthropic.com/v1/messages",
            self.headers(),
            self.build_body(self.model, self.max_tokens, system, messages, tools),
        )
        return self.parse(data)


# ---------------- Gemini (generateContent) ----------------


class GeminiProvider:
    def __init__(self, api_key: str, model: str, client: httpx.AsyncClient | None = None):
        self.api_key, self.model = api_key, model
        self.client = client or httpx.AsyncClient()

    @staticmethod
    def build_body(system: str, messages: list[Message], tools: list[ToolSpec]) -> dict[str, Any]:
        contents: list[dict[str, Any]] = []
        for m in messages:
            if m.role == "user":
                part = {"text": m.text or ""}
                if contents and contents[-1]["role"] == "user":
                    contents[-1]["parts"].append(part)
                else:
                    contents.append({"role": "user", "parts": [part]})
            elif m.role == "assistant":
                parts = m.raw if isinstance(m.raw, list) else [
                    *([{"text": m.text}] if m.text else []),
                    *[{"functionCall": {"name": c.name, "args": c.arguments}} for c in m.tool_calls],
                ]
                contents.append({"role": "model", "parts": parts})
            else:
                part = {"functionResponse": {"name": m.tool_name, "response": {"result": m.text or ""}}}
                last = contents[-1] if contents else None
                if last and last["role"] == "user" and all("functionResponse" in p for p in last["parts"]):
                    last["parts"].append(part)
                else:
                    contents.append({"role": "user", "parts": [part]})
        body: dict[str, Any] = {"systemInstruction": {"parts": [{"text": system}]}, "contents": contents}
        if tools:
            body["tools"] = [
                {"functionDeclarations": [{"name": t.name, "description": t.description, "parameters": t.parameters} for t in tools]}
            ]
        return body

    @staticmethod
    def parse(data: dict[str, Any]) -> LlmResponse:
        cands = data.get("candidates") or []
        if not cands:
            raise LlmError(f"Gemini 응답이 비어 있습니다 ({(data.get('promptFeedback') or {}).get('blockReason')})")
        parts = (cands[0].get("content") or {}).get("parts") or []
        texts, calls = [], []
        for i, p in enumerate(parts):
            if p.get("thought"):
                continue
            if isinstance(p.get("text"), str):
                texts.append(p["text"])
            fc = p.get("functionCall")
            if fc:
                calls.append(ToolCall(fc.get("id") or f"gemini_{time.time_ns()}_{i}", fc["name"], _args(fc.get("args"))))
        return LlmResponse(text="\n".join(texts) if texts else None, tool_calls=calls, raw=parts)

    async def complete(self, system: str, messages: list[Message], tools: list[ToolSpec]) -> LlmResponse:
        data = await _post(
            self.client,
            f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent",
            {"x-goog-api-key": self.api_key},
            self.build_body(system, messages, tools),
        )
        return self.parse(data)


DEFAULT_MODELS = {"anthropic": "claude-sonnet-5", "openai": "gpt-4.1", "gemini": "gemini-3.6-flash"}


def create_provider(
    provider: str,
    model: str,
    *,
    anthropic_key: str,
    openai_key: str,
    gemini_key: str,
    anthropic_workspace_id: str = "",
) -> LlmProvider:
    model = model or DEFAULT_MODELS.get(provider, "")
    if provider == "anthropic":
        return AnthropicProvider(anthropic_key, model, workspace_id=anthropic_workspace_id)
    if provider == "openai":
        return OpenAiProvider(openai_key, model)
    if provider == "gemini":
        return GeminiProvider(gemini_key, model)
    raise ValueError(f"알 수 없는 LLM_PROVIDER: {provider}")


async def complete_with_retry(llm: LlmProvider, system: str, messages: list[Message], tools: list[ToolSpec]) -> LlmResponse:
    delay = 2.0
    for attempt in range(4):
        try:
            return await llm.complete(system, messages, tools)
        except LlmError as e:
            if attempt == 3 or not (e.status == 429 or (e.status or 0) >= 500):
                raise
        except httpx.TimeoutException:
            if attempt == 3:
                raise
        await asyncio.sleep(delay)
        delay *= 2
    raise AssertionError("unreachable")
