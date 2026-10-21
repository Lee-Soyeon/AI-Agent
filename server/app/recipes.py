"""레시피 카탈로그 (tasks.json). 앱과 서버가 같은 파일을 쓴다.

레시피 = 홈 갤러리의 카드 하나. steps(최대 3개)를 거쳐 prompt_template 이 채워지면 에이전트에 넘긴다.
"""

from __future__ import annotations

import json
import re
from functools import lru_cache
from pathlib import Path
from typing import Any

_PATH = Path(__file__).parent / "tasks.json"
STEP_KINDS = ("file", "photo", "text", "chips", "keyword")
INPUT_PLACEHOLDERS = ("file", "photo", "text")
MAX_STEPS = 3


class RecipeError(ValueError):
    pass


def check(data: dict[str, Any]) -> None:
    """카탈로그 불변식. 어기면 서버가 뜨지 않는다 (사람이 고치라는 뜻)."""
    ids: set[str] = set()
    for r in data.get("recipes", []):
        rid = r.get("id")
        if not rid or rid in ids:
            raise RecipeError(f"레시피 id 가 없거나 중복: {rid!r}")
        ids.add(rid)
        steps = r.get("steps", [])
        if len(steps) > MAX_STEPS:
            raise RecipeError(f"{rid}: 단계 {len(steps)}개 (최대 {MAX_STEPS})")
        step_ids = set()
        for s in steps:
            if s.get("kind") not in STEP_KINDS:
                raise RecipeError(f"{rid}: 단계 kind {s.get('kind')!r}")
            if s.get("kind") == "chips" and not (s.get("options") or s.get("options_from")):
                raise RecipeError(f"{rid}.{s.get('id')}: chips 에 options 또는 options_from 이 필요")
            if s.get("kind") == "chips" and s.get("options") and not 2 <= len(s["options"]) <= 6:
                raise RecipeError(f"{rid}.{s.get('id')}: 칩은 2~6개")
            step_ids.add(s.get("id"))
        for ph in re.findall(r"\{(\w+)\}", r.get("prompt_template", "")):
            if ph not in step_ids and ph not in INPUT_PLACEHOLDERS:
                raise RecipeError(f"{rid}: prompt_template 의 {{{ph}}} 에 해당하는 단계가 없음")
        if r.get("engine") not in ("llm", "browser", "gmail"):
            raise RecipeError(f"{rid}: engine {r.get('engine')!r}")
    for r in data.get("recipes", []):
        if r.get("next") and r["next"] not in ids:
            raise RecipeError(f"{r['id']}: next {r['next']!r} 가 없음")


@lru_cache(maxsize=1)
def data() -> dict[str, Any]:
    d = json.loads(_PATH.read_text(encoding="utf-8"))
    check(d)
    return d


def recipes() -> list[dict[str, Any]]:
    return data()["recipes"]


def find(recipe_id: str) -> dict[str, Any] | None:
    return next((r for r in recipes() if r["id"] == recipe_id), None)


def for_persona(persona: str | None) -> list[dict[str, Any]]:
    """페르소나 일치 우선, 나머지는 뒤에."""
    if not persona:
        return list(recipes())
    hit = [r for r in recipes() if persona in r.get("personas", [])]
    rest = [r for r in recipes() if persona not in r.get("personas", [])]
    return hit + rest


def intake_defaults(kind: str) -> list[str]:
    d = data().get("intake_defaults", {})
    return list(d.get(kind) or d.get("text") or ["요약", "고치기", "표로 만들기"])


def fill_prompt(recipe: dict[str, Any], answers: dict[str, str]) -> str:
    """단계 답으로 prompt_template 을 채운다. 없는 자리는 빈칸."""
    return re.sub(r"\{(\w+)\}", lambda m: answers.get(m.group(1), ""), recipe["prompt_template"]).strip()
