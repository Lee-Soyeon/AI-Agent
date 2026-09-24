"""한국에서 많이 쓰는 서비스 카탈로그 (services.json). 앱과 서버가 같은 파일을 쓴다."""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any
from urllib.parse import quote

_PATH = Path(__file__).parent / "services.json"
SUPPORTED = ("web", "partial")


@lru_cache(maxsize=1)
def services() -> list[dict[str, Any]]:
    return json.loads(_PATH.read_text(encoding="utf-8"))["services"]


def supported() -> list[dict[str, Any]]:
    return [s for s in services() if s["web"] in SUPPORTED]


def _norm(s: str) -> str:
    return "".join(s.lower().split())


def find(query: str) -> list[dict[str, Any]]:
    q = _norm(query)
    if not q:
        return []
    exact = [s for s in services() if q in (_norm(s["id"]), _norm(s["name"]))]
    if exact:
        return exact
    return [s for s in services() if q in _norm(s["name"]) or q in _norm(s["id"]) or q in _norm(s["category"])][:5]


def search_url(service: dict[str, Any], keyword: str) -> str | None:
    t = service.get("search")
    return t.replace("{q}", quote(keyword)) if t else None


def describe(s: dict[str, Any]) -> str:
    lines = [f"### {s['name']} ({s['category']})"]
    if s["web"] in SUPPORTED:
        lines.append(f"- 시작: {s['home']}")
        if s.get("login"):
            lines.append(f"- 로그인: {s['login']}" + (f" ({s['account']} 계정 공유)" if s.get("account") else ""))
        if s.get("search"):
            lines.append(f"- 검색 URL: {s['search']}  ({{q}} 에 URL 인코딩한 검색어)")
        if s.get("hint"):
            lines.append(f"- 팁: {s['hint']}")
        if s["web"] == "partial":
            lines.append(f"- 제한: {s.get('note', '웹 기능 일부만 가능')}")
    else:
        lines.append(f"- 브라우저로는 지원하지 않음: {s.get('note', '앱 전용')}. 사용자에게 그렇게 알리세요.")
    return "\n".join(lines)


def prompt_index() -> str:
    """시스템 프롬프트용 짧은 목록 (이름만). 상세는 service_info 도구로."""
    web = ", ".join(s["name"] for s in supported())
    no = ", ".join(s["name"] for s in services() if s["web"] not in SUPPORTED)
    return f"- 브라우저로 지원: {web}\n- 지원 안 함(앱 전용·보안상 제외): {no}"
