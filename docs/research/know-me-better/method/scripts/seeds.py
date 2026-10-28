"""Fetch landmark papers by DOI from Crossref and merge them into the candidate file (dedup by DOI/title).
Usage: python3 -I seeds.py <candidates_in> <candidates_out>"""
import json, sys, re, html, requests, time
SEEDS = [("T2","10.1037/0033-295X.84.3.231"),("T3","10.1145/2632048.2632054"),("T6","10.18653/v1/2024.acl-long.399"),
 ("T6","10.1609/aaai.v38i17.29946"),("T10","10.1145/3613904.3642385"),("T10","10.1145/2858036.2858494"),("T10","10.1080/1369118X.2016.1154086"),
 ("T10","10.1145/3555601"),("T9","10.1146/annurev.psych.57.102904.190127"),("T9","10.1016/j.jrp.2014.10.009"),("T9","10.1037/0003-066X.61.3.204"),
 ("T2","10.1146/annurev.psych.55.090902.141954"),("T2","10.1037/a0013314"),("T2","10.1111/j.1467-6494.1996.tb00512.x"),("T2","10.1037/a0021212"),
 ("T7","10.1111/j.0963-7214.2005.00355.x"),("T2","10.1016/j.jesp.2006.05.011"),("T3","10.1001/jama.2017.11295"),("T3","10.1038/npp.2015.207"),
 ("T3","10.2196/jmir.4273"),("T4","10.1371/journal.pone.0073791"),("T4","10.1037/pspp0000020"),("T4","10.1073/pnas.1802331115"),
 ("T4","10.1073/pnas.2405460121"),("T6","10.1016/j.ijhcs.2021.102601"),("T3","10.1145/1753326.1753409"),("T3","10.1145/2556288.2557039"),
 ("T1","10.1089/cyber.2017.0384"),("T10","10.1145/2395123.2395129"),("T1","10.1177/0956797616678187"),("T1","10.1177/0956797609360756"),
 ("T9","10.1037/0033-295X.102.2.246"),("T2","10.1111/j.1529-1006.2004.00018.x"),("T2","10.1037/0022-3514.77.6.1121"),("T1","10.1177/1088868318772990")]
MANUAL = [
 {"title":"Generative Agent Simulations of 1,000 People","authors":"Park, Zou, Shaw et al.","year":2024,"venue":"arXiv (Stanford HAI / Google DeepMind)","tier":"B","cites":None,
  "doi":"10.48550/arXiv.2411.10109","topics":["T5"],"sources":["manual"],
  "abstract":"We present a generative agent architecture that simulates the attitudes and behaviors of 1,052 real individuals by applying large language models to qualitative interviews about their lives, then measuring how well these agents replicate the attitudes and behaviors of the individuals that they represent. The generative agents replicate participants' responses on the General Social Survey 85% as accurately as participants replicate their own answers two weeks later, and perform comparably in predicting personality traits and outcomes in experimental replications. Our architecture reduces accuracy biases across racial and ideological groups compared to agents given demographic descriptions."},
 {"title":"Towards Understanding Sycophancy in Language Models","authors":"Sharma, Tong, Korbak et al.","year":2024,"venue":"International Conference on Learning Representations (ICLR)","tier":"A","cites":None,
  "doi":"10.48550/arXiv.2310.13548","topics":["T10"],"sources":["manual"],
  "abstract":"Human feedback is commonly utilized to finetune AI assistants. But human feedback may also encourage model responses that match user beliefs over truthful ones, a behaviour known as sycophancy. We investigate the prevalence of sycophancy in models whose finetuning procedure made use of human feedback... five state-of-the-art AI assistants consistently exhibit sycophancy across four varied free-form text-generation tasks... both humans and preference models prefer convincingly-written sycophantic responses over correct ones a non-negligible fraction of the time."},
]
def strip(t):
    t = html.unescape(re.sub(r"<[^>]+>", " ", t or "")); t = re.sub(r"^\s*(abstract)\s*", "", t, flags=re.I)
    return re.sub(r"\s+", " ", t).strip()
inp, out = sys.argv[1], sys.argv[2]
rs = [json.loads(l) for l in open(inp)]
norm = lambda t: re.sub(r"[^a-z0-9]+", " ", (t or "").lower()).strip()
have_doi = {(r.get("doi") or "").lower() for r in rs}; have_t = {norm(r["title"]) for r in rs}
new = []
for topic, doi in SEEDS:
    if doi.lower() in have_doi: continue
    for a in range(3):
        try:
            m = requests.get(f"https://api.crossref.org/works/{doi}", timeout=40).json()["message"]; break
        except Exception: time.sleep(3)
    else:
        print("fail", doi); continue
    t = strip((m.get("title") or [""])[0])
    if norm(t) in have_t: continue
    au = m.get("author") or []
    new.append({"title": t, "authors": ", ".join(a.get("family","") for a in au[:3]) + (" et al." if len(au) > 3 else ""),
                "year": (m.get("issued",{}).get("date-parts") or [[None]])[0][0], "venue": (m.get("container-title") or [""])[0],
                "tier": "A", "cites": m.get("is-referenced-by-count"), "doi": doi, "topics": [topic], "sources": ["Crossref-seed"],
                "abstract": strip(m.get("abstract"))[:1500]})
    print("added", doi, t[:70], "|", new[-1]["venue"][:40])
new += MANUAL
allr = new + rs
with open(out, "w") as f:
    for i, r in enumerate(allr, 1):
        r["pid"] = f"P{i:04d}"; r.setdefault("score", 99)
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
print("total", len(allr))
