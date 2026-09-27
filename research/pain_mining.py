"""사람들이 '매일 귀찮다'고 말하는 반복 작업을 웹에서 모은다 (Playwright).

설문은 '원한다고 말하는 것'을, 불평 글은 '실제로 매일 짜증 나는 것'을 보여 준다.
네이버 블로그·카페·지식iN 검색과 커뮤니티 검색 결과에서 불평 문장을 모아
어떤 서비스·작업이 가장 자주 언급되는지 센다.

실행 (서버 가상환경에서):
    python research/pain_mining.py --pages 3 --out research/out
결과:
    out/snippets.csv   수집한 문장 (출처, 검색어, 제목, 본문 일부, 주소)
    out/ranking.csv    서비스·작업 키워드별 언급 수 (문장 수 기준, 중복 제거)

주의: 공개 검색 결과 페이지만 읽고, 로그인하지 않으며, 요청 사이에 쉬어 간다.
"""

from __future__ import annotations

import argparse
import asyncio
import csv
import os
import re
from collections import Counter
from pathlib import Path
from urllib.parse import quote

from playwright.async_api import async_playwright

# 불평·바람을 드러내는 표현. "무엇이" 귀찮은지는 문장 안의 키워드로 센다.
QUERIES = [
    "매일 귀찮", "맨날 귀찮", "매번 귀찮", "일일이 귀찮", "하나하나 귀찮",
    "맨날 까먹", "매번 까먹", "매일 들어가서 확인", "매일 확인하기 귀찮",
    "누가 대신 해줬으면", "자동으로 해주는 앱 없나", "알아서 해주는 앱",
    "매달 귀찮", "매주 귀찮", "번거로워서 안 함", "귀찮아서 포기",
]

# 검색 결과 페이지. {q} 에 검색어가 들어가고, {p} 는 페이지 번호.
SOURCES = {
    "naver_view": "https://search.naver.com/search.naver?where=view&query={q}&start={start}",
    "naver_kin": "https://search.naver.com/search.naver?where=kin&query={q}&start={start}",
    "ppomppu": "https://www.ppomppu.co.kr/search_bbs.php?keyword={q}&page={p}",
    "clien": "https://www.clien.net/service/search?q={q}&p={p0}",
    "theqoo": "https://theqoo.net/index.php?mid=square&search_target=title_content&search_keyword={q}&page={p}",
}

# 무엇이 귀찮은지: 서비스·작업 사전 (문장에 나오면 1회로 셈). 필요하면 늘린다.
TOPICS = {
    "출석체크·앱테크": r"출석\s*체크|출첵|앱테크|만보기|포인트\s*적립|클릭\s*적립|룰렛",
    "쿠폰·선착순": r"쿠폰|선착순|오픈런|타임\s*딜|특가\s*알림",
    "가계부·지출": r"가계부|지출|카드\s*값|고정\s*지출|구독료|정기\s*결제",
    "구독 해지": r"구독\s*해지|해지|자동\s*결제|정기\s*구독",
    "택배·배송": r"택배|배송\s*조회|송장|반품|교환",
    "장보기·재구매": r"장보기|생필품|재구매|휴지|생수|기저귀|분유",
    "가격 비교·최저가": r"최저가|가격\s*비교|가격\s*변동|가격\s*알림",
    "예약(병원·미용·식당)": r"병원\s*예약|미용실\s*예약|식당\s*예약|캐치테이블|네이버\s*예약|진료\s*예약",
    "공공시설·체육 예약": r"테니스장|수영장|캠핑장|공공\s*예약|체육관\s*예약|주민센터",
    "교통·기차표": r"기차표|ktx|srt|고속버스|항공권",
    "일정·약속": r"일정|약속|캘린더|스케줄|달력",
    "메일·알림 정리": r"메일|스팸|알림\s*정리|광고\s*문자",
    "카톡 답장·단톡": r"카톡|단톡|답장",
    "사진·파일 정리": r"사진\s*정리|갤러리|파일\s*정리|백업",
    "공과금·세금·연말정산": r"공과금|관리비|세금|연말\s*정산|고지서|납부",
    "보험·청구": r"보험\s*청구|실비|실손|병원비\s*청구",
    "학교·어린이집 알림장": r"알림장|가정\s*통신문|어린이집|학교\s*공지|학원",
    "비밀번호·로그인": r"비밀번호|로그인|인증서|본인\s*인증",
    "중고거래": r"당근|중고\s*거래|번개\s*장터",
    "청소·빨래·집안일": r"청소|빨래|설거지|분리\s*수거|집안일",
    "식단·요리": r"식단|메뉴|뭐\s*먹지|요리|레시피",
    "운동·건강 기록": r"운동\s*기록|식단\s*기록|약\s*먹|복약|병원\s*가",
}

TEXT_SELECTORS = [  # 검색 결과의 제목·요약에 해당하는 요소 (사이트 개편 시 수정)
    "a.title_link", "div.dsc_txt", "a.api_txt_lines", "div.api_txt_lines",
    "a.total_tit", "div.total_dsc", ".subject", ".title", "td.title", "span.list_title",
]


async def collect(pages: int, delay: float) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    seen: set[str] = set()
    async with async_playwright() as pw:
        # 서버와 같은 방식: CHROMIUM_PATH 가 있으면 그 크롬을 쓴다.
        browser = await pw.chromium.launch(executable_path=os.environ.get("CHROMIUM_PATH") or None)
        page = await browser.new_page(locale="ko-KR", viewport={"width": 412, "height": 915})
        for source, tmpl in SOURCES.items():
            for q in QUERIES:
                for p in range(1, pages + 1):
                    url = tmpl.format(q=quote(q), p=p, p0=p - 1, start=(p - 1) * 30 + 1)
                    try:
                        await page.goto(url, wait_until="domcontentloaded", timeout=20000)
                        texts = await page.eval_on_selector_all(
                            ", ".join(TEXT_SELECTORS),
                            "els => els.map(e => [e.innerText.trim(), e.href || ''])",
                        )
                    except Exception as e:  # noqa: BLE001 — 한 페이지 실패는 건너뛴다
                        print(f"skip {source} {q} p{p}: {e.__class__.__name__}")
                        continue
                    for text, href in texts:
                        text = re.sub(r"\s+", " ", text)[:300]
                        if len(text) < 8 or text in seen:
                            continue
                        seen.add(text)
                        rows.append({"source": source, "query": q, "text": text, "url": href})
                    await asyncio.sleep(delay)
        await browser.close()
    return rows


def rank(rows: list[dict[str, str]]) -> list[tuple[str, int, str]]:
    counts: Counter[str] = Counter()
    example: dict[str, str] = {}
    for r in rows:
        for topic, pattern in TOPICS.items():
            if re.search(pattern, r["text"], re.IGNORECASE):
                counts[topic] += 1
                example.setdefault(topic, r["text"])
    return [(t, n, example[t]) for t, n in counts.most_common()]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pages", type=int, default=3)
    ap.add_argument("--delay", type=float, default=1.5, help="요청 사이 쉬는 시간(초)")
    ap.add_argument("--out", default="research/out")
    args = ap.parse_args()

    rows = asyncio.run(collect(args.pages, args.delay))
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    with (out / "snippets.csv").open("w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=["source", "query", "text", "url"])
        w.writeheader()
        w.writerows(rows)
    ranking = rank(rows)
    with (out / "ranking.csv").open("w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(["topic", "mentions", "example"])
        w.writerows(ranking)
    print(f"문장 {len(rows)}개 수집")
    for topic, n, ex in ranking[:15]:
        print(f"{n:5d}  {topic:20s}  예) {ex[:60]}")


if __name__ == "__main__":
    main()
