"""서버에서 실제 크롬을 띄워 에이전트와 사용자(실시간 화면)가 함께 조작한다.

- 영구 프로필(user_data_dir)을 써서 한 번 로그인하면 서버를 재시작해도 로그인이 유지된다.
- 모바일 기기(Pixel 7) 에뮬레이션으로 휴대폰용 페이지를 받는다.
- 새 탭(target=_blank, window.open)이 열리면 자동으로 그 탭을 따라간다.
"""

from __future__ import annotations

import asyncio
import logging
from pathlib import Path
from typing import Any, Awaitable, Callable
from urllib.parse import urlparse

from playwright.async_api import BrowserContext, Page, Playwright, async_playwright

log = logging.getLogger(__name__)

_JS_DIR = Path(__file__).parent / "js"


def _js(name: str) -> str:
    return (_JS_DIR / f"{name}.js").read_text(encoding="utf-8")


SNAPSHOT_JS = _js("snapshot")
DESCRIBE_JS = _js("describe")
TYPE_TEXT_JS = _js("type_text")
SCROLL_JS = _js("scroll")


class BrowserError(Exception):
    pass


class PageSnapshot:
    def __init__(self, data: dict[str, Any]):
        self.data = data

    @property
    def url(self) -> str:
        return self.data.get("url", "")

    @property
    def title(self) -> str:
        return self.data.get("title", "")

    def to_prompt(self) -> str:
        lines = [
            f"URL: {self.url}",
            f"제목: {self.title}",
            f"스크롤: {self.data.get('scrollY')}/{self.data.get('scrollHeight')} "
            f"(화면 높이 {self.data.get('viewportHeight')})",
            "",
            "## 화면 텍스트",
            self.data.get("text", ""),
            "",
            "## 조작 가능한 요소 (click/type_text 에 id 사용)",
        ]
        for e in self.data.get("elements", []):
            s = f"[{e['id']}] {e['tag']}"
            if e.get("type"):
                s += f"({e['type']})"
            if e.get("role"):
                s += f" role={e['role']}"
            s += f' "{e.get("label", "")}"'
            if e.get("value"):
                s += f' value="{e["value"]}"'
            if "checked" in e:
                s += " [체크됨]" if e["checked"] else " [체크안됨]"
            if e.get("options"):
                s += f" options={e['options']}"
            if e.get("href"):
                s += f" href={e['href']}"
            if e.get("disabled"):
                s += " [비활성]"
            if e.get("offscreen"):
                s += " (화면 밖)"
            lines.append(s)
        return "\n".join(lines)


PageListener = Callable[[Page], Awaitable[None]]


class BrowserManager:
    def __init__(self, profile_dir: Path, *, headless: bool = True, chromium_path: str | None = None):
        self.profile_dir = profile_dir
        self.headless = headless
        self.chromium_path = chromium_path
        self._pw: Playwright | None = None
        self._context: BrowserContext | None = None
        self._page: Page | None = None
        self._lock = asyncio.Lock()
        self._page_listeners: list[PageListener] = []

    # ---------- 수명 ----------

    async def start(self) -> None:
        if self._context:
            return
        self.profile_dir.mkdir(parents=True, exist_ok=True)
        self._pw = await async_playwright().start()
        device = dict(self._pw.devices["Pixel 7"])
        device.pop("default_browser_type", None)
        self._context = await self._pw.chromium.launch_persistent_context(
            str(self.profile_dir),
            headless=self.headless,
            executable_path=self.chromium_path,
            locale="ko-KR",
            timezone_id="Asia/Seoul",
            args=["--disable-blink-features=AutomationControlled"],
            **device,
        )
        self._context.on("page", self._on_new_page)
        pages = self._context.pages
        self._page = pages[0] if pages else await self._context.new_page()

    async def stop(self) -> None:
        if self._context:
            await self._context.close()
        if self._pw:
            await self._pw.stop()
        self._context = self._pw = self._page = None

    @property
    def page(self) -> Page:
        if not self._page:
            raise BrowserError("브라우저가 시작되지 않았습니다.")
        return self._page

    @property
    def context(self) -> BrowserContext:
        if not self._context:
            raise BrowserError("브라우저가 시작되지 않았습니다.")
        return self._context

    def on_page_change(self, listener: PageListener) -> Callable[[], None]:
        self._page_listeners.append(listener)
        return lambda: self._page_listeners.remove(listener)

    async def _on_new_page(self, page: Page) -> None:
        # 새 탭을 따라간다 (결제창·로그인 팝업 등)
        self._page = page
        page.on("close", lambda _: asyncio.ensure_future(self._on_page_closed(page)))
        for listener in list(self._page_listeners):
            await listener(page)

    async def _on_page_closed(self, page: Page) -> None:
        if self._page is page and self._context:
            alive = [p for p in self._context.pages if not p.is_closed()]
            self._page = alive[-1] if alive else await self._context.new_page()
            for listener in list(self._page_listeners):
                await listener(self._page)

    # ---------- 에이전트 동작 ----------

    async def navigate(self, url: str) -> None:
        parsed = urlparse(url)
        if parsed.scheme not in ("http", "https"):
            raise BrowserError(f"http(s) URL 만 열 수 있습니다: {url}")
        async with self._lock:
            try:
                await self.page.goto(url, wait_until="domcontentloaded", timeout=30_000)
            except Exception as e:  # noqa: BLE001 - 타임아웃이어도 부분 로드된 페이지로 계속
                log.warning("navigate %s: %s", url, e)
            await self._settle()

    async def snapshot(self) -> PageSnapshot:
        try:
            data = await self.page.evaluate(SNAPSHOT_JS, {"maxText": 5000, "maxElements": 180})
        except Exception as e:  # noqa: BLE001
            raise BrowserError(f"페이지를 읽을 수 없습니다: {e}") from e
        return PageSnapshot(data)

    async def describe(self, element_id: int) -> dict[str, Any]:
        return await self.page.evaluate(DESCRIBE_JS, element_id)

    async def click(self, element_id: int) -> dict[str, Any]:
        async with self._lock:
            loc = self.page.locator(f'[data-agent-id="{element_id}"]').first
            if await loc.count() == 0:
                return {"ok": False, "error": "요소를 찾을 수 없습니다. read_page 로 새 id 를 확인하세요."}
            try:
                await loc.click(timeout=5_000)
            except Exception:  # noqa: BLE001 - 다른 요소에 가려진 경우 등
                await loc.dispatch_event("click")
            await self._settle()
            return {"ok": True}

    async def type_text(self, element_id: int, text: str, submit: bool = False) -> dict[str, Any]:
        async with self._lock:
            r = await self.page.evaluate(TYPE_TEXT_JS, {"id": element_id, "text": text, "submit": submit})
            await self._settle()
            return r

    async def scroll(self, direction: str) -> dict[str, Any]:
        r = await self.page.evaluate(SCROLL_JS, direction)
        await asyncio.sleep(0.6)
        return r

    async def go_back(self) -> None:
        async with self._lock:
            try:
                await self.page.go_back(wait_until="domcontentloaded", timeout=15_000)
            except Exception:  # noqa: BLE001
                pass
            await self._settle()

    async def screenshot(self) -> bytes | None:
        try:
            return await self.page.screenshot(type="jpeg", quality=60)
        except Exception:  # noqa: BLE001
            return None

    async def current_url(self) -> str:
        return self.page.url

    async def _settle(self) -> None:
        """동작 후 페이지 이동·동적 렌더링이 끝날 때까지 잠깐 기다린다."""
        try:
            await self.page.wait_for_load_state("domcontentloaded", timeout=10_000)
        except Exception:  # noqa: BLE001
            pass
        try:
            await self.page.wait_for_load_state("networkidle", timeout=3_000)
        except Exception:  # noqa: BLE001 - 계속 통신하는 페이지도 많다
            pass
        await asyncio.sleep(0.5)

    # ---------- 사용자 실시간 조작 (로그인·캡차·결제 비밀번호) ----------

    async def user_input(self, event: dict[str, Any]) -> None:
        """앱의 실시간 화면에서 온 입력. 좌표는 CSS 픽셀(뷰포트 기준)."""
        page = self.page
        kind = event.get("type")
        if kind == "tap":
            x, y = float(event["x"]), float(event["y"])
            try:
                await page.touchscreen.tap(x, y)
            except Exception:  # noqa: BLE001 - 터치 미지원 컨텍스트
                await page.mouse.click(x, y)
        elif kind == "type":
            await page.keyboard.type(str(event.get("text", "")), delay=30)
        elif kind == "key":
            key = str(event.get("key", ""))
            if key in {"Enter", "Backspace", "Tab", "Escape", "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"}:
                await page.keyboard.press(key)
        elif kind == "scroll":
            await page.mouse.wheel(0, float(event.get("dy", 0)))
        elif kind == "back":
            await self.go_back()
        elif kind == "navigate":
            await self.navigate(str(event.get("url", "")))


class Screencast:
    """CDP 스크린캐스트로 현재 탭 화면을 JPEG 프레임으로 흘려보낸다. 탭이 바뀌면 따라간다."""

    def __init__(self, browser: BrowserManager, send: Callable[[dict[str, Any]], Awaitable[None]]):
        self.browser = browser
        self.send = send
        self._cdp = None
        self._unsubscribe: Callable[[], None] | None = None

    async def start(self) -> None:
        self._unsubscribe = self.browser.on_page_change(self._attach)
        await self._attach(self.browser.page)

    async def stop(self) -> None:
        if self._unsubscribe:
            self._unsubscribe()
        await self._detach()

    async def _detach(self) -> None:
        if self._cdp:
            try:
                await self._cdp.send("Page.stopScreencast")
                await self._cdp.detach()
            except Exception:  # noqa: BLE001
                pass
            self._cdp = None

    async def _attach(self, page: Page) -> None:
        await self._detach()
        cdp = await self.browser.context.new_cdp_session(page)
        self._cdp = cdp

        async def on_frame(params: dict[str, Any]) -> None:
            try:
                await cdp.send("Page.screencastFrameAck", {"sessionId": params["sessionId"]})
            except Exception:  # noqa: BLE001
                return
            meta = params.get("metadata", {})
            await self.send(
                {
                    "type": "frame",
                    "data": params["data"],
                    # 앱이 탭 좌표를 CSS 픽셀로 바꿀 때 쓴다
                    "width": meta.get("deviceWidth"),
                    "height": meta.get("deviceHeight"),
                    "url": page.url,
                }
            )

        cdp.on("Page.screencastFrame", lambda p: asyncio.ensure_future(on_frame(p)))
        await cdp.send("Page.startScreencast", {"format": "jpeg", "quality": 55, "everyNthFrame": 1})
