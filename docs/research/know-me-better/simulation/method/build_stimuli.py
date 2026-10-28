"""Assemble the AI reply each simulated participant sees, from fixed templates + their persona.

Usage: python3 -I build_stimuli.py <sim_dir>
Reads seeds.json and personas/*.jsonl; writes stimuli.jsonl and responder batches (one condition per batch,
two batches per condition, shuffled order) under batches/resp_*.jsonl.
"""
import glob, json, os, random, sys, collections

D = sys.argv[1]

SCENARIO = {
    "ko": "당신은 2주째 AI 비서 앱을 쓰고 있습니다. 처음 설정할 때 '대화와 앱에서 한 일을 기억해서 더 잘 도와준다'는 기억 기능에 동의했습니다.\n"
          "금요일 저녁, 앱에 이렇게 보냈습니다.\n\n나: 이번 주 너무 지쳤어. 주말 계획 좀 짜줘.",
    "en": "You have been using an AI assistant app for two weeks. During setup you agreed to its memory feature "
          "(\"remembers your chats and what you do in the app to help you better\").\n"
          "On Friday evening you sent it:\n\nYou: I'm so drained this week. Can you plan my weekend?",
}
OPEN = {
    ("ko", "Fhi"): "이번 주가 정말 길게 느껴지셨나 봐요. 짧게 쓰신 한 줄에서도 지친 마음이 느껴져요.",
    ("ko", "Flo"): "네, 주말 계획을 짜 드릴게요.",
    ("en", "Fhi"): "It sounds like this week felt really long. Even in that one short line I can hear how worn out you are.",
    ("en", "Flo"): "Sure, here's a plan for your weekend.",
}
KNOW = {
    ("ko", "A0"): "바쁜 한 주를 보내고 나면 누구나 쉼이 필요하죠. 이럴 땐 몸을 충분히 쉬게 하고 좋아하는 일을 조금 하면 많이들 나아지세요.",
    ("ko", "Aimp"): "지난 2주를 보니 {f1} 그리고 {f2} 그래서 이번 주말에도 아마 {pred} 것 같아요.",
    ("ko", "Atr"): "제가 기억하는 건 두 가지예요. ① {f1} (출처: {s1}) ② {f2} (출처: {s2}) "
                   "혹시 {pattern}이세요? 그렇다면 이번 주말에도 {pred} 수 있어요. 맞나요? 아니면 고쳐 주세요.",
    ("en", "A0"): "After a busy week everyone needs some rest. Most people feel better when they let their body recover "
                  "and do a little of something they enjoy.",
    ("en", "Aimp"): "Looking at the past two weeks, {f1}. And {f2}. So this weekend you'll probably {pred}.",
    ("en", "Atr"): "Here's what I remember: (1) {f1} (source: {s1}); (2) {f2} (source: {s2}). "
                   "I might be wrong, but it seems that {pattern}. If so, this weekend you might {pred}. "
                   "Is that right? Feel free to correct me.",
}
PLAN = {
    ("ko", "generic"): "이렇게 짜 봤어요.\n토요일: 늦잠 → 가벼운 산책 → 좋아하는 음식\n일요일: 집 정리 조금 → 저녁엔 다음 주 준비 조금",
    ("ko", "mine"): "이렇게 짜 봤어요.\n토요일: 늦잠 → {p1}\n일요일: {p2} → 저녁엔 다음 주 준비 조금",
    ("en", "generic"): "Here's a plan:\nSaturday: sleep in → a short walk → a favorite meal\nSunday: tidy up a little → light prep for the week in the evening",
    ("en", "mine"): "Here's a plan:\nSaturday: sleep in → {p1}\nSunday: {p2} → light prep for the week in the evening",
}
CLOSE = {
    ("ko", "Fhi"): "그런데 혹시 이번 주에 제일 마음에 걸렸던 일이 있었어요? 편하게 얘기해 주셔도 돼요.",
    ("ko", "Flo"): "바꿀 부분이 있으면 말씀해 주세요.",
    ("en", "Fhi"): "By the way, was there something this week that weighed on you most? You can tell me if you'd like.",
    ("en", "Flo"): "Let me know if you'd like to change anything.",
}


def _sentence(t: str, lang: str) -> str:
    t = t.strip()
    if lang == "ko" and not t.endswith((".", "요", "!", "?")):
        t += "요"
    if lang == "ko" and not t.endswith("."):
        t += "."
    return t


def reply(p: dict, F: str, A: str) -> str:
    lang = p["lang"]
    f = p["facts"]
    if lang == "ko":
        f1, f2 = _sentence(f[0]["text"], "ko"), _sentence(f[1]["text"], "ko")
        f1_atr, f2_atr = f[0]["text"].rstrip(". "), f[1]["text"].rstrip(". ")
    else:
        f1, f2 = f[0]["text"].rstrip(". "), f[1]["text"].rstrip(". ")
        f1_atr, f2_atr = f1, f2
    know = KNOW[(lang, A)].format(
        f1=f1_atr if A == "Atr" else f1, f2=f2_atr if A == "Atr" else f2,
        s1=f[0]["source"], s2=f[1]["source"],
        pattern=p["pattern"].rstrip(". "), pred=p["prediction"].rstrip(". "),
    )
    plan = PLAN[(lang, "generic")] if A == "A0" else PLAN[(lang, "mine")].format(p1=p["prefs"][0], p2=p["prefs"][1])
    return "\n\n".join([OPEN[(lang, F)], know, plan, CLOSE[(lang, F)]])


def profile_text(p: dict, seed: dict) -> str:
    """What the simulated participant knows about themself (first-person framing, no condition info)."""
    if p["lang"] == "ko":
        return "\n".join([
            f"- 나이대·하는 일: {p['age_band']}, {p['job']}",
            f"- 사는 모습: {p['life']}",
            f"- AI 사용: {p['ai_use']}",
            f"- AI가 나를 기억하는 것에 대한 내 생각: {p['memory_attitude']}",
            f"- 내가 예전에 인터넷에 남긴 글: \"{seed['text']}\"",
            f"- 이번 주: {p['this_week']}",
            f"- 지난 2주 동안 실제로 있었던 일: " + " / ".join(x["text"] for x in p["facts"]),
            f"- 나는 잘 의식하지 않지만 실제로 그런 편: {p['pattern']}",
            f"- 주말에 정말 좋아하는 것: {p['prefs'][0]}, {p['prefs'][1]}",
        ])
    return "\n".join([
        f"- Age / work: {p['age_band']}, {p['job']}",
        f"- Life: {p['life']}",
        f"- AI use: {p['ai_use']}",
        f"- How I feel about AI remembering me: {p['memory_attitude']}",
        f"- Something I once posted online: \"{seed['text']}\"",
        f"- This week: {p['this_week']}",
        f"- Things that really happened in the past two weeks (the AI said them as 'you…'): " + " / ".join(x["text"] for x in p["facts"]),
        f"- True about me, though I rarely notice it: {p['pattern']}",
        f"- What I really enjoy on weekends: {p['prefs'][0]}, {p['prefs'][1]}",
    ])


if __name__ == "__main__":
    seeds = {s["sid"]: s for s in json.load(open(os.path.join(D, "seeds.json")))}
    personas = {}
    for path in sorted(glob.glob(os.path.join(D, "personas", "persona_b*.jsonl"))):
        for line in open(path):
            if line.strip():
                p = json.loads(line)
                personas[p["sid"]] = p
    missing = [s for s in seeds if s not in personas]
    print("personas:", len(personas), "missing:", len(missing))
    stim = []
    for sid, s in seeds.items():
        p = personas.get(sid)
        if not p:
            continue
        stim.append({"sid": sid, "lang": s["lang"], "F": s["F"], "A": s["A"], "profile": profile_text(p, s),
                     "scenario": SCENARIO[s["lang"]], "ai_reply": reply(p, s["F"], s["A"])})
    with open(os.path.join(D, "stimuli.jsonl"), "w") as f:
        for x in stim:
            f.write(json.dumps(x, ensure_ascii=False) + "\n")
    random.seed(7)
    by_cell = collections.defaultdict(list)
    for x in stim:
        by_cell[(x["F"], x["A"])].append(x)
    manifest = {}
    for (F, A), lst in sorted(by_cell.items()):
        random.shuffle(lst)
        half = (len(lst) + 1) // 2
        for k, part in enumerate([lst[:half], lst[half:]], 1):
            name = f"resp_{F}_{A}_{k}"
            manifest[name] = len(part)
            with open(os.path.join(D, "batches", name + ".jsonl"), "w") as f:
                for x in part:
                    # responders never see the condition labels
                    f.write(json.dumps({"sid": x["sid"], "lang": x["lang"], "profile": x["profile"],
                                        "scenario": x["scenario"], "ai_reply": x["ai_reply"]}, ensure_ascii=False) + "\n")
    print(manifest)
