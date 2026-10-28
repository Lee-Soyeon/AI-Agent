"""Merge coded batches with candidate metadata, select final 1000+1000, write CSVs and summary stats.

Usage: python3 -I merge.py <scratch_dir> <out_dir>
"""
import json, os, sys, glob, collections, csv, re

SC, OUT = sys.argv[1], sys.argv[2]
os.makedirs(os.path.join(OUT, "data"), exist_ok=True)

def jl(p):
    rows = []
    for line in open(p):
        line = line.strip()
        if line:
            rows.append(json.loads(line))
    return rows

DN = {"D1": "성격 특질", "D2": "가치·동기·목표", "D3": "정서 역학·정신건강", "D4": "습관·생활 리듬", "D5": "말과 행동의 차이",
      "D6": "자기예측 오류", "D7": "맹점·남이 보는 나", "D8": "상황별 if-then 패턴", "D9": "관계·사회적 역할", "D10": "삶의 서사·정체성",
      "D11": "시간에 따른 변화", "D12": "신체·생리 신호", "D13": "취향·소비 선호", "D14": "언어·소통 스타일", "D15": "인지·의사결정 스타일"}
RN = {"R1": "정확함에 감탄", "R2": "섬뜩함·감시 불안", "R3": "프라이버시·데이터 통제", "R4": "회의론·바넘 효과", "R5": "잘못된 기억·추론",
      "R6": "기억의 실용 가치", "R7": "정서적 위안·관계·의존", "R8": "아첨·맞장구", "R9": "알고리즘이 나를 만든다", "R10": "자기통찰",
      "R11": "기억 열람·편집·통제 요구", "R12": "기억·이해 부족"}

# ---------- papers ----------
cand = {r["pid"]: r for r in jl(os.path.join(SC, "papers_candidates2.jsonl"))}
codes = {}
for p in sorted(glob.glob(os.path.join(SC, "coded", "papers_b*.jsonl"))):
    for c in jl(p):
        codes[c["pid"]] = c
missing = [k for k in cand if k not in codes]
print("papers coded:", len(codes), "missing:", len(missing))
# hand-checked corrections for landmark papers, plus 2025-26 papers the bibliographic APIs had not indexed yet
ov = json.load(open(os.path.join(SC, "overrides.json")))
for pid, patch in ov["codes"].items():
    codes[pid].update(patch)
rel = [cand[k] | {"c": codes[k]} for k in cand if k in codes and codes[k].get("rel") == "Y"]
print("papers rel=Y:", len(rel), "rel=?:", sum(1 for c in codes.values() if c.get("rel") == "?"))
# candidates file is already ranked (seeds first, then score); keep top 1000 relevant
final_p = (ov["add"] + rel)[:1000]
with open(os.path.join(OUT, "data", "papers.csv"), "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["id", "title", "authors", "year", "venue", "authority_tier", "citations", "doi", "search_topics", "dims", "dim_names",
                "flags", "data_sources", "comparison", "finding_ko"])
    for i, r in enumerate(final_p, 1):
        c = r["c"]
        w.writerow([f"P{i:04d}", r["title"], r.get("authors", ""), r.get("year"), r.get("venue"), r.get("tier"), r.get("cites"),
                    r.get("doi"), ";".join(r.get("topics", [])), ";".join(c.get("dims", [])),
                    ";".join(DN.get(d, d) for d in c.get("dims", [])), ";".join(c.get("flags", [])), ";".join(c.get("data", [])),
                    c.get("cmp", ""), c.get("find", "")])

# ---------- reactions ----------
rc = {r["rid"]: r for r in jl(os.path.join(SC, "reactions_candidates.jsonl"))}
# YouTube comments that finished downloading after the first sample was drawn
if os.path.exists(os.path.join(SC, "reactions_candidates_yt.jsonl")):
    rc.update({r["rid"]: r for r in jl(os.path.join(SC, "reactions_candidates_yt.jsonl"))})
rcodes = {}
for p in sorted(glob.glob(os.path.join(SC, "coded", "reactions_b*.jsonl"))):
    for c in jl(p):
        rcodes[c["rid"]] = c
print("reactions coded:", len(rcodes), "missing:", sum(1 for k in rc if k not in rcodes))
rrel = [rc[k] | {"c": rcodes[k]} for k in rc if k in rcodes and rcodes[k].get("rel") == "Y"]
print("reactions rel=Y:", len(rrel))
print("rel by source:", collections.Counter(r["source"].split(":")[0] + ":" + r["lang"] for r in rrel))
# final 1000: trim each platform by the same fraction, dropping its lowest-relevance items first
groups = collections.defaultdict(list)
for r in rrel:
    groups[r["source"].split(":")[0] + ":" + r["lang"]].append(r)
frac = min(1.0, 1000 / len(rrel))
final_r = []
for g, lst in sorted(groups.items(), key=lambda kv: -len(kv[1])):
    lst.sort(key=lambda r: -r.get("rscore", 0))
    final_r += lst[:max(1, round(len(lst) * frac))]
picked_ids = {r["rid"] for r in final_r}
final_r += sorted((r for r in rrel if r["rid"] not in picked_ids), key=lambda r: -r.get("rscore", 0))[:max(0, 1000 - len(final_r))]
final_r = sorted(final_r, key=lambda r: -r.get("rscore", 0))[:1000]
final_r.sort(key=lambda r: (r["source"], r["rid"]))
with open(os.path.join(OUT, "data", "reactions.csv"), "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["id", "source", "lang", "date", "url", "context", "text", "polarity", "codes", "code_names", "dims", "dim_names", "trigger_ko", "want_ko"])
    for i, r in enumerate(final_r, 1):
        c = r["c"]
        w.writerow([f"R{i:04d}", r["source"], r["lang"], r.get("date", ""), r["url"], r.get("context", ""), r["text"], c.get("pol", ""),
                    ";".join(c.get("codes", [])), ";".join(RN.get(x, x) for x in c.get("codes", [])), ";".join(c.get("dims", [])),
                    ";".join(DN.get(d, d) for d in c.get("dims", [])), c.get("trig", ""), c.get("want", "")])

# ---------- stats ----------
st = {}
P = [r["c"] for r in final_p]
st["papers_n"] = len(final_p)
st["papers_tier"] = collections.Counter(r.get("tier") for r in final_p)
st["papers_decade"] = collections.Counter((r.get("year") or 0) // 10 * 10 for r in final_p)
st["papers_dims"] = collections.Counter(d for c in P for d in c.get("dims", []))
st["papers_dims_primary"] = collections.Counter(c["dims"][0] for c in P if c.get("dims"))
st["papers_flags"] = collections.Counter(f for c in P for f in c.get("flags", []))
st["papers_data"] = collections.Counter(d for c in P for d in c.get("data", []))
st["papers_cmp"] = collections.Counter(c.get("cmp") for c in P)
st["papers_cmp_by_dim"] = {d: dict(collections.Counter(c.get("cmp") for c in P if d in c.get("dims", []) and c.get("cmp") != "none"))
                           for d in DN}
st["papers_topics"] = collections.Counter(t for r in final_p for t in r.get("topics", []))
st["papers_venues_top"] = collections.Counter(re.sub(r"Proceedings of the (\d+\w* )?(Annual |ACM |International )*", "", r.get("venue") or "")[:60]
                                              for r in final_p).most_common(30)
R = [r["c"] for r in final_r]
st["reactions_n"] = len(final_r)
st["reactions_source"] = collections.Counter(r["source"].split(":")[0] for r in final_r)
st["reactions_source_lang"] = collections.Counter(r["source"].split(":")[0] + ":" + r["lang"] for r in final_r)
st["reactions_app"] = collections.Counter(r["source"] for r in final_r if ":" in r["source"])
st["reactions_lang"] = collections.Counter(r["lang"] for r in final_r)
st["reactions_pol"] = collections.Counter(c.get("pol") for c in R)
st["reactions_codes"] = collections.Counter(x for c in R for x in c.get("codes", []))
st["reactions_codes_primary"] = collections.Counter(c["codes"][0] for c in R if c.get("codes"))
st["reactions_dims"] = collections.Counter(d for c in R for d in c.get("dims", []))
st["reactions_codes_by_lang"] = {lang: dict(collections.Counter(x for r in final_r if r["lang"] == lang for x in r["c"].get("codes", [])))
                                 for lang in ("ko", "en")}
st["reactions_pol_by_code"] = {k: dict(collections.Counter(r["c"].get("pol") for r in final_r if k in r["c"].get("codes", []))) for k in RN}
st["reactions_codes_by_type"] = {}
for name, pred in [("커뮤니티", lambda s: s in ("HackerNews", "Lemmy", "DCinside", "YouTube")),
                   ("범용 AI 앱 리뷰", lambda s: any(a in s for a in ("ChatGPT", "Gemini", "Claude", "뤼튼"))),
                   ("컴패니언 앱 리뷰", lambda s: any(a in s for a in ("Replika", "Pi", "Character.AI", "제타")))]:
    sub = [r for r in final_r if pred(r["source"])]
    st["reactions_codes_by_type"][name] = {"n": len(sub), **dict(collections.Counter(x for r in sub for x in r["c"].get("codes", [])))}
st["reactions_wants"] = collections.Counter(c.get("want") for c in R if c.get("want")).most_common(60)
st["reactions_trigs"] = collections.Counter(c.get("trig") for c in R if c.get("trig")).most_common(60)
st["reactions_code_dim"] = {k: dict(collections.Counter(d for c in R if k in c.get("codes", []) for d in c.get("dims", []))) for k in RN}
json.dump(st, open(os.path.join(SC, "stats.json"), "w"), ensure_ascii=False, indent=1, default=str)
print(json.dumps({k: v for k, v in st.items() if k in ("papers_n", "reactions_n", "papers_tier", "reactions_source_lang")}, ensure_ascii=False, default=str))
