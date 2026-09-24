"""작업(대화) 기록을 디스크에 저장한다. 서버를 재시작해도 목록에서 다시 열어 이어서 지시할 수 있다."""

from __future__ import annotations

import asyncio
import json
import logging
from pathlib import Path
from typing import Any

from .agent import Task

log = logging.getLogger(__name__)

SAVE_DELAY = 0.5  # 로그가 연달아 쌓일 때 한 번에 저장하도록 잠깐 모은다
BUSY = ("running", "waiting_approval", "waiting_user")


class TaskStore:
    def __init__(self, directory: Path):
        self.dir = directory
        self.dir.mkdir(parents=True, exist_ok=True)
        self._pending: dict[str, asyncio.TimerHandle] = {}
        self._shot_saved: dict[str, int] = {}

    def _json(self, task_id: str) -> Path:
        return self.dir / f"{task_id}.json"

    def _jpg(self, task_id: str) -> Path:
        return self.dir / f"{task_id}.jpg"

    def load_all(self) -> dict[str, Task]:
        """저장된 작업을 불러온다. 진행 중이던 작업은 서버가 꺼지며 멈췄으므로 '중단됨'으로 바꾼다."""
        tasks: dict[str, Task] = {}
        for path in self.dir.glob("*.json"):
            try:
                task = Task.from_record(json.loads(path.read_text("utf-8")))
            except Exception:  # noqa: BLE001
                log.exception("작업 기록을 읽지 못했습니다: %s", path)
                continue
            shot = self._jpg(task.id)
            if shot.exists():
                task.screenshot = shot.read_bytes()
                task.screenshot_version = 1
                self._shot_saved[task.id] = 1
            if task.status in BUSY:
                task.log("error", "서버가 재시작되어 작업이 중단되었습니다. 이어서 지시할 수 있습니다.")
                task.status = "failed"
                self.save(task)
            tasks[task.id] = task
        return tasks

    def watch(self, task: Task) -> None:
        """작업이 바뀔 때마다 (잠깐 모아서) 저장한다."""
        task.listeners.append(lambda: self.schedule(task))

    def schedule(self, task: Task) -> None:
        if task.id in self._pending:
            return
        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            self.save(task)
            return
        self._pending[task.id] = loop.call_later(SAVE_DELAY, self._flush_one, task)

    def _flush_one(self, task: Task) -> None:
        self._pending.pop(task.id, None)
        self.save(task)

    def save(self, task: Task) -> None:
        try:
            tmp = self._json(task.id).with_suffix(".tmp")
            tmp.write_text(json.dumps(task.to_record(), ensure_ascii=False, default=str), "utf-8")
            tmp.replace(self._json(task.id))
            if task.screenshot and self._shot_saved.get(task.id) != task.screenshot_version:
                self._jpg(task.id).write_bytes(task.screenshot)
                self._shot_saved[task.id] = task.screenshot_version
        except Exception:  # noqa: BLE001
            log.exception("작업 기록을 저장하지 못했습니다: %s", task.id)

    def flush(self, tasks: dict[str, Task]) -> None:
        for task_id, handle in list(self._pending.items()):
            handle.cancel()
            if task_id in tasks:
                self.save(tasks[task_id])
        self._pending.clear()

    def delete(self, task_id: str) -> None:
        handle = self._pending.pop(task_id, None)
        if handle:
            handle.cancel()
        self._shot_saved.pop(task_id, None)
        for p in (self._json(task_id), self._jpg(task_id)):
            p.unlink(missing_ok=True)

