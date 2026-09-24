"""실제 Chromium 으로 BrowserManager 를 검증한다 (브라우저가 없으면 건너뜀)."""

import asyncio
import os
import threading
import time
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

from app.browser import BrowserManager, Screencast

CHROMIUM = os.getenv("CHROMIUM_PATH") or "/opt/pw-browsers/chromium"

PAGE = """<!doctype html><meta charset=utf-8><title>테스트</title>
<form onsubmit="document.title='submitted:'+document.getElementById('q').value;return false">
<input id=q placeholder="검색어"><button>검색</button></form>
<input type=password name=pw>
<a href="/other.html" target="_blank">새 탭 열기</a>
<div role=button aria-label="결제하기" onclick="document.title='paid'">$</div>
<div style="display:none"><button>숨김</button></div>
<input name=cardNo placeholder="카드번호 16자리"><input autocomplete=cc-csc aria-label="보안코드">"""


@pytest.fixture
def site(tmp_path: Path):
    (tmp_path / "index.html").write_text(PAGE, encoding="utf-8")
    (tmp_path / "other.html").write_text("<title>다른 탭</title><p>두번째", encoding="utf-8")
    (tmp_path / "order-complete.html").write_text(
        "<meta charset=utf-8><title>쿠팡</title><h2>주문이 완료되었습니다</h2><p>주문번호 123", encoding="utf-8"
    )
    server = ThreadingHTTPServer(("127.0.0.1", 0), partial(SimpleHTTPRequestHandler, directory=str(tmp_path)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{server.server_port}"
    server.shutdown()


@pytest.mark.skipif(not os.path.exists(CHROMIUM), reason="chromium 없음")
async def test_real_browser_end_to_end(site, tmp_path):
    b = BrowserManager(tmp_path / "profile", headless=True, chromium_path=CHROMIUM)
    await b.start()
    try:
        await b.navigate(f"{site}/index.html")
        snap = await b.snapshot()
        labels = {e["label"]: e["id"] for e in snap.data["elements"]}
        assert "숨김" not in labels
        assert snap.title == "테스트"
        assert "[" in snap.to_prompt()

        assert (await b.describe(labels["결제하기"]))["label"].startswith("결제하기")
        assert (await b.describe(labels["pw"]))["type"] == "password"
        assert (await b.describe(labels["카드번호 16자리"]))["paymentField"] is True
        assert (await b.describe(labels["보안코드"]))["paymentField"] is True
        assert (await b.describe(labels["검색어"]))["paymentField"] is False
        assert await b.payment_done() is False

        assert (await b.type_text(labels["검색어"], "생수", submit=True))["ok"]
        assert await b.page.title() == "submitted:생수"

        assert (await b.click(labels["결제하기"]))["ok"]
        assert await b.page.title() == "paid"
        assert (await b.screenshot() or b"")[:2] == b"\xff\xd8"

        # 실시간 화면: 프레임이 오고, 탭 좌표 입력이 전달된다
        frames = []

        async def send(msg):
            frames.append(msg)

        cast = Screencast(b, send)
        await cast.start()
        await b.user_input({"type": "scroll", "dy": 100})
        for _ in range(50):
            if frames:
                break
            await asyncio.sleep(0.1)
        await cast.stop()
        assert frames and frames[0]["type"] == "frame" and frames[0]["width"]

        # 새 탭을 따라간다
        await b.snapshot()
        snap = await b.snapshot()
        new_tab = next(e["id"] for e in snap.data["elements"] if e["label"] == "새 탭 열기")
        await b.click(new_tab)
        for _ in range(50):
            if b.page.url.endswith("/other.html"):
                break
            await asyncio.sleep(0.1)
        assert b.page.url.endswith("/other.html")

        await b.navigate(f"{site}/order-complete.html")
        assert await b.payment_done() is True

        # 만료일이 있는 로그인 쿠키("로그인 유지")는 프로필에 남아 재시작 후에도 유지된다.
        # (만료일 없는 세션 쿠키는 크롬 특성상 재시작하면 사라진다)
        await b.context.add_cookies(
            [{"name": "sid", "value": "1", "url": site, "expires": time.time() + 86400}]
        )
    finally:
        await b.stop()
    b2 = BrowserManager(tmp_path / "profile", headless=True, chromium_path=CHROMIUM)
    await b2.start()
    try:
        assert any(c["name"] == "sid" for c in await b2.context.cookies(site))
    finally:
        await b2.stop()
