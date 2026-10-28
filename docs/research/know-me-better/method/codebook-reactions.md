# Reaction coding codebook

Research question: how do ordinary people react when an AI or algorithm seems to *know*, *remember*, *profile*, or *fail to know* them? Items are public comments/reviews (Hacker News, Lemmy, YouTube, Google Play, App Store, dcinside) in English or Korean. `context` is the thread/video/app the comment appeared under.

For every item in your batch, output ONE JSON object per line with exactly these keys:

```
{"rid": "R0001", "rel": "Y", "pol": "neg", "codes": ["R5", "R11"], "dims": ["D13"], "trig": "예전 대화를 엉뚱하게 끼워 넣음", "want": "기억 확인·삭제"}
```

## rel — relevance (be strict)
- "Y": a first-person experience or opinion about an AI/algorithm/app knowing, inferring, remembering, personalizing for, profiling, understanding or misunderstanding *the user (or people)*. Memory complaints count when they are about the AI forgetting/misremembering what the user told it (including companion/role-play apps). Opinions about AI memory/personalization/profiling as a social issue count.
- "N": generic tech talk, coding-tool remarks, the word "remember/기억/알고리즘" used in an unrelated sense, bug reports unrelated to memory/knowing (lag, ads, login), news links, spam, concert reviews, etc.

## pol — overall polarity toward being known/remembered by the AI (only if rel=Y, else "")
"pos" | "neg" | "mixed" | "neu"

## codes — reaction codes (1–3, most central first; [] if rel=N)
- R1 awe at accuracy ("it knows me better than I do", 소름 돋게 잘 맞힘)
- R2 creepy / surveillance unease
- R3 privacy & data control (where does my data go, who sees it)
- R4 skepticism / Barnum effect / "it's just pattern-matching, it doesn't really know me"
- R5 wrong memory or wrong inference (stale, mixed-up, hallucinated facts about me, injecting old context)
- R6 practical value of memory/continuity (no need to re-explain, saves time)
- R7 emotional comfort, companionship, dependence ("better than my friends/therapist")
- R8 sycophancy / it just tells me what I want to hear (아첨·맞장구)
- R9 algorithm shapes/manipulates me rather than knowing me (filter bubble, nudging, addiction)
- R10 self-insight — the AI helped me see something about myself
- R11 wants to see/edit/delete/control what it remembers; transparency
- R12 lack of memory/understanding — it forgets me, treats me like a stranger every time

## dims — which aspect of the person is being known/missed (0–2, same D codes as papers)
D1 personality, D2 values/goals, D3 emotions/mental state, D4 habits/routines, D5 say–do gap, D6 self-prediction, D7 blind spots/how others see me, D8 situational patterns, D9 relationships, D10 life story/identity, D11 change over time, D12 body/physiology, D13 tastes/consumption, D14 language/communication style, D15 decision/thinking style. Use [] if the item is only about memory of facts/context with no aspect of the person.

## trig — what triggered the reaction, in Korean, ≤ 25 characters ("" if rel=N)
## want — what the person wants or asks for, in Korean, ≤ 20 characters ("" if nothing stated or rel=N)

## Rules
- Judge only from the text and context given.
- Output exactly one line per input item, same order, valid JSON (double quotes, no trailing commas).
- Write the output with the Write tool or Bash heredocs with a quoted delimiter (`cat >> FILE <<'EOF'`), in chunks of ~60 items if needed. Then verify the line count equals the input line count with `wc -l`, and validate with `python3 -c "import json;[json.loads(l) for l in open('FILE')]"`.
