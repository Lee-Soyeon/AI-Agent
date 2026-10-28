"""Merge raw Crossref/EPMC results, apply relevance + authority filters, rank, and write candidates.

Usage: python3 -I build_papers.py <raw_dir> <out_jsonl> [n]
"""
import json, os, re, sys, math, hashlib, html, collections

RAW, OUT = sys.argv[1], sys.argv[2]
N = int(sys.argv[3]) if len(sys.argv) > 3 else 1250
Q = json.load(open(os.path.join(RAW, "queries.json")))

TIER_A = [r"^(nature|science)$", r"^nature (human behaviou?r|communications|medicine|mental health|machine intelligence|computational science)$",
    r"^science advances$", r"proceedings of the national academy of sciences", r"^pnas nexus$",
    r"^psychological (review|bulletin|science|methods|assessment|medicine|inquiry)$", r"journal of personality and social psychology",
    r"perspectives on psychological science", r"annual review of (psychology|clinical psychology)", r"^american psychologist$",
    r"personality and social psychology (review|bulletin)", r"journal of research in personality", r"european journal of personality",
    r"^journal of personality$", r"^assessment$", r"^emotion$", r"clinical psychological science", r"current directions in psychological science",
    r"social psychological and personality science", r"journal of experimental psychology", r"trends in cognitive sciences",
    r"behavioral and brain sciences", r"journal of applied psychology", r"organizational behavior and human decision processes",
    r"journal of consumer research", r"^journal of marketing( research)?$", r"^management science$", r"advances in experimental social psychology",
    r"^cognition and emotion$", r"journal of abnormal psychology", r"journal of psychopathology and clinical science", r"^cognition$",
    r"chi conference on human factors", r"proceedings of the acm on human-computer interaction",
    r"interactive, mobile, wearable and ubiquitous technologies", r"pervasive and ubiquitous computing", r"user interface software and technology",
    r"intelligent user interfaces", r"designing interactive systems", r"computer[- ]supported cooperative work",
    r"acm transactions on computer-human interaction", r"international journal of human-computer studies", r"^human-computer interaction$",
    r"user modeling,? adaptation,? and personalization", r"user modeling and user-adapted interaction", r"conference on recommender systems",
    r"acm transactions on recommender systems", r"web conference", r"world wide web", r"knowledge discovery (and|&) data mining",
    r"\bsigir\b", r"web search and data mining", r"information and knowledge management", r"web and social media",
    r"acm transactions on information systems", r"association for computational linguistics", r"empirical methods in natural language processing",
    r"north american chapter", r"aaai conference on artificial intelligence", r"international joint conference on artificial intelligence",
    r"fairness, accountability,? and transparency", r"ieee transactions on affective computing", r"ieee transactions on pattern analysis",
    r"neural information processing", r"international conference on machine learning", r"learning representations",
    r"npj digital medicine", r"lancet digital health", r"^jama", r"^journal of medical internet research$", r"world psychiatry",
    r"american journal of psychiatry", r"lancet psychiatry", r"^the lancet$", r"^lancet$",
    r"journal of computer-mediated communication", r"new media (&|and) society", r"information,? communication (&|and) society",
    r"big data (&|and) society", r"mis quarterly", r"information systems research", r"journal of the association for information systems",
    r"journal of the academy of marketing science"]
TIER_A = [re.compile(p, re.I) for p in TIER_A]
JUNK = re.compile(r"^(correction|erratum|corrigendum|retraction|retracted|expression of concern|editorial|author response|reply to|response to|comment on|in this issue|front matter|back matter|table of contents)\b", re.I)

def norm_title(t):
    return re.sub(r"[^a-z0-9]+", " ", (t or "").lower()).strip()

def strip_tags(t):
    t = re.sub(r"<[^>]+>", " ", t or "")
    t = html.unescape(t)
    t = re.sub(r"^\s*(abstract|summary)\s*", "", t, flags=re.I)
    return re.sub(r"\s+", " ", t).strip()

def tier(venue):
    v = (venue or "").strip()
    return "A" if any(p.search(v) for p in TIER_A) else None

recs = {}
def add(rec, topic, qi):
    key = (rec["doi"] or "").lower() or norm_title(rec["title"])
    tkey = norm_title(rec["title"])
    if not tkey or len(tkey) < 15 or JUNK.search(rec["title"] or ""):
        return
    k = key if key in recs else (tkey if tkey in recs else None)
    if k is None:
        # also map by title to catch DOI-less duplicates
        for kk in (key, tkey):
            pass
        recs[key] = rec | {"topics": set(), "queries": set(), "sources": set()}
        recs[tkey] = recs[key]
        k = key
    r = recs[k]
    r["topics"].add(topic); r["queries"].add(qi); r["sources"].add(rec["src"])
    for f in ("abstract", "venue", "year", "doi", "authors"):
        if not r.get(f) and rec.get(f):
            r[f] = rec[f]
    r["cites"] = max(r.get("cites") or 0, rec.get("cites") or 0)

for qi, (topic, q, groups) in enumerate(Q):
    h = hashlib.md5(q.encode()).hexdigest()[:8]
    regs = [re.compile(g, re.I) for g in groups]
    items = []
    for it in json.load(open(os.path.join(RAW, f"crossref_{h}.json"))):
        y = (it.get("issued", {}).get("date-parts") or [[None]])[0][0]
        au = it.get("author") or []
        items.append({"src": "Crossref", "doi": it.get("DOI"), "title": strip_tags((it.get("title") or [""])[0]),
                      "venue": (it.get("container-title") or [""])[0], "year": y, "cites": it.get("is-referenced-by-count") or 0,
                      "abstract": strip_tags(it.get("abstract")), "type": it.get("type"),
                      "authors": ", ".join(f"{a.get('family','')}" for a in au[:3]) + (" et al." if len(au) > 3 else "")})
    for it in json.load(open(os.path.join(RAW, f"epmc_{h}.json"))):
        if it.get("source") in ("PPR",) and int(it.get("citedByCount") or 0) < 30:
            continue
        items.append({"src": "EuropePMC", "doi": it.get("doi"), "title": strip_tags(it.get("title")), "venue": it.get("journal") or "",
                      "year": int(it["pubYear"]) if (it.get("pubYear") or "").isdigit() else None, "cites": int(it.get("citedByCount") or 0),
                      "abstract": strip_tags(it.get("abstractText")), "type": "journal-article",
                      "authors": (it.get("authorString") or "")[:80]})
    for rec in items:
        text = f"{rec['title']} {rec['abstract']}"
        if all(r.search(text) for r in regs):
            # title must carry at least one group, otherwise relevance is too weak
            if any(r.search(rec["title"]) for r in regs):
                add(rec, topic, qi)

uniq = {id(v): v for v in recs.values()}.values()
cands = []
for r in uniq:
    t = tier(r.get("venue"))
    c = r.get("cites") or 0
    y = r.get("year") or 0
    if t == "A":
        pass
    elif c >= 30:
        t = "B"
    elif c >= 5 and y >= 2022:
        t = "C"
    else:
        continue
    score = {"A": 3.0, "B": 2.0, "C": 1.0}[t] + math.log10(c + 1) + 0.4 * (len(r["queries"]) - 1) + (0.5 if r.get("abstract") else 0)
    cands.append(r | {"tier": t, "score": round(score, 3)})

cands.sort(key=lambda r: -r["score"])
# keep topic balance: guarantee each topic its top 60 before global fill
picked, seen = [], set()
by_topic = collections.defaultdict(list)
for r in cands:
    for t in r["topics"]:
        by_topic[t].append(r)
for t, lst in by_topic.items():
    for r in lst[:60]:
        if id(r) not in seen:
            seen.add(id(r)); picked.append(r)
for r in cands:
    if len(picked) >= N:
        break
    if id(r) not in seen:
        seen.add(id(r)); picked.append(r)
picked.sort(key=lambda r: -r["score"])

with open(OUT, "w") as f:
    for i, r in enumerate(picked, 1):
        f.write(json.dumps({"pid": f"P{i:04d}", "title": r["title"], "authors": r.get("authors", ""), "year": r.get("year"),
                            "venue": r.get("venue"), "tier": r["tier"], "cites": r.get("cites"), "doi": r.get("doi"),
                            "topics": sorted(r["topics"]), "sources": sorted(r["sources"]), "score": r["score"],
                            "abstract": (r.get("abstract") or "")[:1500]}, ensure_ascii=False) + "\n")
print("candidates passing filters:", len(cands), "written:", len(picked))
print("tiers:", collections.Counter(r["tier"] for r in picked))
print("topics:", sorted(collections.Counter(t for r in picked for t in r["topics"]).items()))
print("with abstract:", sum(1 for r in picked if r.get("abstract")))
