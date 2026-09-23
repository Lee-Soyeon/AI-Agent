"""결제·전송 같은 되돌릴 수 없는 버튼은 사용자가 승인한 경우에만 누를 수 있도록 코드에서 강제한다.

LLM 이 지시를 무시하거나 웹페이지 속 악성 지시(프롬프트 인젝션)에 속더라도 이 검사는 우회할 수 없다.
"""

from __future__ import annotations

import re
import time

SENSITIVE = re.compile(
    r"(결제\s*하기|결제\s*완료|\d[\d,]*\s*원\s*결제|주문\s*하기|주문\s*확정|구매\s*확정|"
    r"pay\s*now|place\s*(your\s*)?order|complete\s*purchase|confirm\s*(and\s*)?pay|"
    r"보내기|메일\s*전송|^\s*전송\s*$|\bsend\b|송금|이체|예약\s*확정|예매\s*하기|탈퇴|계정\s*삭제)",
    re.IGNORECASE,
)


class SafetyPolicy:
    def __init__(self, grant_ttl_seconds: float = 600):
        self.grant_ttl = grant_ttl_seconds
        self._grant_expires: float | None = None

    @staticmethod
    def is_sensitive(label: str) -> bool:
        return bool(SENSITIVE.search(label or ""))

    def grant(self) -> None:
        self._grant_expires = time.monotonic() + self.grant_ttl

    def revoke(self) -> None:
        self._grant_expires = None

    def consume(self) -> bool:
        """승인이 살아 있으면 1회 소진하고 True."""
        ok = self._grant_expires is not None and time.monotonic() < self._grant_expires
        self._grant_expires = None
        return ok
