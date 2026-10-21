"""show_ui 부품 검증 (ui_schema.json). 앱의 ui_renderer.dart 와 같은 규칙으로 검사한다.

LLM 이 보낸 화면 트리는 반드시 이 안의 부품 8종 중 하나여야 한다. 아니면 text_block 으로 떨어뜨린다.
"""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

_PATH = Path(__file__).parent / "ui_schema.json"


class UiSchemaError(ValueError):
    pass


@lru_cache(maxsize=1)
def schema() -> dict[str, Any]:
    return json.loads(_PATH.read_text(encoding="utf-8"))


def parts() -> dict[str, Any]:
    return schema()["parts"]


def limits() -> dict[str, int]:
    return schema()["limits"]


def is_interactive(tree: dict[str, Any]) -> bool:
    p = parts().get(str(tree.get("type", "")))
    return bool(p and p["interactive"])


def _str(v: Any, name: str, *, max_len: int | None = None) -> str:
    if not isinstance(v, str) or not v.strip():
        raise UiSchemaError(f"{name} 은(는) 비어 있지 않은 문자열이어야 합니다.")
    s = v.strip()
    return s[:max_len] if max_len else s


def _str_list(v: Any, name: str) -> list[str]:
    if not isinstance(v, list):
        raise UiSchemaError(f"{name} 은(는) 문자열 배열이어야 합니다.")
    out: list[str] = []
    for x in v:
        if isinstance(x, (str, int, float)) and str(x).strip():
            s = str(x).strip()
            if s not in out:
                out.append(s)
    return out


def validate(tree: Any) -> dict[str, Any]:
    """정규화된 트리를 돌려준다. 틀리면 UiSchemaError."""
    if not isinstance(tree, dict):
        raise UiSchemaError("화면은 객체여야 합니다.")
    kind = str(tree.get("type", ""))
    spec = parts().get(kind)
    if not spec:
        raise UiSchemaError(f"알 수 없는 부품: {kind!r}")
    for key in spec["required"]:
        if key not in tree:
            raise UiSchemaError(f"{kind} 에 {key} 가 없습니다.")
    lim = limits()
    text_max = lim["text_max_chars"]
    out: dict[str, Any] = {"type": kind}
    allowed = set(spec["required"]) | set(spec["optional"])

    if kind == "chips":
        out["question"] = _str(tree["question"], "question", max_len=200)
        opts = _str_list(tree["options"], "options")
        if not lim["chips_min"] <= len(opts) <= lim["chips_max"]:
            raise UiSchemaError(f"칩은 {lim['chips_min']}~{lim['chips_max']}개여야 합니다 (지금 {len(opts)}개).")
        out["options"] = opts
        out["allow_free"] = bool(tree.get("allow_free", True))
    elif kind == "keyword":
        out["question"] = _str(tree["question"], "question", max_len=200)
        if tree.get("options") is not None:
            opts = _str_list(tree["options"], "options")[: lim["chips_max"]]
            if opts:
                out["options"] = opts
        if tree.get("placeholder"):
            out["placeholder"] = _str(tree["placeholder"], "placeholder", max_len=80)
    elif kind == "file_button":
        out["question"] = _str(tree["question"], "question", max_len=200)
        out["label"] = _str(tree["label"], "label", max_len=40)
        accept = str(tree.get("accept", "file"))
        if accept not in ("file", "photo", "text"):
            raise UiSchemaError("accept 는 file | photo | text 중 하나입니다.")
        out["accept"] = accept
    elif kind == "confirm":
        out["sentence"] = _str(tree["sentence"], "sentence", max_len=text_max)
        if tree.get("title"):
            out["title"] = _str(tree["title"], "title", max_len=60)
    elif kind == "table":
        headers = _str_list(tree["headers"], "headers")
        if not headers:
            raise UiSchemaError("headers 가 비어 있습니다.")
        rows_in = tree["rows"]
        if not isinstance(rows_in, list):
            raise UiSchemaError("rows 는 배열이어야 합니다.")
        rows: list[list[str]] = []
        for r in rows_in[: lim["table_rows_max"]]:
            if not isinstance(r, list):
                raise UiSchemaError("rows 의 각 행은 배열이어야 합니다.")
            cells = ["" if c is None else str(c) for c in r]
            cells = (cells + [""] * len(headers))[: len(headers)]
            rows.append(cells)
        out["headers"], out["rows"] = headers, rows
        if len(rows_in) > lim["table_rows_max"]:
            out["truncated"] = len(rows_in) - lim["table_rows_max"]
    elif kind == "before_after":
        out["before"] = _str(tree["before"], "before", max_len=text_max)
        out["after"] = _str(tree["after"], "after", max_len=text_max)
    elif kind == "checklist":
        items = _str_list(tree["items"], "items")[: lim["checklist_items_max"]]
        if not items:
            raise UiSchemaError("items 가 비어 있습니다.")
        out["items"] = items
        done = tree.get("done")
        if isinstance(done, list):
            out["done"] = [bool(d) for d in done][: len(items)] + [False] * max(0, len(items) - len(done))
    elif kind == "text_block":
        out["text"] = _str(tree["text"], "text", max_len=text_max)

    # 공통 선택 항목
    for key in ("why", "caption"):
        if key in allowed and tree.get(key):
            out[key] = _str(tree[key], key, max_len=200)
    return out


def coerce(tree: Any) -> dict[str, Any]:
    """항상 유효한 트리를 돌려준다. 틀리면 내용을 text_block 으로."""
    try:
        return validate(tree)
    except UiSchemaError as e:
        text = tree if isinstance(tree, str) else json.dumps(tree, ensure_ascii=False, default=str)
        text = f"{text}".strip() or "(내용 없음)"
        return {"type": "text_block", "text": text[: limits()["text_max_chars"]], "caption": f"화면 부품 오류: {e}"}


def label(tree: dict[str, Any]) -> str:
    """로그에 쓸 짧은 설명."""
    kind = tree.get("type")
    if kind == "table":
        return f"표 {len(tree.get('rows', []))}행"
    if kind == "checklist":
        return f"체크리스트 {len(tree.get('items', []))}개"
    if kind == "before_after":
        return "전후 비교"
    if kind in ("chips", "keyword", "file_button"):
        return f"질문: {tree.get('question', '')}"
    if kind == "confirm":
        return "확인 요청"
    return "글"


def prompt_help() -> str:
    """시스템 프롬프트용 부품 설명."""
    lines = []
    for name, p in parts().items():
        fields = ", ".join(p["required"]) + (f" (+{', '.join(p['optional'])})" if p["optional"] else "")
        lines.append(f"- {name}: {fields} — {p['doc']}")
    return "\n".join(lines)
