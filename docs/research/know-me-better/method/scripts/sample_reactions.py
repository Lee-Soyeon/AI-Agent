"""Score reaction candidates for relevance and draw a quota sample for manual coding.

Usage: python3 -I sample_reactions.py <raw_dir> <out_jsonl>
"""
import json, os, re, sys, collections

RAW, OUT = sys.argv[1], sys.argv[2]
CORE_EN = [r"know(s)? me better", r"knows? (more |so much |a lot |everything |too much )?about me", r"\bknows? me\b", r"\bknew me\b",
           r"\bunderstands? me\b", r"\bgets? me\b", r"remember(s|ed)? (that i|my|me|everything|what i|who i)", r"memory feature",
           r"(chatgpt|claude|gemini|llm|ai|gpt|bot|model)('s)? memory", r"\bcreep(y|ily|iness)\b", r"my personality", r"about myself",
           r"psychoanaly", r"my (habits|patterns|preferences|taste|interests|psychology)", r"\bprofil(e|ing) (of )?(me|us|users)\b",
           r"digital twin", r"know(s)? what i (want|like|need|mean)", r"better than (i|my) (do|know|wife|husband|friends|partner|therapist)",
           r"forg[eo]t (me|my|who i|everything|what i)", r"\bsycophan", r"\bflatter", r"personali[sz]ed (to me|for me)", r"\bthe algorithm\b"]
WEAK_EN = [r"\bremembers?\b", r"\bmemor(y|ies)\b", r"\bpersonali[sz]", r"\btherap", r"\bfriend\b", r"\bprivacy\b", r"\brecommend"]
CORE_KO = [r"나보다\s?나를", r"나에\s?대해", r"나를\s?(너무|잘|정말|진짜|더)?\s?(알|파악|이해)", r"날\s?(너무|잘|정말)\s?알", r"(나|내)를?\s?기억",
           r"소름", r"내\s?성격", r"이해해\s?주", r"맞춤", r"아첨|맞장구", r"섬뜩", r"내\s?(취향|말투|상황|패턴|마음|감정|정보)", r"까먹|잊어|잊었|기억\s?못|기억력"]
WEAK_KO = [r"기억", r"분석", r"위로", r"알고리즘", r"무섭", r"친구", r"상담"]
CE = [re.compile(p, re.I) for p in CORE_EN]; WE = [re.compile(p, re.I) for p in WEAK_EN]
CK = [re.compile(p) for p in CORE_KO]; WK = [re.compile(p) for p in WEAK_KO]

def score(r):
    t = r["text"]
    core, weak = (CK, WK) if r["lang"] == "ko" else (CE, WE)
    s = 2 * sum(1 for p in core if p.search(t)) + sum(1 for p in weak if p.search(t))
    L = len(t)
    s += 0.5 if 80 <= L <= 900 else (-0.5 if L < 40 else 0)
    return s

def load(name):
    p = os.path.join(RAW, name)
    return [json.loads(l) for l in open(p)] if os.path.exists(p) else []

pool = {"hn": load("hn.jsonl"), "lemmy": load("lemmy.jsonl"), "yt": load("yt.jsonl"), "appstore": load("appstore.jsonl"),
        "play": load("play.jsonl"), "dc": load("dc.jsonl")}
for k, v in pool.items():
    for r in v:
        r["rscore"] = score(r)

def top(rows, n, min_score=1.5):
    rows = sorted([r for r in rows if r["rscore"] >= min_score], key=lambda r: -r["rscore"])
    return rows[:n]

GENERAL = {"ChatGPT", "Gemini", "Claude", "뤼튼"}
COMPANION = {"Replika", "Pi", "Character.AI", "제타"}
play_general = [r for r in pool["play"] if r["source"].split(":")[1] in GENERAL]
play_comp = [r for r in pool["play"] if r["source"].split(":")[1] in COMPANION]

picked = []
picked += top(pool["hn"], 850, 2.5)
picked += top(pool["lemmy"], 60, 2.5)
picked += top(pool["yt"], 200, 1)
picked += top(pool["appstore"], 50, 1)
# general assistants: split per app×lang so one app does not dominate
for app in GENERAL:
    for lang in ("ko", "en"):
        picked += top([r for r in play_general if r["source"].endswith(app) and r["lang"] == lang], 80, 2)
for app in COMPANION:
    for lang in ("ko", "en"):
        picked += top([r for r in play_comp if r["source"].endswith(app) and r["lang"] == lang], 40, 2)
picked += top(pool["dc"], 450, 2)

seen, out = set(), []
for r in picked:
    k = r["text"][:100]
    if k in seen:
        continue
    seen.add(k); out.append(r)
with open(OUT, "w") as f:
    for i, r in enumerate(out, 1):
        r["rid"] = f"R{i:04d}"
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
print("pool sizes:", {k: len(v) for k, v in pool.items()})
print("sampled:", len(out))
print(collections.Counter(r["source"].split(":")[0] + ":" + r["lang"] for r in out))
print(collections.Counter(r["source"] for r in out if r["source"].startswith("GooglePlay")))
