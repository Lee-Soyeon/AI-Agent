"""dcinside search snippets about AI knowing/remembering me. Usage: python3 -I collect_dc.py <raw_dir>"""
import re, html, json, sys, time, urllib.parse, requests, os
RAW = sys.argv[1]
S = requests.Session(); S.headers["User-Agent"] = "Mozilla/5.0"
QS = ["챗지피티 나에 대해", "지피티 나를 기억", "챗지피티 메모리", "지피티가 나를 너무 잘", "나보다 나를 잘 아는", "알고리즘이 나를",
      "챗지피티 소름", "지피티 성격 분석", "지피티 상담 위로", "제미나이 나에 대해", "클로드 기억", "AI가 나를", "챗gpt 나를 분석",
      "지피티 나에 대해 아는", "gpt 기억 기능", "지피티 아첨", "지피티 맞장구", "알고리즘 무섭다 나를"]
KO = re.compile(r"기억|나를|날\s?(너무|잘)|나에\s?대해|나보다|내\s?(성격|취향|말투|상황|정보|이야기|얘기|패턴|마음)|소름|섬뜩|무섭|맞춤|개인화|알아주|이해해|까먹|잊어|알고리즘|꿰뚫|정확|분석|아첨|맞장구|위로")
rows, seen = [], set()
for q in QS:
    for p in range(1, 6):
        url = f"https://search.dcinside.com/post/p/{p}/q/{urllib.parse.quote(q)}"
        try:
            s = S.get(url, timeout=30).text
        except Exception:
            break
        items = re.findall(r'<li>\s*<a href="(https://gall\.dcinside\.com[^"]+)"[^>]*>(.*?)</a>\s*<p class="link_dsc_txt">(.*?)</p>(.*?)</li>', s, re.S)
        if not items:
            break
        for u, t, d, rest in items:
            t = html.unescape(re.sub(r"<[^>]+>", "", t)).strip(); d = html.unescape(re.sub(r"<[^>]+>", "", d)).strip()
            d = re.sub(r"\s+", " ", d)
            date = (re.findall(r"\d{4}\.\d{2}\.\d{2}", rest) or [""])[0]
            txt = f"{t} — {d}"
            if u in seen or len(d) < 30 or not KO.search(txt):
                continue
            seen.add(u)
            rows.append({"source": "DCinside", "lang": "ko", "query": q, "date": date, "url": u, "context": t, "text": txt})
        time.sleep(0.6)
    print("dc", q, len(rows), flush=True)
with open(os.path.join(RAW, "dc.jsonl"), "w") as f:
    for r in rows: f.write(json.dumps(r, ensure_ascii=False) + "\n")
print("dc wrote", len(rows))
