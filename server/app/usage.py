"""LLM 호출 횟수 한도. 운영자 키(무료 등급)로 돌릴 때 하루·한 달 요청 수를 막는다.

토큰이 아니라 호출 수를 센다. 공급자마다 토큰 집계 방식이 달라 호출 수가 가장 단순하고 정직하다.
"""

from __future__ import annotations

import datetime as dt
import json
import logging
from pathlib import Path
from typing import Any

from .llm import LlmProvider, LlmResponse, Message, ToolSpec

log = logging.getLogger(__name__)

LIMIT_MESSAGE = "오늘은 여기까지예요. 내일 다시 열어 주세요."


class UsageLimitExceeded(Exception):
    pass


class UsageMeter:
    def __init__(self, path: Path, *, daily_limit: int = 0, monthly_limit: int = 0):
        self.path = path
        self.daily_limit = daily_limit
        self.monthly_limit = monthly_limit
        self.counts: dict[str, int] = {}
        self._load()

    def _load(self) -> None:
        try:
            if self.path.exists():
                raw = json.loads(self.path.read_text("utf-8"))
                self.counts = {k: int(v) for k, v in raw.get("counts", {}).items()}
        except Exception:  # noqa: BLE001
            log.exception("사용량 기록을 읽지 못했습니다: %s", self.path)
            self.counts = {}

    def _save(self) -> None:
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            # 지난달 이전 기록은 버린다
            keep = {k: v for k, v in self.counts.items() if k >= self._month_key(dt.date.today().replace(day=1) - dt.timedelta(days=1))}
            self.counts = keep
            self.path.write_text(json.dumps({"counts": keep}, ensure_ascii=False), "utf-8")
        except Exception:  # noqa: BLE001
            log.exception("사용량 기록을 저장하지 못했습니다")

    @staticmethod
    def _day_key(d: dt.date) -> str:
        return d.isoformat()

    @staticmethod
    def _month_key(d: dt.date) -> str:
        return d.strftime("%Y-%m")

    def today(self) -> int:
        return self.counts.get(self._day_key(dt.date.today()), 0)

    def this_month(self) -> int:
        return self.counts.get(self._month_key(dt.date.today()), 0)

    def exceeded(self) -> bool:
        if self.daily_limit and self.today() >= self.daily_limit:
            return True
        return bool(self.monthly_limit and self.this_month() >= self.monthly_limit)

    def record(self) -> None:
        today = dt.date.today()
        for key in (self._day_key(today), self._month_key(today)):
            self.counts[key] = self.counts.get(key, 0) + 1
        self._save()

    def to_json(self) -> dict[str, Any]:
        return {
            "today": self.today(),
            "daily_limit": self.daily_limit,
            "this_month": self.this_month(),
            "monthly_limit": self.monthly_limit,
            "exceeded": self.exceeded(),
        }


class MeteredLlm:
    """LlmProvider 를 감싸 호출마다 센다. 한도를 넘으면 호출하지 않는다."""

    def __init__(self, inner: LlmProvider, meter: UsageMeter):
        self.inner = inner
        self.meter = meter

    async def complete(self, system: str, messages: list[Message], tools: list[ToolSpec]) -> LlmResponse:
        if self.meter.exceeded():
            raise UsageLimitExceeded(LIMIT_MESSAGE)
        self.meter.record()
        return await self.inner.complete(system, messages, tools)
