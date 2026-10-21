# 안내형 에이전트 업그레이드 · Claude Code 프롬프트

아래 블록을 그대로 Claude Code 에 붙여 넣는다. 레포 루트(`Lee-Soyeon/AI-Agent`)에서 실행한다. 기획 근거는 `docs/guided-agent-prd.md`, 장표는 `docs/guided-agent-deck.html`.

```text
먼저 docs/guided-agent-prd.md 를 끝까지 읽어라. 이 작업은 그 PRD 의 F1~F6, F9 를 구현하는 것이다.
README.md, lib/ui/guide_screen.dart, lib/ui/task_screen.dart, lib/agent/prompts.dart,
lib/agent/agent_tools.dart, lib/core/settings_store.dart, lib/openai/chatgpt_auth.dart,
server/app/services.json 을 읽고 현재 구조를 파악한 뒤 시작하라.

## 목표

AI 를 써본 적 없는 사람이 앱을 열고 도움 없이 자기 일 하나를 끝낸다.
빈 입력창을 첫 화면에서 없애고, 사용자는 적는 대신 고르고 답한다.
에이전트가 프롬프트를 대신 써서 보여주고 "이대로 실행할까요?" 를 묻는다.

## 지킬 것

- 기존 안전 규칙(lib/agent/safety.dart, server/app/safety.py)은 한 줄도 약화하지 않는다.
  결제 넘기기(handoff_payment), 승인 카드(request_approval), 사용자 도움 요청(request_user_help)은 그대로 쓴다.
- 기존 LLM 공급자·브라우저·Gmail·서버 모드 코드는 삭제하지 않는다. 앞단(UI 와 프롬프트)만 바꾼다.
- 카탈로그는 JSON 한 파일로 두고 앱(asset)과 서버가 함께 읽는다. services.json 과 같은 방식.
- 질문은 LLM 이 즉석에서 만들지 않는다. 카탈로그에 정의된 질문만 쓴다. 한 작업당 최대 3개, 모든 질문에 선택지 2~4개 + "직접 입력".
- 새 UI 문구는 전부 한국어. 도구 이름(open_url 등)을 사용자에게 노출하지 않는다.
- 테스트를 먼저 쓴다. 기존 test/ 폴더 스타일을 따른다. flutter test 가 통과해야 끝이다.
- 모르면 추측하지 말고 PRD 의 해당 절을 인용해 질문하라.

## 작업 순서 (각 단계마다 커밋)

1. 할 일 카탈로그 `server/app/tasks.json` 신설 + 앱 asset 등록.
   스키마:
   {
     "id": "excel_fill",
     "title": "엑셀 표 채우기",
     "can": "비어 있는 열을 다른 열을 보고 채움",
     "cannot": "수식·매크로·서식은 못 바꿈",
     "personas": ["parttime", "office"],
     "inputs": ["file"],                 // file | photo | text | none
     "engine": "llm",                    // llm | browser | gmail
     "questions": [
       { "id": "column", "why": "같은 형식으로 채우려면 머리글이 필요해요", "text": "어느 열을 채울까요?",
         "options": ["파일의 열 이름을 읽어서 보여줌"], "allow_free": true },
       { "id": "values", "why": "", "text": "들어갈 값의 종류는?",
         "options": ["파일에 있는 것 그대로"], "allow_free": true }
     ],
     "prompt_template": "첨부한 엑셀의 '{source}' 열을 보고 '{column}' 열을 채워줘. 값은 {values} 중 하나. 확신이 없는 행은 비워 두고 맨 아래에 목록으로 알려줘.",
     "next": "excel_weekly"
   }
   첫 버전 카드 9개: 페르소나(가정·은퇴 / 아르바이트 / 취업 준비)당 3개.
   - 가정·은퇴: 성경 구절 쉽게 풀기(text) · 묵상 질문 만들기(text) · 모임 안내문 쓰기(text)
   - 아르바이트: 엑셀 표 채우기(file) · 사진 속 글자 표로 옮기기(photo) · 근무표 정리(text)
   - 취업 준비: 자기소개서 고치기(text) · 채용 공고 요약(text 또는 browser) · 쿠팡 최저가 찾기(browser, 기존 흐름 재사용)
   server/tests/test_catalog.py 스타일로 스키마 검증 테스트를 추가한다.

2. 첫 실행 3문답 (PRD 5.1).
   lib/core/settings_store.dart 에 persona, routine, device 필드 추가. 앱 첫 실행 시 전체 화면으로 3문답.
   건너뛰기 가능. 설정 화면에 "다시 설정" 항목. 답은 buildSystemPrompt 에 "## 사용자" 절로 들어간다.

3. 홈 화면 교체 (PRD 5.2).
   lib/ui/guide_screen.dart 의 4단계 체크리스트와 taskExamples 9개를 제거하고 카드 그리드로 바꾼다.
   카드 순서는 persona 일치 우선. 카드마다 can/cannot 한 줄. 빈 입력창은 "다른 일이 있어요" 를 누를 때만 펼친다.
   모델 설정·로그인 미완료 상태는 카드를 눌렀을 때 그 작업에 필요한 것만 한 번 안내한다 (전체 체크리스트 금지).

4. 질문 흐름 + 프롬프트 미리보기 (PRD 5.3, 4.1).
   lib/agent/ 에 TaskIntake 를 추가한다: 카드 → questions 를 순서대로 → prompt_template 치환 → 미리보기 카드.
   미리보기 카드는 lib/ui/task_screen.dart 의 _ApprovalCard 와 같은 시각 문법으로 만들되 버튼은 "이대로 실행" "고치기" "복사" 셋.
   "고치기" 는 문장을 편집 가능한 텍스트 필드로 바꾼다. "실행" 은 최종 문장을 AgentRunner 에 사용자 메시지로 넘긴다.
   질문 4개 이상인 카탈로그 항목은 로드 시 assert 로 막는다.

5. 브라우저 없는 작업 (PRD F6).
   engine 이 "llm" 인 카드는 브라우저 도구 없이 LLM 직접 호출로 처리한다.
   입력 종류별로 file_picker(xlsx·csv → 텍스트 표로 변환), image_picker(사진 → 비전 입력), 텍스트 붙여넣기를 받는다.
   xlsx 파싱은 순수 Dart 패키지를 쓰고 서버 의존을 만들지 않는다. 결과는 채팅에 표로 보여주고 "파일로 저장" 을 제공한다.

6. 로그 문장 한국어화 (PRD 5.4).
   lib/agent/agent_models.dart 의 로그 생성 지점에서 도구 이름 → 한국어 동사 매핑 테이블을 둔다.
   open_url → "{도메인} 열기", click → "{요소 텍스트} 누르기", type_text → "{필드} 입력", scroll → "아래로 내리기",
   gmail_search → "메일 찾기", gmail_read → "메일 읽기", request_approval → "승인 요청", finish → "완료".
   각 단계 완료 시 체크 표시. 기존 PiP 는 그대로.

7. 로그인 경로 단순화 (PRD 8).
   설정 화면에서 API 키 입력과 모델 선택을 "고급" 섹션으로 접는다. 기본 화면에는 "ChatGPT 로 로그인" 과 "계정 없이 시작(서버)" 둘만 둔다.
   "계정 없이 시작" 은 서버 모드로 연결하고 서버가 운영자 키로 실행한다. 서버 .env 에 월 토큰 한도 변수를 추가하고 초과 시 작업 생성을 거부한다.
   lib/openai/chatgpt_auth.dart 의 Codex 기기 코드 로그인은 유지하되 파일 상단 주석에 "공식 Sign in with ChatGPT(PKCE) 로 교체 예정, developers.openai.com/siwc" 를 적는다.
   PKCE 교체 자체는 이번 범위 밖이다. Claude 구독 로그인은 추가하지 않는다 (Anthropic 정책, PRD 8).

8. 결과 뒤 다음 할 일 (PRD 5.5). finish 결과 아래 카탈로그 next 카드를 하나 보여준다. 없으면 생략.

## 끝낼 때

- README.md 의 "동작 흐름" 절을 새 흐름(3문답 → 카드 → 질문 → 미리보기 → 실행)으로 고친다.
- docs/guided-agent-prd.md 의 F1~F9 표에 구현 상태 열을 추가해 채운다.
- flutter test 와 server pytest 결과를 그대로 보고한다. 실패가 있으면 숨기지 말고 적어라.
```

## 붙여 넣기 전에 정할 것

1. 운영자 서버 키로 쓸 모델과 월 한도. PRD 8 은 저가 모델·가족 한정을 전제로 한다.
2. 카드 9개의 문구. 검증(PRD 9.1) 뒤 지난주 실제 한 일로 교체하는 것이 맞다. 검증 전에 구현하면 카드 문구는 자리 표시자다.
3. 웹 버전(F8)은 이 프롬프트에 없다. 앱 검증 뒤 별도 프롬프트.
