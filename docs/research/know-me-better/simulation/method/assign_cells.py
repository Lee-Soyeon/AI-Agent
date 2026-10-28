"""Stratified random assignment of the 1,000 reaction seeds to the 2 x 3 cells (run before persona building).

Usage: python3 -I assign_cells.py <reactions.csv> <sim_dir>
Writes <sim_dir>/seeds.json and condition-free persona batches <sim_dir>/batches/persona_bN.jsonl.
"""
import csv, json, random, collections, sys, os

R = list(csv.DictReader(open(sys.argv[1])))
D = sys.argv[2]
CELLS = [(f, a) for f in ("Fhi", "Flo") for a in ("A0", "Aimp", "Atr")]
random.seed(20261028)
strata = collections.defaultdict(list)
for r in R:
    strata[(r["lang"], r["codes"].split(";")[0])].append(r)
assign, k = {}, 0
for key in sorted(strata):
    lst = strata[key]
    random.shuffle(lst)
    for r in lst:
        assign[r["id"]] = CELLS[k % 6]
        k += 1
seeds = []
for i, r in enumerate(R, 1):
    f, a = assign[r["id"]]
    seeds.append({"sid": f"S{i:04d}", "seed_id": r["id"], "lang": r["lang"], "source": r["source"], "context": r["context"][:100],
                  "text": r["text"][:700], "codes": r["codes"], "F": f, "A": a})
json.dump(seeds, open(os.path.join(D, "seeds.json"), "w"), ensure_ascii=False)
order = list(range(len(seeds)))
random.shuffle(order)
n = 8
size = -(-len(order) // n)
for b in range(n):
    with open(os.path.join(D, "batches", f"persona_b{b + 1}.jsonl"), "w") as fh:
        for i in order[b * size:(b + 1) * size]:
            s = seeds[i]
            fh.write(json.dumps({k: s[k] for k in ["sid", "lang", "source", "context", "text"]}, ensure_ascii=False) + "\n")
