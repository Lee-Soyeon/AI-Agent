# 안내형 에이전트 PRD

작성 2026-10-21 · 작성자 이소연 · 상태 초안 (검증 전)

이 문서는 AI Agent 앱의 축을 "웹사이트를 대신 조작하는 에이전트"에서 "AI를 써본 적 없는 사람이 교육 없이 자기 일을 끝내게 하는 안내형 에이전트"로 옮기기 위한 기획이다. 산출물은 세 가지다.

- 이 PRD (`docs/guided-agent-prd.md`)
- 문제부터 다음 단계까지 10장 덱 (`docs/guided-agent-deck.html`)
- Claude Code 에 넘길 구현 프롬프트 (`docs/guided-agent-upgrade-prompt.md`)

## 1. 배경과 문제

### 1.1 출발점이 된 관찰

2026-10-20 밤 대표(이소연)가 보낸 메시지 원문.

> AI 많이 잘 쓰는 사람들은 미친듯이 쓰는데
> 아예 써보지도 않은 사람도 엄청 많은게 왜 그럴까 LLM이 텍스트로 일 시키기에 무슨 UX가 불편한걸까
> 따로 AI 교육 필요없이 AI가 무슨 일을 할 수 있고 차근차근 할 일들 단계 별로 지침을 알려주는 에이전트는 어떨까

가족 세 사람에 대한 관찰 (2026-10-21 인터뷰, 원문).

| 사람 | 관찰 원문 |
|---|---|
| 어머니 | "엄마는 AI 쓸 일이 성경 공부 같은 일일테고" |
| 동생 1 (아르바이트 중) | "알바 하면서 반복되는 작업에 AI를 충분히 쓸 수 있는데 안쓰고 있고" · "액셀 파일에 예를 들어 몇 가지 내용을 채워넣어서 만들어보고 AI한테 시키는 장면을 본 적 있는데 말을 제대로 못해 프롬프트를 제대로 못써 그러니깐 LLM이 일을 정확히 해내질 못하게 되는게 조금 안타까웠음" |
| 동생 2 (취업 준비) | "이제 취업하거나 하는데 AI를 잘 쓰는지 모르겠어 구독해서 쓰는거 같진 않아" |

동생 1의 장면이 이 PRD의 핵심 사례다. 쓸 의지가 있고, 할 일(엑셀 반복 입력)도 있고, 도구(Claude)도 열었다. 그런데 "무엇을 어떻게 적어야 하는지"에서 막혀 결과가 틀렸고, 다시 손으로 했다.

### 1.2 통계로 본 격차

사용자 집단이 둘로 갈라져 있다. 쓰는 사람은 매주 쓰고, 안 쓰는 사람은 한 번도 안 썼다.

| 출처 | 수치 |
|---|---|
| Pew Research 2026-10-09 (미국 성인 5,119명) | 챗봇을 한 번도 안 써본 사람 51%. 그중 "쓰는 법을 모른다" 55% (주 이유 29% + 부차 26%) |
| 방미통위·KISDI 2025 지능정보사회 이용자 패널조사 (18~72세 4,324명, 2026-05 발표) | 생성형 AI 미이용 이유 1위 "사용 방법을 모르거나 익히기 어렵다" 63.5% |
| KISDI STAT Report 26-04 (한국미디어패널 2025) | 생성형 AI 이용률 20대 69.5% · 50대 20.8% · 60대 6.3% · 70세 이상 0.7% |
| 과기정통부 2025 인터넷이용실태조사 (2026-03 발표) | 생성형 AI 경험률 44.5%. 60대·70대 이상 미이용 이유에서 "이용 방법을 몰라서" 각 25.3% · 26.1% |
| Reuters Institute Generative AI and News 2025 (6개국) | 주간 사용 18~24세 59% vs 55세 이상 20% |

"관심이 없어서"가 미이용 이유 1위인 것도 같이 봐야 한다 (Pew 83%, 한국 인터넷이용실태조사 49.5%). 즉 비사용자는 AI를 배우고 싶은 것이 아니다. 자기 일이 끝나길 원할 뿐이다.

### 1.3 연구가 가리키는 원인

빈 텍스트 입력창이 문제라는 가설은 HCI 연구로 뒷받침된다. 아래는 원문을 확인한 것만 적었다 (11장 참고문헌).

1. 입력창에는 단서가 없다. Wattenberger (2023): "The only clue we receive is that we should type characters into the textbox." 좋은 도구는 쓰는 법이 보인다.
2. 비전문가는 프롬프트를 체계 없이 시도한다. Zamfirescu-Pereira et al., CHI 2023 (N=10): 참가자들은 "opportunistically, not systematically" 탐색했고, 한 번의 실패로 "할 수 없다"고 과일반화했으며, 사람에게 시키듯 지시했다. 동생 1의 장면과 정확히 같다.
3. 막히는 지점은 셋이다. Subramonyam et al., CHI 2024 본문 §3.2: 무엇을 시켜야 할지 모름(capability gap), 어떻게 적어야 할지 모름(instruction gap), 자기 의도 자체가 불분명함(intentionality gap).
4. 사용자는 배우려 하지 않는다. Carroll & Rosson 1987 "Paradox of the Active User": 사람은 처리량(production bias)을 우선해 아는 방법만 고수하고, 새 상황을 아는 것으로 해석한다(assimilation bias). 설계 결함이 아니라 구조적 역설이므로 "교육"으로 풀리지 않는다.
5. 오류 상태를 막으면 더 빨리 배운다. Carroll & Carrithers, CACM 1984 "Training Wheels": 초보자가 빠질 오류 상태를 닿지 않게 만든 인터페이스가 더 빠른 학습·더 나은 이해 점수를 냈다. 통제군은 시간의 약 4분의 1을 오류 복구에 썼다.
6. 시스템이 할 수 있는 일을 먼저 보여줘야 한다. Amershi et al., CHI 2019 18개 지침 중 G1 "Make clear what the system can do", G2 "Make clear how well the system can do what it can do".
7. 큰 일은 쪼개서 보여줄 때 결과가 좋다. Wu, Terry, Cai, CHI 2022 "AI Chains" (N=20): 프롬프트를 체인으로 쪼개면 결과 품질과 투명성·통제감이 올라갔다. Ma et al., CHI EA 2024 "ExploreLLM" (N=8): 과제를 하위 과제 스키마로 쪼개 GUI로 보여주자 8명 중 7명이 ChatGPT 응답을 "verbose and generic"이라 했고 5명이 선택지 목록을 선호했다.
8. 자동화와 직접 조작은 섞어야 한다. Horvitz, CHI 1999 "Mixed-Initiative": 에이전트가 주도하되 사용자가 언제든 개입하는 결합. Shneiderman·Maes 1997 논쟁의 해답이 여기 있다.
9. 불만족을 겪어도 고치지 않는다. Kim et al., IUI 2024 (107명, 불만 응답 511건): LLM 지식이 낮은 사용자는 정확성 불만이 더 많고 해결 노력을 덜 했다. 전술을 써도 72%가 미해결.
10. 생성형 AI는 메타인지 부담을 키운다. Tankelevitch et al., CHI 2024 (Best Paper): 프롬프트 작성·출력 평가·의존 여부 판단 전부가 자기 사고를 감시하는 부담이다. 처방은 시스템에 메타인지 지원을 내장하는 것.

### 1.4 교육이 답이 아닌 이유

대표의 첫 가설은 "AI 교육이 필요 없는 에이전트"였다. 연구와 통계가 이 방향을 지지한다.

- 비사용자의 1위 이유는 무관심이다 (1.2). 교육 상품은 이미 관심 있는 사람에게만 팔린다.
- Active User Paradox (1.3-4): 사람은 배우기보다 하려고 한다.
- AI 리터러시 개입 RCT (Puppart & Aru 2025, 고교생): 짧은 교육은 과의존을 줄이지 못했고 과소의존만 늘렸다.
- CHI 2026 Gautam et al. (26명 관찰): 캐주얼 사용자는 튜토리얼을 건너뛰고 "프롬프트 박스가 곧 온보딩 진입점"이었다.

결론: 가르치지 않는다. 일을 끝내 준다. 배움은 부산물로 일어나게 한다 (5.3 프롬프트 미리보기).

## 2. 목표와 비목표

### 2.1 목표

1. AI를 써본 적 없는 사람이 앱을 열고 도움 없이 자기 일 하나를 끝낸다.
2. 빈 입력창을 없앤다. 사용자가 적는 대신 고르고 답한다.
3. 에이전트가 프롬프트를 대신 쓰고 보여준다. 사용자는 "이대로 할까요?"에 답한다.
4. 실행 과정이 단계로 보인다. 브라우저 작업은 화면 캡처로 보인다.
5. API 키·모델 선택 UI를 일반 사용자 경로에서 제거한다.

### 2.2 비목표 (이번 범위 밖)

- 결제 완주. 현 앱의 `handoff_payment` 원칙 유지. 에이전트는 결제 버튼 직전까지만.
- 은행·송금·본인인증·비밀번호 입력. 현 `safety.dart` 규칙 그대로.
- AI 교육 커리큘럼·강의·튜토리얼 화면.
- 새 서비스 자동화 추가. 서비스 카탈로그는 현 109개 유지.
- 사용자 OAuth 토큰 수집·중계 (8장 정책 제약).

## 3. 사용자

### 3.1 타깃

AI를 안 써봤거나 한두 번 열어 보고 닫은 사람. 1.2의 "쓰는 법을 모른다" 55~63.5% 집단.

### 3.2 페르소나 (가족 관찰 기반, 가명 없이 역할로만)

| 역할 | 하고 싶은 일 (추정, 검증 전) | 막히는 지점 (관찰) |
|---|---|---|
| 60대 어머니 | 성경 본문 쉬운 말로 풀기 · 묵상 질문 만들기 · 교회 모임 안내문 | 무엇을 시킬 수 있는지 모름. 로그인·구독 없음 |
| 20대 동생 1 (아르바이트) | 엑셀 반복 입력 · 사진 속 목록을 표로 · 근무표 정리 | 프롬프트를 못 씀 → 결과 틀림 → 포기 (관찰됨) |
| 20대 동생 2 (취업 준비) | 자기소개서 첨삭 · 공고 요약 · 명함·증명사진 보정 | 구독 없음. 쓰는지 확인 안 됨 |

"하고 싶은 일"은 대표의 추정이다. 9.1 검증에서 지난주 실제로 한 일로 교체한다.

## 4. 핵심 경험 원칙

| 원칙 | 근거 | 현 앱 상태 |
|---|---|---|
| P1 빈 입력창 대신 할 일 고르기 | Wattenberger · Amershi G1 | 홈에 예시 9개 (`guide_screen.dart` `taskExamples`). 전부 쇼핑·메일 |
| P2 한 번에 하나씩 묻기, 선택지로 | Horvitz · ExploreLLM | `ask_user` 도구와 선택지 카드 존재. 작업 중에만 쓰임 |
| P3 프롬프트를 대신 써서 보여주기 | Johnny · Training Wheels | 없음 |
| P4 실행 과정을 단계로 보이기 | Gulf of Evaluation · AI Chains | 실시간 로그 + 브라우저 PiP 존재 |
| P5 끝나면 다음 할 일 하나 제안 | Amershi G12 (맥락 기반 제안) | `finish` 뒤 후속 지시 입력만 |
| P6 로그인·키 없음 | 1.1 "API 키는 절대 못하지" | ChatGPT 구독 로그인 존재 (Codex 기기 코드) |

### 4.1 질문 공세 금지 (우리 사용자 데이터)

AIdol 사용자 인터뷰 재분석 (2026-02~10, 11명 15회)에서 연습생 채팅의 "질문 공세·GPT 말투" 앞에서 6명이 이탈했다. 단계별로 묻는 것과 질문을 퍼붓는 것은 다르다. 규칙:

- 한 작업당 질문 최대 3개. 넘으면 합리적 기본값으로 진행하고 미리보기에서 바꾸게 한다.
- 모든 질문에 선택지 2~4개 + "직접 입력". 열린 질문 금지.
- 질문 전에 "왜 묻는지" 한 줄. 예: "표 머리글을 알아야 같은 형식으로 채울 수 있어요."

## 5. 사용자 흐름 (첫 실행 1분)

### 5.1 첫 대화 세팅 (3문답, 건너뛰기 가능)

1. "주로 어떤 일을 하세요?" 선택지: 학생 · 직장인 · 아르바이트 · 자영업 · 은퇴·가정 · 기타
2. "요즘 반복해서 하는 일이 있나요?" 선택지는 1번 답에 따라 달라진다. 예: 아르바이트 → 엑셀 정리 · 재고 사진 정리 · 근무표 · 없음
3. "주로 폰이에요, 컴퓨터예요?" → 웹/앱 안내 분기

답은 `SettingsStore`에 저장하고 시스템 프롬프트에 넣는다. 이후 할 일 카드 순서가 이 답으로 정렬된다.

### 5.2 할 일 고르기

홈 = 카드 그리드. 각 카드는 동사로 시작하는 한 줄. "엑셀 표 채우기" · "사진 속 글자 표로 옮기기" · "성경 구절 쉽게 풀기" · "자기소개서 고치기" · "증명사진 배경 바꾸기" · "쿠팡에서 제일 싼 거 찾기" · "안 읽은 메일 요약". 카드마다 "할 수 있는 것 · 못 하는 것" 한 줄씩 (Amershi G1·G2).

빈 입력창은 카드 아래 접힌 상태로만 둔다. "다른 일이 있어요" 를 누르면 열린다.

### 5.3 단계 질문 → 프롬프트 미리보기

카드 선택 → 4.1 규칙으로 질문 최대 3개 → 에이전트가 프롬프트를 작성해 카드로 보여준다.

```
이렇게 시킬게요

"첨부한 엑셀의 '품목' 열을 보고 '카테고리' 열을 채워줘.
 카테고리는 식품·생활·전자 셋 중 하나.
 확신이 없는 행은 비워 두고 맨 아래에 목록으로 알려줘."

[이대로 실행]  [고치기]  [복사]
```

사용자가 "고치기"로 문장을 바꿀 수 있다. "복사"는 ChatGPT·Claude 앱에 그대로 붙여 넣는 사람을 위한 것이다. 이 카드가 교육을 대신한다. 보고 따라 쓰게 된다.

### 5.4 실행 관찰

현 `task_screen.dart` 로그 + 브라우저 PiP 유지. 로그 문장을 사용자 언어로 바꾼다. "open_url coupang.com" 이 아니라 "쿠팡 열기". 각 단계에 체크 표시. 승인 카드·결제 넘기기·도움 요청은 현 구조 그대로.

### 5.5 결과와 다음

`finish` 결과 아래 다음 할 일 카드 하나. 예: 엑셀 채우기 뒤 → "같은 파일로 매주 할까요? 월요일에 알려드릴게요" (알림은 P2).

## 6. 기능 요구사항

| ID | 요구사항 | 우선순위 | 비고 |
|---|---|---|---|
| F1 | 첫 실행 3문답 세팅, 건너뛰기, 설정에서 재실행 | P0 | `SettingsStore` 확장 |
| F2 | 할 일 카드 카탈로그 (JSON, 앱·서버 공용) | P0 | `services.json` 과 같은 방식으로 `tasks.json` |
| F3 | 카드별 질문 흐름 (최대 3, 선택지 필수) | P0 | 카탈로그에 질문 정의. LLM 이 즉석에서 만들지 않음 |
| F4 | 프롬프트 미리보기 카드 (실행·고치기·복사) | P0 | 실행 전 반드시 거침 |
| F5 | 로그 문장 사용자 언어화 | P0 | 도구 이름 → 한국어 동사 매핑 |
| F6 | 브라우저 없는 작업 지원 (파일·텍스트·사진 입력) | P0 | 엑셀·사진·텍스트 붙여넣기. 현 앱은 브라우저·Gmail 만 |
| F7 | 결과 뒤 다음 할 일 제안 1개 | P1 | 카탈로그의 `next` 필드 |
| F8 | 웹 버전 (Flutter web + 서버 모드) | P1 | 어머니는 컴퓨터일 가능성. 헤드리스 웹뷰는 모바일 전용이라 웹은 서버 모드 필수 |
| F9 | 로그인 경로 단순화 (8장) | P0 | 일반 사용자 경로에서 API 키·모델 선택 제거 |
| F10 | 반복 작업 알림 | P2 | |

## 7. 플랫폼

- 모바일 앱 (현 Flutter) 유지.
- 웹 추가. 브라우저 조작은 서버 모드(`server/`)로만 가능하므로 웹 버전은 서버 모드 전용.
- 파일 기반 작업(F6)은 앱·웹 모두 LLM 직접 호출. 브라우저 불필요.

## 8. 로그인과 비용 (정책 제약, 2026-10-21 확인)

대표 요청: "API 키 입력이나 모델 선택은 다 치워. Claude 구독 있으면 하는 방법 없을까? 오픈클로처럼."

확인 결과 Claude 구독은 안 된다.

| 공급자 | 서드파티 앱에서 구독 사용 | 출처 |
|---|---|---|
| Anthropic (Claude Pro·Max) | 금지. "Anthropic does not permit third-party developers to offer Claude.ai login into their own applications, or to route requests through Free, Pro, or Max plan credentials on behalf of their users." 사전 승인 예외만 | code.claude.com/docs/en/legal-and-compliance (2026-10-21 열람) |
| OpenAI (ChatGPT Plus·Pro) | 허용. 2026-09-29 DevDay 공식 출시 "Sign in with ChatGPT". 개인 프로젝트·오픈소스 가능, 호스팅·유료 앱은 waitlist | developers.openai.com/siwc |

따라서:

1. 기본 경로 = Sign in with ChatGPT 공식 플로우(PKCE)로 이전. 현 `chatgpt_auth.dart`는 Codex 비공식 클라이언트 ID를 빌려 쓰는 기기 코드 방식이라 교체 대상.
2. 구독이 없는 사용자(어머니 페르소나) = 운영자 서버 키로 실행. 비용은 운영자 부담. 저가 모델(Gemini Flash 급) 기본, 월 한도 설정. 이 경로가 열리면 비용 리스크가 생기므로 9.1 검증 전까지는 가족 한정.
3. Claude 구독 사용자 = 지원 안 함. 요청이 오면 "Claude API 키" 를 설정 깊은 곳에만 둔다 (일반 경로 노출 금지).

## 9. 검증과 성공 기준

### 9.1 만들기 전 검증 (가족 3명, Mom Test)

종이·피그마 프로토타입으로 5장 흐름을 보여주기 전에, 먼저 지난주에 실제로 한 일을 묻는다.

- "지난주에 컴퓨터나 폰으로 제일 귀찮았던 일이 뭐였어?"
- "그거 어떻게 했어? 얼마나 걸렸어?"
- "AI 열어본 적 있어? 그때 뭐 하려고 했고 왜 닫았어?"

의견("좋을 것 같아")은 세지 않는다. 지난 행동과 약속만 센다. 기준은 AIdol 인터뷰 재분석에서 쓴 무게표와 같다.

프로토타입을 보여준 뒤 측정: 도움 없이 카드 선택 → 질문 답 → 미리보기 → "실행" 까지 가는가. 막힌 지점을 시각 단위로 기록.

### 9.2 성공 기준 (첫 버전)

| 지표 | 기준 |
|---|---|
| 도움 없이 첫 작업 완료 | 가족 3명 중 2명 |
| 미리보기에서 "고치기" 사용 | 1명 이상 (프롬프트를 읽었다는 신호) |
| 1주 뒤 자발적 재사용 | 1명 이상 (약속이 아니라 행동) |
| 질문 단계 이탈 | 0명 |

### 9.3 명시적 가설

- H1 비사용자는 AI 교육을 원하지 않는다. 자기 일이 끝나길 원한다. (대표 질문 "AI 교육을 다들 원하긴 할까?" 에 대한 답. 반증되면 교육 쪽으로 축을 옮긴다)
- H2 프롬프트 미리보기를 본 사용자는 두 번째 작업에서 "고치기" 또는 직접 입력을 쓴다. (학습이 부산물로 일어난다는 가설)
- H3 질문 3개 이내면 이탈하지 않는다. (AIdol 반증 사례의 경계 찾기)

## 10. 리스크와 열린 질문

| 리스크 | 대응 |
|---|---|
| 질문 단계가 "질문 공세"로 느껴져 이탈 (AIdol 사례) | 4.1 규칙. 검증에서 H3 측정 |
| 운영자 키 비용 | 가족 한정 · 월 한도 · 저가 모델 |
| Sign in with ChatGPT 호스팅 앱 자격 미승인 | 개인 프로젝트 자격으로 시작. 상용화 시 waitlist |
| 단계별 명확화 질문의 초보자 대상 HCI 실험 근거 부재 | ML 쪽 시뮬레이션 근거(STaR-GATE 등)만 있음. 우리 검증이 1차 근거가 된다 |
| 미리보기 카드를 읽지 않고 "실행"만 누름 | H2 로 측정. 실패하면 미리보기 문장 길이 절반으로 |

열린 질문:

1. 파일 입력(F6)을 폰 사진으로 받을지 파일 선택으로 받을지. 어머니 페르소나는 사진일 가능성.
2. 카드 카탈로그 첫 버전 개수. 페르소나당 3개, 총 9개로 시작할지.
3. 웹 버전을 처음부터 할지, 앱 검증 뒤 할지.

## 11. 참고문헌 (원문 확인분)

1. Zamfirescu-Pereira, Wong, Hartmann, Yang. Why Johnny Can't Prompt: How Non-AI Experts Try (and Fail) to Design LLM Prompts. CHI 2023. https://doi.org/10.1145/3544548.3581388
2. Subramonyam, Pea, Pondoc, Agrawala, Seifert. Bridging the Gulf of Envisioning: Cognitive Challenges in Prompt Based Interactions with LLMs. CHI 2024. https://doi.org/10.1145/3613904.3642754
3. Hutchins, Hollan, Norman. Direct Manipulation Interfaces. Human-Computer Interaction 1(4), 1985. https://doi.org/10.1207/s15327051hci0104_2
4. Carroll, Rosson. Paradox of the Active User. In Interfacing Thought, MIT Press, 1987. https://dl.acm.org/doi/10.5555/28446.28451
5. Carroll, Carrithers. Training Wheels in a User Interface. CACM 27(8), 1984. https://doi.org/10.1145/358198.358218
6. Amershi et al. Guidelines for Human-AI Interaction. CHI 2019. https://doi.org/10.1145/3290605.3300233
7. Horvitz. Principles of Mixed-Initiative User Interfaces. CHI 1999. https://doi.org/10.1145/302979.303030
8. Tankelevitch et al. The Metacognitive Demands and Opportunities of Generative AI. CHI 2024. https://doi.org/10.1145/3613904.3642902
9. Ma et al. Beyond ChatBots: ExploreLLM for Structured Thoughts and Personalized Model Responses. CHI EA 2024. https://doi.org/10.1145/3613905.3636301
10. Wu, Terry, Cai. AI Chains: Transparent and Controllable Human-AI Interaction by Chaining Large Language Model Prompts. CHI 2022. https://doi.org/10.1145/3491102.3517582
11. Dang, Mecke, Lehmann, Goller, Buschek. How to Prompt? Opportunities and Challenges of Zero- and Few-Shot Learning for Human-AI Interaction in Creative Applications of Generative Models. GenAICHI @ CHI 2022. arXiv:2209.01390
12. Shneiderman. Direct Manipulation: A Step Beyond Programming Languages. IEEE Computer 16(8), 1983. https://doi.org/10.1109/MC.1983.1654471 · Shneiderman, Maes. Direct manipulation vs. interface agents. interactions 4(6), 1997. https://doi.org/10.1145/267505.267514
13. Kim, Lee, Kim, Park, Kim. Understanding Users' Dissatisfaction with ChatGPT Responses. IUI 2024. https://doi.org/10.1145/3640543.3645148
14. Wattenberger. Why Chatbots Are Not the Future. 2023. https://wattenberger.com/thoughts/boo-chatbots
15. Andukuri, Fränken, Gerstenberg, Goodman. STaR-GATE: Teaching Language Models to Ask Clarifying Questions. COLM 2024. arXiv:2403.19154
16. Kotturi, Anderson, Ford, Skirpan, Bigham. Deconstructing the Veneer of Simplicity: Co-Designing Introductory Generative AI Workshops with Local Entrepreneurs. CHI 2024. https://doi.org/10.1145/3613904.3642191
17. Gautam, Bhatia, Chilana. "I Just Need GPT to Refine My Prompts": Rethinking Onboarding and Help-Seeking with Generative 3D Modelling Tools. CHI 2026. https://doi.org/10.1145/3772318.3791124
18. Puppart, Aru. A Brief AI Literacy Intervention Does Not Significantly Reduce Over-Reliance and Increases Under-Reliance on ChatGPT. 2025. arXiv:2503.10556
19. Pew Research. Why don't some people use chatbots? 2026-10-09. https://www.pewresearch.org/short-reads/2026/10/09/why-dont-some-people-use-chatbots/
20. Pew Research. Majorities of adults under 50 now use ChatGPT. 2026-06-17. https://www.pewresearch.org/chart/majorities-of-adults-under-50-now-use-chatgpt/
21. 방송미디어통신위원회·KISDI. 2025 지능정보사회 이용자 패널조사. 2026-05-28 발표. (아이티데일리 2026-05-29 보도 https://www.itdaily.kr/news/articleView.html?idxno=239577)
22. 오주현. AI 포용 관점에서 본 생성형 AI 이용 격차: 인지, 이용, 활용. KISDI STAT Report 26-04, 2026-04-15.
23. 과학기술정보통신부·NIA. 2025 인터넷이용실태조사. 2026-03-31 발표.
24. Reuters Institute. Generative AI and News Report 2025. 2025-10-07.
25. Anthropic. Claude Code Legal and compliance. https://code.claude.com/docs/en/legal-and-compliance (2026-10-21 열람)
26. OpenAI. Sign in with ChatGPT. https://developers.openai.com/siwc (2026-10-21 열람)
