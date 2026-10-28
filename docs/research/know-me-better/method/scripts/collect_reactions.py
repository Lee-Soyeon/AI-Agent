"""Collect public reactions to 'AI/algorithms knowing me' from HN, YouTube, Google Play, App Store, Lemmy.

Usage: python3 -I collect_reactions.py <raw_dir> <source>
source in: hn | yt | play | appstore | lemmy
Writes <raw_dir>/<source>.jsonl  (one candidate per line, already keyword-filtered).
"""
import json, os, re, sys, time, html, itertools
import requests

RAW, SRC = sys.argv[1], sys.argv[2]
S = requests.Session()
S.headers["User-Agent"] = "Mozilla/5.0 (research script)"

EN_KNOW = re.compile(
    r"\b(knows?|knew|knowing|understands?|understood|gets?|got)\s+(me|my|who i am)\b|know(s)? me better|"
    r"\bremember(s|ed|ing)?\b|\bmemor(y|ies)\b|\babout me\b|\bforg[eo]t\b|"
    r"\bmy (personality|preferences|habits|taste|interests|patterns|psychology|mind|values|life)\b|"
    r"\bcreep(y|ily|iness)\b|\bpersonali[sz]", re.I)
EN_AI = re.compile(
    r"\b(AI|A\.I\.|ChatGPT|GPT|GPT-?\d\w*|Claude|Gemini|LLMs?|models?|bots?|chatbots?|assistants?|algorithms?|Replika|"
    r"Pi|Spotify|TikTok|YouTube|Netflix|Google|Facebook|Instagram|Amazon|Copilot|Siri|Alexa|Character\.?ai|it)\b", re.I)
FIRST = re.compile(r"\b(I|I'm|I've|me|my|mine)\b")
KO_KNOW = re.compile(r"기억|나를|날\s?(너무|잘|정말|진짜)|나에\s?대해|나보다|내\s?(성격|취향|말투|상황|정보|이야기|얘기|패턴|마음|감정)|"
                     r"소름|섬뜩|무섭|맞춤|개인화|알아주|알아가|알아봐|이해해\s?주|까먹|잊어|잊었|알고리즘|꿰뚫|정확히|맞혔|맞췄|맞춰|날\s?알|나를\s?알")

def clean(t):
    t = html.unescape(re.sub(r"<[^>]+>", " ", t or ""))
    return re.sub(r"\s+", " ", t).strip()

def write(rows):
    path = os.path.join(RAW, f"{SRC}.jsonl")
    seen, n = set(), 0
    with open(path, "w") as f:
        for r in rows:
            key = r["text"][:120]
            if key in seen:
                continue
            seen.add(key); n += 1
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"{SRC}: wrote {n}", flush=True)

def get(url, params=None, tries=4):
    for a in range(tries):
        try:
            r = S.get(url, params=params, timeout=40)
            if r.status_code == 200:
                return r
        except Exception:
            pass
        time.sleep(2 ** (a + 1))
    return None

# ---------------- Hacker News ----------------
HN_Q = ["knows me better than I know myself", "knows me better than myself", "know me better than I do",
        "ChatGPT memory", "ChatGPT remembers", "memory feature ChatGPT", "Claude memory", "LLM memory personal",
        "AI remembers everything about me", "AI knows me", "ChatGPT knows me", "it knows me", "algorithm knows me",
        "TikTok algorithm knows", "Spotify knows me", "YouTube algorithm knows me", "creepy personalization",
        "creepy recommendations", "digital twin of myself", "AI therapist", "Replika", "personal AI assistant memory",
        "tell me about myself ChatGPT", "what ChatGPT knows about you", "roast me ChatGPT memory", "Rewind AI",
        "Limitless pendant", "lifelogging AI", "AI companion", "sycophantic ChatGPT", "Netflix recommendations know",
        "ads know me", "Facebook knows me", "Google knows more about me", "AI psychologist personality"]

def hn():
    rows = []
    for q in HN_Q:
        for page in range(4):
            r = get("https://hn.algolia.com/api/v1/search", {"query": q, "tags": "comment", "hitsPerPage": 100, "page": page})
            if not r:
                break
            hits = r.json().get("hits", [])
            for h in hits:
                t = clean(h.get("comment_text"))
                if not (60 <= len(t) <= 2500):
                    continue
                if EN_KNOW.search(t) and EN_AI.search(t) and FIRST.search(t):
                    rows.append({"source": "HackerNews", "lang": "en", "query": q, "date": (h.get("created_at") or "")[:10],
                                 "url": f"https://news.ycombinator.com/item?id={h.get('objectID')}",
                                 "context": h.get("story_title") or "", "text": t})
            if len(hits) < 100:
                break
            time.sleep(0.3)
        print("hn", q, len(rows), flush=True)
    write(rows)

# ---------------- YouTube ----------------
YT_Q = [("ko", "AI가 나보다 나를 더 잘 안다"), ("ko", "챗GPT 메모리 기능"), ("ko", "챗GPT에게 나에 대해 물어봤다"),
        ("ko", "GPT 나에 대해 아는 것 말해줘"), ("ko", "알고리즘이 나를 너무 잘 안다"), ("ko", "AI 상담 위로 챗GPT 울었다"),
        ("ko", "유발 하라리 알고리즘 나보다 나를"), ("ko", "챗GPT 성격 분석 소름"), ("ko", "AI 디지털 트윈 나"),
        ("en", "ChatGPT memory knows me"), ("en", "asked ChatGPT what it knows about me"), ("en", "ChatGPT tell me something about myself"),
        ("en", "algorithms know you better than you know yourself Harari"), ("en", "AI knows you better than you know yourself"),
        ("en", "ChatGPT roast me based on memory"), ("en", "Replika remembers me"), ("en", "AI therapist ChatGPT changed my life"),
        ("en", "TikTok algorithm knows me too well"), ("ko", "챗GPT 나를 분석해줘 소름"), ("ko", "챗GPT가 나를 기억한다"),
        ("ko", "AI 연애상담 챗GPT 위로"), ("ko", "인공지능이 나를 안다 알고리즘 무섭다"), ("en", "ChatGPT memory feature creepy"),
        ("en", "I asked ChatGPT to psychoanalyze me"), ("en", "AI companion remembers everything")]

def yt_search(q, lang):
    r = get("https://www.youtube.com/results", {"search_query": q, "hl": lang})
    if not r:
        return []
    ids = []
    for m in re.finditer(r'"videoId":"([\w-]{11})"', r.text):
        if m.group(1) not in ids:
            ids.append(m.group(1))
    title = {}
    for m in re.finditer(r'"videoId":"([\w-]{11})".{0,600}?"title":\{"runs":\[\{"text":"(.*?)"\}', r.text):
        title.setdefault(m.group(1), m.group(2))
    return [(i, title.get(i, "")) for i in ids[:10]]

YT_API = "https://www.youtube.com/youtubei/v1/next?prettyPrint=false"

def yt_comments(vid, lang, limit=400):
    import urllib.parse
    ctx = {"client": {"clientName": "WEB", "clientVersion": "2.20251020.00.00", "hl": lang, "gl": "KR" if lang == "ko" else "US"}}
    try:
        d = S.post(YT_API, json={"context": ctx, "videoId": vid}, timeout=30).json()
    except Exception:
        return
    s = json.dumps(d)
    m = re.search(r'"token": "([^"]+)", "request": "CONTINUATION_REQUEST_TYPE_WATCH_NEXT"\}\}\}\}\], "trackingParams": "[^"]+", "header": \{"commentsHeaderRenderer"', s)
    if not m:
        return
    tok, n = urllib.parse.unquote(m.group(1)), 0
    while tok and n < limit:
        try:
            d = S.post(YT_API, json={"context": ctx, "continuation": tok}, timeout=30).json()
        except Exception:
            return
        muts = d.get("frameworkUpdates", {}).get("entityBatchUpdate", {}).get("mutations", [])
        for mu in muts:
            c = mu.get("payload", {}).get("commentEntityPayload")
            if c:
                n += 1
                yield {"text": c["properties"]["content"]["content"], "time": c["properties"].get("publishedTime", ""),
                       "cid": c["properties"].get("commentId", ""), "votes": c.get("toolbar", {}).get("likeCountNotliked", "")}
        tok = None
        for e in d.get("onResponseReceivedEndpoints", []):
            body = next((v for v in e.values() if isinstance(v, dict) and "continuationItems" in v), {})
            items = body.get("continuationItems", [])
            if items and "continuationItemRenderer" in items[-1]:
                cir = items[-1]["continuationItemRenderer"]
                cmd = cir.get("continuationEndpoint") or cir.get("button", {}).get("buttonRenderer", {}).get("command", {})
                tok = cmd.get("continuationCommand", {}).get("token")
        time.sleep(0.3)

def yt():
    rows, done = [], set()
    for lang, q in YT_Q:
        vids = yt_search(q, lang)
        for vid, title in vids:
            if vid in done:
                continue
            done.add(vid)
            n = 0
            for c in yt_comments(vid, lang):
                t = clean(c.get("text"))
                if len(t) < 25 or len(t) > 2000:
                    continue
                ok = KO_KNOW.search(t) if lang == "ko" else (EN_KNOW.search(t) and FIRST.search(t))
                if ok:
                    rows.append({"source": "YouTube", "lang": lang, "query": q, "date": c.get("time", ""),
                                 "url": f"https://www.youtube.com/watch?v={vid}&lc={c.get('cid')}",
                                 "context": clean(title), "text": t, "likes": c.get("votes")})
                    n += 1
            print("yt", lang, q, vid, n, flush=True)
    write(rows)

# ---------------- Google Play ----------------
PLAY = [("com.openai.chatgpt", "ChatGPT"), ("com.google.android.apps.bard", "Gemini"), ("com.anthropic.claude", "Claude"),
        ("ai.replika.app", "Replika"), ("ai.character.app", "Character.AI"), ("ai.inflection.pi", "Pi"),
        ("com.wrtn.app", "뤼튼"), ("com.scatterlab.messenger", "제타")]
EN_REV = re.compile(r"remember|memory|memories|forg[eo]t|knows? me|know me|understands? me|gets me|about me|"
                    r"my (personality|life|preferences|feelings)|personali[sz]|creepy|like a friend|knows? (everything|so much)", re.I)

def play():
    from google_play_scraper import reviews, Sort
    rows = []
    for aid, name in PLAY:
        for lang, country in [("ko", "kr"), ("en", "us")]:
            for sort, cap in [(Sort.MOST_RELEVANT, 1500), (Sort.NEWEST, 6000)]:
                tok, got, n = None, 0, 0
                while got < cap:
                    try:
                        res, tok = reviews(aid, lang=lang, country=country, sort=sort, count=200, continuation_token=tok)
                    except Exception as e:
                        print("play err", aid, e, flush=True); break
                    if not res:
                        break
                    got += len(res)
                    for x in res:
                        t = clean(x.get("content"))
                        if len(t) < 25:
                            continue
                        ok = KO_KNOW.search(t) if lang == "ko" else EN_REV.search(t)
                        if ok:
                            rows.append({"source": f"GooglePlay:{name}", "lang": lang, "query": "", "date": str(x.get("at"))[:10],
                                         "url": f"https://play.google.com/store/apps/details?id={aid}&reviewId={x.get('reviewId')}",
                                         "context": f"{name} 앱 리뷰 (별점 {x.get('score')})", "text": t, "rating": x.get("score"),
                                         "likes": x.get("thumbsUpCount")})
                            n += 1
                    if tok is None or getattr(tok, "token", None) is None:
                        break
                print("play", name, lang, sort, got, n, flush=True)
    write(rows)

# ---------------- App Store ----------------
IOS = [("6448311069", "ChatGPT"), ("6473753684", "Claude"), ("6477489729", "Gemini"), ("1158555867", "Replika"),
       ("1671705818", "Character.AI"), ("6445815935", "Pi")]

def appstore():
    rows = []
    for aid, name in IOS:
        for country, lang in [("kr", "ko"), ("us", "en")]:
            n = 0
            for sort in ["mostrecent", "mosthelpful"]:
                for page in range(1, 11):
                    r = get(f"https://itunes.apple.com/{country}/rss/customerreviews/page={page}/id={aid}/sortby={sort}/json")
                    if not r:
                        break
                    try:
                        entries = r.json()["feed"].get("entry", [])
                    except Exception:
                        break
                    if isinstance(entries, dict):
                        entries = [entries]
                    if not entries:
                        break
                    for e in entries:
                        if "im:rating" not in e:
                            continue
                        t = clean((e.get("title", {}).get("label", "") + ". " + e.get("content", {}).get("label", "")))
                        ok = KO_KNOW.search(t) if lang == "ko" else EN_REV.search(t)
                        if ok and len(t) >= 25:
                            rows.append({"source": f"AppStore:{name}", "lang": lang, "query": "", "date": e.get("updated", {}).get("label", "")[:10],
                                         "url": f"https://apps.apple.com/{country}/app/id{aid}?see-all=reviews#{e.get('id', {}).get('label', '')}",
                                         "context": f"{name} 앱 리뷰 (별점 {e['im:rating']['label']})", "text": t,
                                         "rating": int(e["im:rating"]["label"])})
                            n += 1
            print("appstore", name, country, n, flush=True)
    write(rows)

# ---------------- Lemmy ----------------
LEMMY_Q = ["ChatGPT memory", "knows me better", "algorithm knows me", "AI remembers", "creepy recommendations", "AI companion", "Replika"]

def lemmy():
    rows = []
    for q in LEMMY_Q:
        for page in range(1, 4):
            r = get("https://lemmy.world/api/v3/search", {"q": q, "type_": "Comments", "limit": 50, "page": page, "sort": "TopAll"})
            if not r:
                break
            cs = r.json().get("comments", [])
            for c in cs:
                t = clean(c["comment"]["content"])
                if 60 <= len(t) <= 2500 and EN_KNOW.search(t) and EN_AI.search(t) and FIRST.search(t):
                    rows.append({"source": "Lemmy", "lang": "en", "query": q, "date": c["comment"]["published"][:10],
                                 "url": c["comment"]["ap_id"], "context": c.get("post", {}).get("name", ""), "text": t})
            if len(cs) < 50:
                break
        print("lemmy", q, len(rows), flush=True)
    write(rows)

{"hn": hn, "yt": yt, "play": play, "appstore": appstore, "lemmy": lemmy}[SRC]()
