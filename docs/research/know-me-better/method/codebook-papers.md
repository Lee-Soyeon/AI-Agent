# Paper coding codebook

Research question: beyond facts pulled from connected accounts (Google, calendar, mail), what must an AI know about a person to credibly "know them better than they know themselves"? Which kinds of self-knowledge does the self, close others, or an algorithm hold most accurately?

For every paper in your batch, output ONE JSON object per line with exactly these keys:

```
{"pid": "P0001", "rel": "Y", "dims": ["D1"], "flags": ["P"], "data": ["likes"], "cmp": "AI>others", "find": "페이스북 좋아요 300개면 배우자보다 성격 판단이 정확"}
```

## rel — relevance (be strict)
- "Y": directly about knowing/inferring/predicting a person's traits, states, values, preferences, behavior, or self-knowledge; OR accuracy of self vs. others' judgments; OR AI/algorithm personalization, user modeling, memory of users; OR how people perceive/feel about being profiled, known, remembered or personalized; OR ethics/privacy of such inference.
- "N": only shares keywords (e.g., attitude scales on unrelated topics, neuroscience of dopamine, hardware memory, patient-outcome digital twins of organs, generic LLM benchmarks unrelated to individual users, multi-agent coordination).
- "?": cannot judge from title alone.

## dims — which dimension(s) of a person the paper is about (1–3 codes, most central first; [] if rel=N)
- D1 personality traits (Big Five, HEXACO)
- D2 values, motives, goals
- D3 emotion dynamics, mood, stress, mental health state
- D4 behavioral habits & daily rhythms (sleep, mobility, phone use)
- D5 say–do gap (stated vs. revealed preference, self-report vs. logged behavior, attitude–behavior gap)
- D6 self-prediction errors (affective forecasting, planning fallacy, introspection limits, intention–behavior gap)
- D7 blind spots / how others see me (reputation, self-enhancement, bias blind spot, metaperception)
- D8 situation-specific if-then patterns (person × situation, within-person variability)
- D9 relationships & social roles
- D10 life story, narrative identity, self-concept
- D11 change over time (personality development, life transitions)
- D12 body & physiological signals (HRV, sleep physiology, voice acoustics)
- D13 tastes & consumption preferences (music, products, content, recommender preferences)
- D14 language & communication style
- D15 cognitive/decision style (risk, biases, trust in algorithms, reasoning)

## flags (0–2)
- "E" ethics, privacy, manipulation, targeting, consent
- "P" people's perceptions, trust, acceptance, feelings about AI/algorithms/personalization

## data — data sources used (0–3, from this list only)
self-report, informant, social-media-text, likes-clicks, smartphone-sensing, wearable-physio, chat-logs, interviews, behavior-logs, music-media, speech-voice, experiment, review-theory

## cmp — the accuracy comparison the paper reports (one value)
- "AI>self": algorithm predicts the person's outcomes/behavior better than the person's own self-report/self-prediction
- "AI>others": algorithm more accurate than friends/family/acquaintances
- "AI~others": comparable
- "others>AI": humans more accurate than algorithm
- "others>self": other people's judgments outperform the self on something
- "self>others": the self is more accurate than others
- "mixed": depends on trait/domain (e.g., SOKA)
- "none": no such comparison

## find — ONE line in Korean (≤ 70 characters)
The key finding relevant to the research question, with a number if the abstract gives one. If rel=N write "".

## Rules
- Use only the title and abstract given; do not invent numbers.
- Output exactly one line per input paper, same order, valid JSON (double quotes, no trailing commas).
- Write the whole output file in one go (use a Bash heredoc with a quoted delimiter, e.g. `cat > FILE <<'EOF' ... EOF`, or the Write tool). Then verify the line count equals the input line count with `wc -l`, and validate with `python3 -c "import json;[json.loads(l) for l in open('FILE')]"`.
