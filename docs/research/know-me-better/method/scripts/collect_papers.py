"""Collect candidate papers from Crossref + Europe PMC for the 'AI knows me better than I do' review.

Usage: python3 -I collect_papers.py <raw_dir>
Writes <raw_dir>/crossref_*.json, <raw_dir>/epmc_*.json (cached per query).
"""
import json, os, sys, time, re, hashlib, urllib.parse
import requests

RAW = sys.argv[1]
S = requests.Session()
S.headers["User-Agent"] = "know-me-review/0.1 (academic literature review script)"

# (topic, query, required regex groups: every group must match title+abstract)
Q = [
    # T1 computer vs human personality judgment
    ("T1", "computer-based personality judgments more accurate than humans", [r"personalit"]),
    ("T1", "predicting personality from digital footprints", [r"personalit", r"digital|online|social media|facebook|footprint|smartphone|record"]),
    ("T1", "facebook likes predict personality traits", [r"personalit|trait|attribute", r"facebook|like"]),
    ("T1", "private traits and attributes are predictable from digital records", [r"predict|infer", r"digital|online|facebook|record"]),
    ("T1", "personality prediction from social media text", [r"personalit", r"social media|twitter|facebook|text|language|post"]),
    ("T1", "personality prediction from smartphone data", [r"personalit", r"smartphone|mobile|phone"]),
    ("T1", "accuracy of personality judgment informant self", [r"personalit|trait", r"accura|agreement|judg"]),
    ("T1", "zero-acquaintance personality judgment accuracy", [r"personalit|trait", r"accura|judg"]),
    ("T1", "machine learning personality assessment validity", [r"personalit", r"machine learning|algorithm|automat|computer"]),
    ("T1", "meta-analysis predicting personality digital footprints", [r"personalit", r"digital|social media|online"]),
    ("T1", "personality from music preferences spotify", [r"personalit|trait", r"music|spotify|listen"]),
    # T2 self-knowledge
    ("T2", "self-other knowledge asymmetry", [r"self", r"other|informant|observer|peer"]),
    ("T2", "others sometimes know us better than we know ourselves", [r"self", r"know|accura|percept"]),
    ("T2", "self-knowledge accuracy personality", [r"self-knowledge|self-insight|self-perception|self-report|know (ourselves|themselves|yourself)", r"accura|valid|bias|blind"]),
    ("T2", "blind spots in self-perception", [r"self", r"blind|bias|accura|insight"]),
    ("T2", "limits of introspection", [r"introspect|self-report|self-knowledge|verbal report"]),
    ("T2", "introspection illusion bias blind spot", [r"introspect|bias blind|self"]),
    ("T2", "self-enhancement self-perception accuracy", [r"self-enhanc|positive illusion|self-perception", r"accura|bias|valid"]),
    ("T2", "metaperception how others see us accuracy", [r"meta-?percept|reputation|others see|how others"]),
    ("T2", "informant reports versus self-reports predicting behavior", [r"informant|peer|observer|other-report", r"self-report|self"]),
    ("T2", "adaptive unconscious self-knowledge", [r"self-knowledge|unconscious|introspect|self-insight"]),
    ("T2", "interpersonal perception accuracy social relations model", [r"percept|judg|accura", r"interpersonal|social relations|dyad"]),
    # T3 digital phenotyping / passive sensing
    ("T3", "digital phenotyping mental health smartphone", [r"digital phenotyp|passive|smartphone|mobile sens|sensor", r"mental|depress|mood|anxiety|stress|well-being|psychiatr"]),
    ("T3", "passive sensing depression prediction smartphone", [r"passive|sensing|smartphone|mobile|wearable|sensor", r"depress|mood|mental"]),
    ("T3", "mobile sensing personality behavior", [r"mobile sens|smartphone|sensing|passive", r"personalit|behavio"]),
    ("T3", "wearable stress detection physiological signals", [r"wearable|physiolog|heart rate|electrodermal|sensor", r"stress|emotion|affect|mood"]),
    ("T3", "StudentLife smartphone sensing students mental health", [r"sensing|smartphone|mobile", r"student|college|mental|well-being|academic"]),
    ("T3", "ecological momentary assessment predicting mood", [r"ecological momentary|experience sampling|EMA|daily diary", r"mood|affect|emotion|predict"]),
    ("T3", "smartphone usage patterns predict well-being", [r"smartphone|phone|app usage|screen", r"well-being|mood|depress|personalit|stress"]),
    ("T3", "speech voice markers depression detection", [r"speech|voice|acoustic|vocal", r"depress|mood|emotion|mental"]),
    ("T3", "sleep and circadian rhythm sensing mood", [r"sleep|circadian|rhythm", r"mood|depress|sensing|wearable|smartphone"]),
    ("T3", "personal informatics self-tracking self-knowledge", [r"self-track|personal informatics|quantified self|lifelog", r"self|reflect|insight|knowledge"]),
    ("T3", "just-in-time adaptive intervention prediction", [r"just-in-time|adaptive intervention|JITAI", r"predict|sens|mobile"]),
    # T4 language-based inference
    ("T4", "language-based assessment of psychological traits", [r"language|text|word|linguistic", r"personalit|psycholog|trait|well-being|depress"]),
    ("T4", "large language models infer personality from text", [r"language model|LLM|GPT|ChatGPT", r"personalit|psycholog|trait"]),
    ("T4", "large language models infer psychological dispositions social media users", [r"language model|LLM|GPT", r"psycholog|personalit|disposition"]),
    ("T4", "inferring personal values from text", [r"value", r"text|language|social media|infer|predict"]),
    ("T4", "predicting depression from social media language", [r"social media|facebook|twitter|reddit|language|text", r"depress|mental"]),
    ("T4", "word use personality linguistic markers", [r"word|language|linguistic|LIWC", r"personalit|psycholog|self"]),
    ("T4", "large language models theory of mind user mental states", [r"language model|LLM|GPT", r"theory of mind|mental state|belief|intent"]),
    ("T4", "LLM attribute inference privacy personal information from text", [r"language model|LLM|GPT", r"privacy|infer|personal|attribute"]),
    # T5 digital twin / simulation
    ("T5", "generative agent simulations of people", [r"generative agent|language model|LLM|simulat", r"people|individual|human|survey|person"]),
    ("T5", "large language model digital twin of individual", [r"digital twin|simulat|language model|LLM", r"individual|person|human|user|patient"]),
    ("T5", "language models simulate survey responses human subjects", [r"language model|LLM|GPT|silicon", r"survey|respon|human|participant|sample"]),
    ("T5", "predicting individual decisions with language models", [r"language model|LLM|GPT|machine learning", r"individual|human|decision|choice|behavio"]),
    ("T5", "persona simulation LLM individual behavior", [r"persona|simulat", r"language model|LLM|GPT|agent"]),
    # T6 personalization & memory
    ("T6", "personalized large language models user", [r"personali", r"language model|LLM|GPT|dialog|assistant|chatbot"]),
    ("T6", "long-term memory conversational agents", [r"memory|remember|long-term", r"conversation|dialog|agent|chatbot|assistant|language model"]),
    ("T6", "user modeling conversational assistant personalization", [r"user model|personali|profile", r"conversation|dialog|assistant|chatbot|agent"]),
    ("T6", "persona-based dialogue personalization", [r"persona|personali", r"dialog|conversation|chat"]),
    ("T6", "user modeling adaptation personalization survey", [r"user model|personali|adaptive"]),
    ("T6", "recommender systems user preference elicitation", [r"recommend|preference", r"user|elicit|model"]),
    ("T6", "chatbot memory user perceptions", [r"memory|remember|recall", r"chatbot|agent|assistant|conversation"]),
    ("T6", "social chatbot companion relationship users Replika", [r"chatbot|companion|replika|agent|AI", r"relationship|user|social|loneli|emotion"]),
    # T7 self-prediction errors
    ("T7", "affective forecasting errors", [r"affective forecast|predict.*(feel|emotion|happi)|forecast"]),
    ("T7", "surprising power of neighborly advice surrogation", [r"surroga|advice|forecast|simulat"]),
    ("T7", "self-prediction accuracy of future behavior", [r"self-predict|predict.*(own|self)|forecast", r"behavio|future|accura"]),
    ("T7", "intention-behavior gap meta-analysis", [r"intention", r"behavio"]),
    ("T7", "planning fallacy prediction", [r"planning fallacy|task completion|predict"]),
    ("T7", "end of history illusion personality change", [r"end of history|personality change|predict.*change"]),
    ("T7", "projection bias predicting future preferences", [r"projection bias|future (preference|self)|predict"]),
    ("T7", "impact bias durability bias", [r"impact bias|durability bias|affective forecast"]),
    # T8 stated vs revealed
    ("T8", "stated preferences versus revealed preferences", [r"stated|revealed|self-report", r"preference|behavio|choice"]),
    ("T8", "self-reported versus logged behavior smartphone use accuracy", [r"self-report|estimat|subjective", r"log|objective|actual|measured|track"]),
    ("T8", "implicit feedback versus explicit ratings recommender", [r"implicit|explicit|rating|feedback", r"recommend|user|preference"]),
    ("T8", "attitude behavior consistency", [r"attitude|intention|self-report", r"behavio"]),
    ("T8", "implicit association test predict behavior", [r"implicit|IAT", r"predict|behavio|validity"]),
    ("T8", "what users say versus what they do algorithmic feeds", [r"user|consumer|people", r"preference|choice|want|behavio", r"algorithm|feed|recommend|platform"]),
    # T9 values, goals, narrative identity, change
    ("T9", "narrative identity life story", [r"narrative|life stor"]),
    ("T9", "personal values Schwartz behavior", [r"value", r"behavio|personalit|predict|Schwartz"]),
    ("T9", "personality change across adulthood", [r"personalit", r"change|development|stability"]),
    ("T9", "goal pursuit self-concordance well-being", [r"goal", r"pursuit|concordan|well-being|motivat"]),
    ("T9", "possible selves future self-continuity", [r"possible self|future self|self-continuity"]),
    ("T9", "personality states within-person variability", [r"within-person|state|variab|density distribution|whole trait", r"personalit|trait"]),
    ("T9", "if-then behavioral signatures situation personality", [r"if-then|situation|CAPS|person-situation|signature", r"personalit|behavio"]),
    ("T9", "emotion dynamics inertia variability well-being", [r"emotion|affect", r"dynamic|inertia|variab|instabil"]),
    ("T9", "self-concept clarity", [r"self-concept|self-clarity|identity"]),
    # T10 perception & ethics
    ("T10", "creepiness of personalization", [r"creep|uncanny|personali|privacy", r"personali|recommend|ad|target|AI|algorithm"]),
    ("T10", "privacy paradox personalization", [r"privacy", r"personali|paradox|disclos"]),
    ("T10", "algorithmic self algorithm awareness users", [r"algorithm", r"self|aware|identity|user|folk"]),
    ("T10", "folk theories of algorithms social media", [r"folk theor|algorithm", r"user|social media|feed|theor"]),
    ("T10", "psychological targeting persuasion personality", [r"psycholog|personalit", r"target|persuas|advert|tailor"]),
    ("T10", "algorithm aversion appreciation", [r"algorithm", r"aversion|apprecia|trust|advice"]),
    ("T10", "explainable recommendations user trust transparency", [r"explain|transparen|scrutab", r"recommend|user model|personali"]),
    ("T10", "scrutable user models user control", [r"scrutab|user control|transparen|editable", r"user model|personali|profile|recommend"]),
    ("T10", "anthropomorphism trust AI companion attachment", [r"anthropomorph|attachment|companion|parasocial", r"AI|chatbot|agent|robot|assistant"]),
    ("T10", "sycophancy language models", [r"sycophan|flatter|agree", r"language model|LLM|assistant|AI"]),
    ("T10", "filter bubble recommender preference shaping", [r"filter bubble|echo chamber|preference (shift|shap)|feedback loop|polariz", r"recommend|algorithm|platform"]),
    ("T10", "Barnum effect personality feedback acceptance", [r"Barnum|Forer|personality feedback|acceptance"]),
]

def cache(path, fn):
    if os.path.exists(path):
        return json.load(open(path))
    data = fn()
    json.dump(data, open(path, "w"))
    return data

def crossref(q, rows=200):
    url = "https://api.crossref.org/works"
    params = {"query.bibliographic": q, "rows": rows,
              "filter": "type:journal-article,type:proceedings-article,type:posted-content",
              "select": "DOI,title,container-title,is-referenced-by-count,abstract,type,issued,author,publisher"}
    for attempt in range(5):
        try:
            r = S.get(url, params=params, timeout=60)
            if r.status_code == 200:
                return r.json()["message"]["items"]
            time.sleep(3 * (attempt + 1))
        except Exception as e:
            time.sleep(3 * (attempt + 1))
    return []

def epmc(q, size=300):
    url = "https://www.ebi.ac.uk/europepmc/webservices/rest/search"
    out, cursor = [], "*"
    while len(out) < size:
        params = {"query": q, "format": "json", "resultType": "core", "pageSize": 100, "cursorMark": cursor}
        for attempt in range(5):
            try:
                r = S.get(url, params=params, timeout=60)
                if r.status_code == 200:
                    d = r.json(); break
            except Exception:
                pass
            time.sleep(3 * (attempt + 1))
        else:
            break
        res = d.get("resultList", {}).get("result", [])
        if not res:
            break
        out += res
        nxt = d.get("nextCursorMark")
        if not nxt or nxt == cursor:
            break
        cursor = nxt
    # keep only light fields
    keep = ["id", "source", "pmid", "doi", "title", "authorString", "journalInfo", "pubYear", "abstractText",
            "citedByCount", "pubTypeList", "bookOrReportDetails"]
    slim = []
    for r in out[:size]:
        x = {k: r.get(k) for k in keep}
        ji = r.get("journalInfo") or {}
        x["journal"] = (ji.get("journal") or {}).get("title")
        x.pop("journalInfo", None)
        slim.append(x)
    return slim

if __name__ == "__main__":
    json.dump(Q, open(os.path.join(RAW, "queries.json"), "w"))
    for i, (topic, q, _) in enumerate(Q):
        h = hashlib.md5(q.encode()).hexdigest()[:8]
        a = cache(os.path.join(RAW, f"crossref_{h}.json"), lambda: crossref(q))
        b = cache(os.path.join(RAW, f"epmc_{h}.json"), lambda: epmc(q))
        print(f"{i+1}/{len(Q)} {topic} crossref={len(a)} epmc={len(b)} :: {q}", flush=True)
        time.sleep(0.5)
