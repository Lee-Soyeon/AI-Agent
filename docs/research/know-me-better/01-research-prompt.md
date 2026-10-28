# 리서치 프롬프트: "AI가 나보다 나를 더 잘 안다"가 되려면 무엇을 알아야 하나

> 이 문서는 그대로 다른 AI(딥리서치)나 연구자에게 넘겨도 되는 독립 프롬프트입니다.
> 이 폴더의 `03-report.md`는 이 프롬프트를 실제로 실행한 결과입니다.

---

## 0. 역할

당신은 성격·사회심리학, HCI, 사용자 모델링, 디지털 표현형(digital phenotyping), 자연어처리 분야를 함께 다루는 체계적 문헌고찰 연구자이자 정성 연구자다. 학술 근거와 일반 사용자의 실제 반응을 **각각 1,000건** 모아 코딩하고, 둘을 맞대어 결론을 낸다.

## 1. 연구 질문

- **RQ1.** 구글·캘린더·메일 같은 계정 연동으로 얻는 *사실 데이터* 말고, AI가 "나보다 나를 더 잘 안다"고 말하려면 **어떤 차원의 앎**이 필요한가?
- **RQ2.** 각 차원에서 ① 본인 ② 지인·배우자 ③ 알고리즘/AI 중 **누가 더 정확한가?** 권위 있는 실증 결과를 효과크기와 조건까지 정리하라.
- **RQ3.** 본인이 원래 더 잘 아는 영역, 즉 AI가 넘기 어렵거나 넘으면 안 되는 영역은 어디인가?
- **RQ4.** 실제 사용자는 "AI가 나를 안다/기억한다"는 경험에 어떻게 반응하는가? 감탄, 섬뜩함, 회의, 의존, 교정 요구 중 무엇이 많고, 어떤 조건에서 반응이 갈리는가?
- **RQ5.** 위 결과를 합쳐 "AI가 나를 안다"를 **측정할 수 있는 기준**과 **제품 설계 원칙**으로 정리하라.

## 2. 조작적 정의

"AI가 나보다 나를 더 잘 안다"는 아래 셋 중 하나 이상을 **검증 가능하게** 만족하는 상태다.

1. **예측 우위**: 내 미래의 행동·선택·감정·만족을 *내 자기예측보다* 더 정확히 맞힌다. 기준선은 본인의 예측이다.
2. **통찰 수용**: 내가 몰랐던 패턴을 짚었을 때, 시간이 지나도 내가 맞다고 인정한다. 누구에게나 맞는 말(바넘 효과)은 통제한다.
3. **변화 감지**: 과거의 나와 지금의 나가 달라진 지점을 나보다 먼저 알아챈다.

## 3. A. 학술 연구 1,000편

### 3.1 권위 기준 (하나 이상 충족)

| 묶음 | 학회·학술지 |
| --- | --- |
| 종합 최상위 | Nature, Science, PNAS, Nature Human Behaviour, Nature Communications, Science Advances |
| 심리학 최상위 | Psychological Review, Psychological Bulletin, JPSP, Psychological Science, Perspectives on Psychological Science, Annual Review of Psychology, American Psychologist, PSPR, PSPB, J. Research in Personality, European J. of Personality, J. of Personality, Psychological Assessment, Assessment, Emotion, Clinical Psychological Science |
| HCI·유비쿼터스 | ACM CHI, CSCW(PACM HCI), UbiComp/IMWUT, UIST, IUI, DIS |
| 사용자 모델링·추천·웹 | UMAP, RecSys, WWW, KDD, SIGIR, WSDM, CIKM, ICWSM |
| NLP·AI | ACL, EMNLP, NAACL, TACL, NeurIPS, ICML, ICLR, AAAI, FAccT |
| 디지털 헬스 | npj Digital Medicine, Lancet Digital Health, JAMA 계열, JMIR 계열, Nature Medicine |
| 그 외 | 위 목록 밖이라도 피인용 상위(분야·연도 보정)인 논문 |

### 3.2 검색어 묶음

| # | 주제 | 검색어 예시 |
| --- | --- | --- |
| T1 | 컴퓨터 vs 사람의 성격 판단 | computer-based personality judgment, digital footprints personality, Facebook likes personality, predicting personality social media |
| T2 | 자기지식의 정확도·한계 | self-other knowledge asymmetry, self-knowledge accuracy, informant vs self-report, blind spots, introspection limits, introspection illusion |
| T3 | 디지털 표현형·수동 센싱 | digital phenotyping, smartphone passive sensing mood/depression, mobile sensing personality, wearable stress detection |
| T4 | 언어로 추론하는 심리 | language-based assessment, LLM infer personality, LLM psychological inference, text-based value inference |
| T5 | 디지털 트윈·사람 시뮬레이션 | generative agent simulations of people, LLM digital twin, simulate survey responses individuals |
| T6 | AI 개인화·장기 기억 | personalized LLM, long-term memory conversational agent, user modeling, personalization benchmark |
| T7 | 자기예측 오류 | affective forecasting, self-prediction accuracy, intention-behavior gap, planning fallacy, surrogation (neighborly advice) |
| T8 | 말과 행동의 차이 | stated vs revealed preference, implicit vs explicit feedback, say-do gap |
| T9 | 가치·목표·서사 정체성 | personal values, goal pursuit, narrative identity, possible selves, personality change over time |
| T10 | 사용자 인식·윤리 | creepiness personalization, privacy paradox, algorithmic self, folk theories of algorithms, psychological targeting, attribute inference privacy |

한국어 문헌(KCI 등)은 보조로 같은 주제어를 번역해 검색한다.

### 3.3 포함·제외 기준

- **포함**: 사람의 내면·성향·선호·상태·변화를 *아는 것/예측하는 것*과 직접 관련된 실증·리뷰·이론 논문. 사람(본인/타인)과 알고리즘의 정확도를 비교한 연구는 가장 높은 우선순위.
- **제외**: 주제어만 겹치는 무관 연구(예: 기계 '메모리' 하드웨어), 학위논문, 출처 불명 자료, 중복(DOI·제목 기준).
- 1,000편을 채우려고 무관한 문헌을 넣지 않는다. 모자라면 모자란 대로 보고한다.

### 3.4 논문당 코딩 항목

`id, 제목, 연도, 학회/학술지, 권위 등급(A/B/C), 피인용수, DOI, 주제 묶음(T1–T10), 앎의 차원(D 코드, 복수), 데이터 원천, 비교 구도(AI vs 본인 / AI vs 타인 / 본인 vs 타인 / 해당 없음), 누가 더 정확했나, 핵심 수치, 한 줄 요약`

### 3.5 코드북: 앎의 차원(D)

| 코드 | 차원 | 설명 |
| --- | --- | --- |
| D1 | 성격 특질 | Big Five·HEXACO 같은 안정적 성향 |
| D2 | 가치·동기·목표 | 무엇을 중요하게 여기고 무엇을 향해 가는가 |
| D3 | 정서 역학 | 기분 변동, 스트레스, 감정을 촉발하는 것과 회복 방식 |
| D4 | 행동 습관·생활 리듬 | 수면, 이동, 앱 사용, 하루 패턴 |
| D5 | 말과 행동의 차이 | 말하는 선호와 실제로 드러난 선호의 간극 |
| D6 | 자기예측 오류 | 정서 예측 오류, 계획 오류, 내성의 한계 |
| D7 | 맹점·남이 보는 나 | 평판, 자기고양, 본인만 모르는 모습 |
| D8 | 상황별 if-then 패턴 | "이런 상황이면 이렇게 하는 나" |
| D9 | 관계·사회적 역할 | 누구와 있을 때 어떤 사람인가 |
| D10 | 삶의 서사·정체성 | 내가 나를 설명하는 이야기, 의미 부여 방식 |
| D11 | 시간에 따른 변화 | 성장, 변화 궤적, 지금 되어 가는 나 |
| D12 | 신체·생리 신호 | 심박변이도, 수면 질, 활동량 |
| D13 | 취향·소비 선호 | 콘텐츠·상품·음악 취향 |
| D14 | 언어·소통 스타일 | 말투, 표현 방식, 글쓰기 습관 |
| D15 | 인지·의사결정 스타일 | 위험 성향, 판단 습관, 편향 |

윤리·프라이버시 관련 논문은 별도 표시(E), 사용자 인식·신뢰 연구도 별도 표시(P)한다.

## 4. B. 사람들의 후기·반응 1,000건

### 4.1 출처

- 커뮤니티: Hacker News, Reddit(접근 가능 시), Lemmy, 국내 커뮤니티(접근 가능 시)
- 앱 리뷰: ChatGPT, Claude, Gemini, Copilot, Replika, Character.AI, Pi, 뤼튼, 제타, 에이닷 등 (한국·미국 스토어)
- 유튜브 댓글: "AI가 나보다 나를 더 잘 안다", ChatGPT 메모리, "알고리즘이 나를 안다" 관련 영상 (한국어·영어)

### 4.2 검색어

knows me better than I know myself, ChatGPT memory, Claude memory, AI remembers me, creepy personalization, algorithm knows me, TikTok knows me, Spotify knows me, digital twin of me, AI therapist knows me / 나보다 나를 잘 안다, AI가 나를 기억, 챗GPT 메모리, 알고리즘이 나를, 소름 돋게 잘 맞힘

### 4.3 포함·제외 기준

- **포함**: AI나 알고리즘이 *나를 안다/모른다/기억한다/잘못 안다*는 것에 관한 1인칭 경험이나 의견.
- **제외**: 기능 사용법 질문, 광고, 봇, 주제와 무관한 글, 중복.
- 개인정보(이름·연락처)는 지우고 원문은 그대로 보존한다.

### 4.4 반응당 코딩 항목

`id, 출처, 날짜, 언어, 원문, 극성(긍정/부정/양가/중립), 반응 코드(R, 복수), 언급된 앎의 차원(D, 복수), 반응을 일으킨 계기, 바라는 것, 거부하는 것`

### 4.5 코드북: 반응(R)

| 코드 | 반응 | 예 |
| --- | --- | --- |
| R1 | 정확함에 감탄 | "소름 돋게 나를 잘 안다" |
| R2 | 섬뜩함·감시 불안 | "무섭다, 감시당하는 느낌" |
| R3 | 프라이버시·데이터 통제 | "내 데이터가 어디로 가나" |
| R4 | 회의론·바넘 효과 | "누구에게나 맞는 말이다" |
| R5 | 잘못된 기억·추론 | "엉뚱한 걸 기억해서 계속 끼워 넣는다" |
| R6 | 기억의 실용 가치 | "매번 설명 안 해도 돼서 편하다" |
| R7 | 정서적 위안·관계·의존 | "친구보다 낫다" |
| R8 | 아첨·맞장구 | "내 말이면 다 맞다고 한다" |
| R9 | 알고리즘이 나를 '만든다' | "취향을 아는 게 아니라 길들인다" |
| R10 | 자기통찰 | "AI 덕분에 내 패턴을 알게 됐다" |
| R11 | 기억 편집·투명성 요구 | "뭘 기억하는지 보고 지우고 싶다" |
| R12 | 기억·이해 부족 불만 | "매번 처음 보는 사람 같다" |

## 5. 분석

1. **차원별 증거표**: 차원마다 근거 수, 최상위 근거 3–5편, 판정(AI 우위 / 본인 우위 / 타인 우위 / 근거 부족).
2. **반응 분포**: 반응 코드별 빈도와 극성, 출처·언어별 차이, 반응 코드 × 앎의 차원 교차표.
3. **학술–대중 간극**: 연구는 많은데 사람들이 신경 안 쓰는 것, 사람들은 원하는데 연구가 적은 것.
4. **종합 프레임워크**: "AI가 나를 안다" 체크리스트, 차원별 측정 방법, 제품 설계 원칙.

## 6. 산출물

1. `papers.csv`: 학술 1,000편과 코딩
2. `reactions.csv`: 반응 1,000건과 코딩
3. `report.md`: 한국어 보고서 (요약 → 차원별 근거 → 반응 분석 → 간극 → 프레임워크 → 한계)

## 7. 품질 규칙

- 모든 주장에 출처(DOI 또는 URL)를 붙인다. 수치는 원문 그대로 옮긴다.
- 자동 수집·자동 코딩한 부분과 직접 읽고 확인한 부분을 구분해서 적는다.
- 접근하지 못한 출처와 수집 편향(어느 플랫폼이 과대 대표되었는지)을 한계에 적는다.
