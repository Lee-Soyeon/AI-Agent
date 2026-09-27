"""결제·전송·예약·게시 같은 되돌릴 수 없는 버튼은 사용자가 승인한 경우에만 누를 수 있도록 코드에서 강제한다.

LLM 이 지시를 무시하거나 웹페이지 속 악성 지시(프롬프트 인젝션)에 속더라도 이 검사는 우회할 수 없다.

승인은 "아무 버튼 1회"가 아니라 승인한 내용에 묶인다:
- 승인 종류와 버튼 동작이 맞아야 한다 (메일 전송 승인으로 결제 버튼을 누를 수 없음).
- 승인받은 사이트에서만 쓸 수 있다.
- 버튼에 금액이 적혀 있으면 그 금액이 승인 내용에 있어야 한다 (금액이 바뀌면 다시 승인).

앱(lib/agent/safety.dart)과 같은 규칙이다. 규칙을 바꾸면 양쪽을 함께 고치고
tests/sensitive_labels.json 에 사례를 추가한다 (앱·서버 테스트가 같은 표를 검사).
"""

from __future__ import annotations

import re
import time
from dataclasses import dataclass
from urllib.parse import urlparse

_I = re.IGNORECASE | re.MULTILINE  # 폼 버튼 문구는 버튼마다 한 줄

# (동작, 사람이 읽는 이름, 승인받을 때 쓸 kind, 패턴). 순서대로 검사한다:
# 취소·해지를 먼저 봐야 "주문 취소", "예약 취소" 가 주문/예약으로 분류되지 않는다.
ACTIONS: list[tuple[str, str, str, re.Pattern[str]]] = [
    ("terminate", "취소·해지·탈퇴", "terminate", re.compile(
        r"(탈퇴|계정\s*삭제|영구\s*삭제|(구독|멤버십|멤버쉽|정기\s*결제|자동\s*결제)\s*해지|해지\s*하기|"
        r"(주문|예약|예매|결제|구매)\s*취소|delete\s*(my\s*)?account|cancel\s*(my\s*)?subscription)", _I)),
    ("pay", "결제", "purchase", re.compile(
        r"(결제\s*하기|결제\s*완료|\d[\d,]*\s*원\s*결제|주문\s*하기|주문\s*확정|구매\s*확정|"
        r"pay\s*now|place\s*(your\s*)?order|complete\s*purchase|confirm\s*(and\s*)?pay|송금|이체)", _I)),
    ("book", "예약·예매 확정", "booking", re.compile(
        r"(예약\s*확정|예약\s*신청|예약\s*완료|동의하고\s*예약|예매\s*하기|"
        r"book\s*now|reserve\s*now|confirm\s*(booking|reservation))", _I)),
    ("submit", "지원·제출", "submit", re.compile(
        r"(지원\s*하기|지원서\s*제출|제출\s*하기|^\s*제출\s*$|apply\s*now|submit\s*application)", _I)),
    ("post", "글 게시", "post", re.compile(
        r"(게시\s*하기|^\s*게시\s*$|^\s*등록\s*$|^\s*올리기\s*$|"
        r"(글|댓글|답글|후기|리뷰|게시글|게시물)\s*(등록|올리기|작성\s*완료)|^\s*(post|tweet)\s*$)", _I)),
    ("send", "전송", "send_message", re.compile(r"(보내기|메일\s*전송|^\s*전송\s*$|\bsend\b)", _I)),
]
_ACTION_INFO = {a: (label, kind) for a, label, kind, _ in ACTIONS}

KIND_LABELS = {
    "purchase": "구매/결제",
    "send_email": "이메일 전송",
    "send_message": "메시지 전송",
    "booking": "예약/예매",
    "post": "글 게시",
    "submit": "지원/제출",
    "terminate": "취소/해지/탈퇴",
    "other": "기타 중요한 동작",
}

# 승인 종류별로 누를 수 있는 동작. 예약은 마지막 단계에서 결제 버튼이 나오는 경우가 많아 결제도 허용한다.
# "기타" 승인으로는 결제·전송을 할 수 없다.
ALLOWED: dict[str, set[str]] = {
    "purchase": {"pay"},
    "send_email": {"send"},
    "send_message": {"send"},
    "booking": {"book", "pay"},
    "post": {"post"},
    "submit": {"submit"},
    "terminate": {"terminate"},
    "other": {"book", "post", "submit", "terminate"},
}

_AMOUNT = re.compile(r"(\d[\d,]*)\s*원|[₩$]\s*(\d[\d,]*)")
_NUMBER = re.compile(r"\d[\d,]*")
_SECOND_LEVEL = {"co", "or", "go", "ne", "ac", "re", "pe", "com", "net", "org"}


def classify(label: str) -> str | None:
    for action, _, _, pattern in ACTIONS:
        if pattern.search(label or ""):
            return action
    return None


def amounts_in(label: str) -> set[str]:
    """버튼 문구 속 금액 (콤마 제거). 예: "32,900원 결제하기" → {"32900"}."""
    return {(m.group(1) or m.group(2)).replace(",", "") for m in _AMOUNT.finditer(label or "")}


def site_of(url: str | None) -> str | None:
    """주소의 사이트 단위 (m.coupang.com → coupang.com, m.11st.co.kr → 11st.co.kr)."""
    if not url:
        return None
    host = (urlparse(url).hostname or "").lower()
    if not host:
        return None
    parts = host.split(".")
    if len(parts) < 2:
        return host
    n = 3 if len(parts) >= 3 and len(parts[-1]) == 2 and parts[-2] in _SECOND_LEVEL else 2
    return ".".join(parts[-n:])


def _won(n: str) -> str:
    return f"{int(n):,}원"


@dataclass
class Grant:
    kind: str
    content: str
    site: str | None
    expires: float


class SafetyPolicy:
    def __init__(self, grant_ttl_seconds: float = 600):
        self.grant_ttl = grant_ttl_seconds
        self._grant: Grant | None = None

    @staticmethod
    def is_sensitive(label: str) -> bool:
        return classify(label) is not None

    def grant(self, kind: str, content: str, url: str | None = None) -> None:
        """content 는 사용자에게 보여준 승인 카드의 전체 내용, url 은 승인할 때의 페이지."""
        kind = kind if kind in ALLOWED else "other"
        self._grant = Grant(kind, content, site_of(url), time.monotonic() + self.grant_ttl)

    def revoke(self) -> None:
        self._grant = None

    def authorize(self, label: str, url: str | None = None) -> str | None:
        """민감한 버튼을 누르기 직전 호출. 누를 수 있으면 None, 막아야 하면 이유.
        민감한 버튼이면 결과와 관계없이 승인은 소진된다 (1회용)."""
        action = classify(label)
        if action is None:
            return None
        g, self._grant = self._grant, None
        name, kind = _ACTION_INFO[action]
        if g is None or time.monotonic() >= g.expires:
            return f"{name} 버튼입니다. 먼저 request_approval(kind: {kind}) 로 전체 내용을 보여주고 사용자 승인을 받으세요."
        if action not in ALLOWED[g.kind]:
            return (
                f'승인받은 것은 "{KIND_LABELS[g.kind]}"인데 이 버튼은 "{name}" 동작입니다. '
                f"request_approval(kind: {kind}) 로 다시 승인받으세요."
            )
        site = site_of(url)
        if g.site and site and g.site != site:
            return f"승인받은 사이트({g.site})와 지금 사이트({site})가 다릅니다. 이 사이트에서 다시 승인받으세요."
        approved = {m.group(0).replace(",", "") for m in _NUMBER.finditer(g.content)}
        changed = sorted(n for n in amounts_in(label) if n not in approved)
        if changed:
            return (
                f"버튼 금액({', '.join(_won(n) for n in changed)})이 승인받은 내용에 없습니다. "
                "금액이 바뀌었으면 바뀐 금액으로 다시 승인받으세요."
            )
        return None

    @staticmethod
    def allowed_labels(kind: str) -> str:
        return "·".join(_ACTION_INFO[a][0] for a, *_ in ACTIONS if a in ALLOWED.get(kind, ALLOWED["other"]))
