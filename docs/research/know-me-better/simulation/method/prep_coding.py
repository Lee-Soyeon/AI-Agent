"""Pool all simulated responses, shuffle, strip condition info, and split into blind coding batches.

Usage: python3 -I prep_coding.py <sim_dir> <n_batches>
Writes batches/code_cNN.jsonl and coding_map.json (rid -> sid).
"""
import glob, json, os, random, sys

D, N = sys.argv[1], int(sys.argv[2])
rows = []
for f in sorted(glob.glob(os.path.join(D, "responses", "r*.jsonl"))):
    for line in open(f):
        if line.strip():
            r = json.loads(line)
            rows.append(r)
lang = {json.loads(l)["sid"]: json.loads(l)["lang"] for l in open(os.path.join(D, "stimuli.jsonl"))}
random.seed(31)
random.shuffle(rows)
cmap = {}
size = -(-len(rows) // N)
for b in range(N):
    with open(os.path.join(D, "batches", f"code_c{b + 1:02d}.jsonl"), "w") as f:
        for i, r in enumerate(rows[b * size:(b + 1) * size]):
            rid = f"X{b * size + i + 1:04d}"
            cmap[rid] = r["sid"]
            f.write(json.dumps({"rid": rid, "lang": lang[r["sid"]], "next_msg": r["next_msg"], "feeling": r["feeling"]},
                               ensure_ascii=False) + "\n")
json.dump(cmap, open(os.path.join(D, "coding_map.json"), "w"))
print("responses:", len(rows), "batches:", N, "size:", size)
