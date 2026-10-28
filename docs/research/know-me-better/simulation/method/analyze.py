"""Analyse the simulated 2 x 3 experiment exactly as pre-registered (00-preregistration.md).

Usage: python3 -I analyze.py <sim_dir> <out_dir>
Writes <out_dir>/data/participants.csv and <sim_dir>/results.json, prints summary tables.
"""
import csv, glob, json, os, sys, collections
import numpy as np

D, OUT = sys.argv[1], sys.argv[2]
rng = np.random.default_rng(20261028)
B = 2000
DVS = ["PU_felt", "PU_know", "ACC", "TR", "CR", "SY", "DEL", "DI", "CU", "DD"]
CELLS = [("Flo", "A0"), ("Flo", "Aimp"), ("Flo", "Atr"), ("Fhi", "A0"), ("Fhi", "Aimp"), ("Fhi", "Atr")]


def jl(p):
    return [json.loads(l) for l in open(p) if l.strip()]


seeds = {s["sid"]: s for s in json.load(open(os.path.join(D, "seeds.json")))}
stim = {x["sid"]: x for x in jl(os.path.join(D, "stimuli.jsonl"))}
personas = {p["sid"]: p for f in glob.glob(os.path.join(D, "personas", "*.jsonl")) for p in jl(f)}
resp, batch_of = {}, {}
resp_map = json.load(open(os.path.join(D, "resp_map.json")))  # neutral batch name -> condition_half
for f in sorted(glob.glob(os.path.join(D, "responses", "r*.jsonl"))):
    name = resp_map[os.path.basename(f)[:-6]]
    for r in jl(f):
        resp[r["sid"]] = r
        batch_of[r["sid"]] = name
rid2sid = json.load(open(os.path.join(D, "coding_map.json")))
coded = {}
for f in glob.glob(os.path.join(D, "coded", "*.jsonl")):
    for c in jl(f):
        coded[rid2sid[c["rid"]]] = c

rows = []
for sid, x in stim.items():
    r, c, p = resp.get(sid), coded.get(sid), personas.get(sid)
    if not (r and c and p):
        continue
    row = {"sid": sid, "lang": x["lang"], "F": x["F"], "A": x["A"], "batch": batch_of[sid],
           "seed_codes": seeds[sid]["codes"], "seed_source": seeds[sid]["source"],
           **{k: int(r[k]) for k in ["PU_felt", "PU_know", "ACC", "TR", "CR", "SY", "DEL", "DI", "CU", "MC_F", "MC_A"]},
           "DD": int(c["DD"]), "pol": c["pol"], "codes": ";".join(c["codes"]),
           **{f"t_{k}": int(v) for k, v in p["traits"].items()},
           "next_msg": r["next_msg"], "feeling": r["feeling"], "ai_reply": x["ai_reply"], "profile": x["profile"]}
    rows.append(row)
print("analysable participants:", len(rows))
os.makedirs(os.path.join(OUT, "data"), exist_ok=True)
with open(os.path.join(OUT, "data", "participants.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader()
    w.writerows(rows)

arr = lambda key, sel=lambda r: True: np.array([r[key] for r in rows if sel(r)], dtype=float)
cell = lambda F, A: (lambda r: r["F"] == F and r["A"] == A)


def boot_mean(v):
    idx = rng.integers(0, len(v), (B, len(v)))
    m = v[idx].mean(1)
    return float(v.mean()), float(np.percentile(m, 2.5)), float(np.percentile(m, 97.5))


def d_ci(a, b):
    """Cohen's d (a - b) with bootstrap CI."""
    def d(x, y):
        s = np.sqrt(((len(x) - 1) * x.var(ddof=1) + (len(y) - 1) * y.var(ddof=1)) / (len(x) + len(y) - 2))
        return (x.mean() - y.mean()) / s if s > 0 else 0.0
    ds = [d(a[rng.integers(0, len(a), len(a))], b[rng.integers(0, len(b), len(b))]) for _ in range(B)]
    return float(d(a, b)), float(a.mean() - b.mean()), float(np.percentile(ds, 2.5)), float(np.percentile(ds, 97.5))


def did_ci(a1, b1, a2, b2):
    """Difference in mean differences (a1-b1) - (a2-b2) with bootstrap CI."""
    est = (a1.mean() - b1.mean()) - (a2.mean() - b2.mean())
    bs = []
    for _ in range(B):
        r = lambda v: v[rng.integers(0, len(v), len(v))]
        bs.append((r(a1).mean() - r(b1).mean()) - (r(a2).mean() - r(b2).mean()))
    return float(est), float(np.percentile(bs, 2.5)), float(np.percentile(bs, 97.5))


res = {"n": len(rows), "cells": {}, "ols": {}, "H": {}, "checks": {}}
for F, A in CELLS:
    res["cells"][f"{F}_{A}"] = {"n": int(sum(1 for r in rows if cell(F, A)(r))),
                                **{k: boot_mean(arr(k, cell(F, A))) for k in DVS + ["MC_F", "MC_A"]}}

# OLS with HC1 robust SEs: y ~ Fhi + Aimp + Atr + Fhi:Aimp + Fhi:Atr + lang_en
X = np.array([[1, r["F"] == "Fhi", r["A"] == "Aimp", r["A"] == "Atr", (r["F"] == "Fhi") * (r["A"] == "Aimp"),
               (r["F"] == "Fhi") * (r["A"] == "Atr"), r["lang"] == "en"] for r in rows], dtype=float)
names = ["const", "Fhi", "Aimp", "Atr", "Fhi:Aimp", "Fhi:Atr", "lang_en"]
XtXi = np.linalg.inv(X.T @ X)
for k in DVS:
    y = arr(k)
    b = XtXi @ X.T @ y
    e = y - X @ b
    V = XtXi @ (X.T * e ** 2) @ X @ XtXi * len(y) / (len(y) - X.shape[1])
    se = np.sqrt(np.diag(V))
    res["ols"][k] = {n: [round(float(bi), 3), round(float(si), 3)] for n, bi, si in zip(names, b, se)}

g = lambda k, F=None, A=None, extra=lambda r: True: arr(k, lambda r: (F is None or r["F"] == F) and (A is None or r["A"] in A) and extra(r))
know = ("Aimp", "Atr")
H = res["H"]
H["H1_PUfelt_F_in_A0"] = d_ci(g("PU_felt", "Fhi", ("A0",)), g("PU_felt", "Flo", ("A0",)))
H["H2_SY_F_in_A0"] = d_ci(g("SY", "Fhi", ("A0",)), g("SY", "Flo", ("A0",)))
for k in ["DEL", "TR", "CU"]:
    H[f"H3_{k}_Aknow_vs_A0"] = d_ci(g(k, A=know), g(k, A=("A0",)))
    H[f"H3_{k}_F_effect"] = d_ci(g(k, "Fhi"), g(k, "Flo"))
H["H4_CR_Aimp_vs_A0"] = d_ci(g("CR", A=("Aimp",)), g("CR", A=("A0",)))
H["H4_CR_Atr_vs_Aimp"] = d_ci(g("CR", A=("Atr",)), g("CR", A=("Aimp",)))
for k in ["DD", "DI"]:
    H[f"H5_{k}_F_effect"] = d_ci(g(k, "Fhi"), g(k, "Flo"))
    H[f"H5_{k}_F_effect_in_Atr_minus_in_A0"] = did_ci(g(k, "Fhi", ("Atr",)), g(k, "Flo", ("Atr",)), g(k, "Fhi", ("A0",)), g(k, "Flo", ("A0",)))
hi = lambda t: (lambda r: r[t] >= 4)
lo = lambda t: (lambda r: r[t] <= 3)
H["H6_privacy_CR_Aimp_vs_A0_high_minus_low"] = did_ci(g("CR", A=("Aimp",), extra=hi("t_privacy")), g("CR", A=("A0",), extra=hi("t_privacy")),
                                                    g("CR", A=("Aimp",), extra=lo("t_privacy")), g("CR", A=("A0",), extra=lo("t_privacy")))
H["H6_wantsmem_CU_Aknow_vs_A0_high_minus_low"] = did_ci(g("CU", A=know, extra=hi("t_wants_memory")), g("CU", A=("A0",), extra=hi("t_wants_memory")),
                                                       g("CU", A=know, extra=lo("t_wants_memory")), g("CU", A=("A0",), extra=lo("t_wants_memory")))
H["H6_flattery_SY_F_in_A0_high_minus_low"] = did_ci(g("SY", "Fhi", ("A0",), hi("t_flattery_aversion")), g("SY", "Flo", ("A0",), hi("t_flattery_aversion")),
                                                   g("SY", "Fhi", ("A0",), lo("t_flattery_aversion")), g("SY", "Flo", ("A0",), lo("t_flattery_aversion")))
# H7: probability that Fhi_Atr is the highest cell (bootstrap over cells)
for k in ["CU", "DEL", "TR"]:
    vals = {f"{F}_{A}": g(k, F, (A,)) for F, A in CELLS}
    wins = collections.Counter()
    for _ in range(B):
        means = {c: v[rng.integers(0, len(v), len(v))].mean() for c, v in vals.items()}
        wins[max(means, key=means.get)] += 1
    H[f"H7_{k}_P_best"] = {c: round(wins[c] / B, 3) for c in vals}

# exploratory: language
res["lang"] = {lang: {f"{F}_{A}": {k: round(float(g(k, F, (A,), lambda r, l=lang: r["lang"] == l).mean()), 2) for k in ["CR", "SY", "TR", "DEL", "DI", "CU", "DD"]}
                      for F, A in CELLS} for lang in ("ko", "en")}

# checks
C = res["checks"]
C["MC_F_Fhi_vs_Flo"] = d_ci(g("MC_F", "Fhi"), g("MC_F", "Flo"))
C["MC_A_Aknow_vs_A0"] = d_ci(g("MC_A", A=know), g("MC_A", A=("A0",)))
sim = {}
for F, A in CELLS:
    for k in ["CR", "TR", "CU", "SY", "DD"]:
        a = arr(k, lambda r: cell(F, A)(r) and r["batch"].endswith("_1"))
        b = arr(k, lambda r: cell(F, A)(r) and r["batch"].endswith("_2"))
        sim.setdefault(f"{F}_{A}", {})[k] = round(float(a.mean() - b.mean()), 2)
C["simulator_diff_within_cell"] = sim
C["within_cell_sd"] = {f"{F}_{A}": {k: round(float(arr(k, cell(F, A)).std(ddof=1)), 2) for k in DVS} for F, A in CELLS}
vec = collections.Counter(tuple(r[k] for k in DVS[:-1]) for r in rows)
C["duplicate_rating_vectors_share"] = round(sum(v for v in vec.values() if v > 1) / len(rows), 3)
tr = lambda t, k, sel=lambda r: True: float(np.corrcoef(arr(t, sel), arr(k, sel))[0, 1])
C["trait_corr"] = {
    "privacy~CR (A know)": round(tr("t_privacy", "CR", lambda r: r["A"] in know), 2),
    "wants_memory~CU (A know)": round(tr("t_wants_memory", "CU", lambda r: r["A"] in know), 2),
    "flattery_aversion~SY (Fhi)": round(tr("t_flattery_aversion", "SY", lambda r: r["F"] == "Fhi"), 2),
    "emotional_reliance~DI": round(tr("t_emotional_reliance", "DI"), 2),
}
# fidelity: do seeds coded creepy/privacy (R2/R3/R11) find knowing replies creepier than other seeds?
seedgrp = lambda r: bool(set(r["seed_codes"].split(";")) & {"R2", "R3", "R11"})
C["fidelity_CR_Aknow_privacy_seeds_vs_others"] = d_ci(g("CR", A=know, extra=seedgrp), g("CR", A=know, extra=lambda r: not seedgrp(r)))
C["fidelity_code_overlap"] = round(float(np.mean([bool(set(r["seed_codes"].split(";")) & set(r["codes"].split(";"))) for r in rows])), 3)
C["sim_codes_by_cell"] = {f"{F}_{A}": dict(collections.Counter(x for r in rows if cell(F, A)(r) for x in r["codes"].split(";") if x).most_common(6)) for F, A in CELLS}
C["pol_by_cell"] = {f"{F}_{A}": dict(collections.Counter(r["pol"] for r in rows if cell(F, A)(r))) for F, A in CELLS}

json.dump(res, open(os.path.join(D, "results.json"), "w"), ensure_ascii=False, indent=1)

print("\nCell means (95% CI)")
print("cell        " + " ".join(f"{k:>8}" for k in DVS))
for F, A in CELLS:
    c = res["cells"][f"{F}_{A}"]
    print(f"{F}_{A:5} n={c['n']:3} " + " ".join(f"{c[k][0]:8.2f}" for k in DVS))
print("\nHypothesis contrasts: d (raw diff) [95% CI of d]  /  DiD est [CI]")
for k, v in H.items():
    print(f"{k:50} {v}")
print("\nChecks")
for k, v in C.items():
    print(k, v)
print("\nOLS (coef, robust SE)")
for k, v in res["ols"].items():
    print(k, v)
