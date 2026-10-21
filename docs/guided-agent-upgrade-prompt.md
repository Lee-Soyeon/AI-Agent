# 안내형 에이전트 업그레이드 · Claude Code 프롬프트

아래 블록을 그대로 Claude Code 에 붙여 넣는다. 레포 루트(`Lee-Soyeon/AI-Agent`)에서 실행한다. 기획 근거는 `docs/guided-agent-prd.md`, 장표는 `docs/guided-agent-deck.html`.

```text
먼저 docs/guided-agent-prd.md 를 끝까지 읽어라. 이 작업은 그 PRD 의 F0~F6, F8, F9 를 구현하는 것이다.
플랫폼은 PRD 7장대로 Flutter web, 폰 폭(최대 430px) 레이아웃만이다. 네이티브 빌드는 깨뜨리지 않되 이번에 손대지 않는다.
UI 문법은 PRD 4.1(토스 입력 폼 방식), 홈은 PRD 4.3(내 것부터 넣기 + 갤러리), 즉석 UI 는 PRD 4.4(show_ui)를 따른다. 채팅 UI 로 만들지 않는다.
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
- 레시피 9개의 단계 화면은 카탈로그 steps 로 미리 정한다. 한 작업당 최대 3개, 모든 칩 화면에 칩 2~6개 + "직접 입력".
- show_ui 는 PRD 4.4 의 부품 8종만 그린다. LLM 이 HTML·마크다운·자유 위젯을 보내면 거부하고 text_block 으로 떨어뜨린다.
- 웹에는 API 키를 두지 않는다. 모든 LLM 호출은 server/ 를 거친다.
- 새 UI 문구는 전부 한국어. 도구 이름(open_url 등)을 사용자에게 노출하지 않는다.
- 테스트를 먼저 쓴다. 기존 test/ 폴더 스타일을 따른다. flutter test 가 통과해야 끝이다.
- 모르면 추측하지 말고 PRD 의 해당 절을 인용해 질문하라.

## 작업 순서 (각 단계마다 커밋)

0. show_ui 도구 (PRD 4.4, F0).
   server/app/tools.py 와 lib/agent/agent_tools.dart 에 show_ui 를 추가한다. 인자는 부품 트리 JSON 하나.
   부품 8종의 JSON Schema 를 server/app/ui_schema.json 한 파일로 두고 앱 asset 으로도 등록한다:
   chips(options[], allow_free) · keyword(placeholder) · file_button(label, accept) · table(headers[], rows[][]) ·
   before_after(before, after, caption) · checklist(items[], done[]) · confirm(sentence) · text_block(text).
   lib/ui/ui_renderer.dart 가 JSON → 위젯. 스키마 검증 실패는 text_block 으로 떨어뜨린다.
   기존 ask_user 는 show_ui(chips) 의 별칭으로 남긴다. 서버 tests 에 스키마 검증 테스트, 앱 test 에 렌더러 골든 테스트.

1. 레시피 카탈로그 `server/app/tasks.json` 신설 + 앱 asset 등록.
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
     "next": "excel_weekly",
     "gallery": { "before": "assets/gallery/excel_before.png", "after": "assets/gallery/excel_after.png", "line": "빈 열을 다른 열 보고 채움" }
   }
   첫 버전 카드 9개: 페르소나(가정·은퇴 / 아르바이트 / 취업 준비)당 3개.
   - 가정·은퇴: 성경 구절 쉽게 풀기(text) · 묵상 질문 만들기(text) · 모임 안내문 쓰기(text)
   - 아르바이트: 엑셀 표 채우기(file) · 사진 속 글자 표로 옮기기(photo) · 근무표 정리(text)
   - 취업 준비: 자기소개서 고치기(text) · 채용 공고 요약(text 또는 browser) · 쿠팡 최저가 찾기(browser, 기존 흐름 재사용)
   server/tests/test_catalog.py 스타일로 스키마 검증 테스트를 추가한다.

2. 첫 실행 3문답 (PRD 5.1).
   lib/core/settings_store.dart 에 persona, routine, device 필드 추가. 앱 첫 실행 시 전체 화면으로 3문답.
   건너뛰기 가능. 설정 화면에 "다시 설정" 항목. 답은 buildSystemPrompt 에 "## 사용자" 절로 들어간다.

3. 홈 화면 교체 (PRD 4.3, 5.2). 묻지 않는다. 보여준다.
   lib/ui/guide_screen.dart 의 4단계 체크리스트와 taskExamples 9개를 제거한다. 새 홈은 위에서 아래로:
   (가) 오늘의 하나: 갤러리에서 날짜 기준으로 1개 순환, before/after 이미지 한 장과 한 줄.
   (나) 내 것부터 넣기: 큰 버튼 셋 "사진 찍기" "파일 올리기" "글 붙여넣기". 웹이므로 image_picker/file_picker 의 web 구현을 쓴다.
       넣는 즉시 스켈레톤 칩 3개를 보여주고, 서버 POST /intake 에 내용(사진은 base64, 엑셀은 머리글과 앞 20행, 글은 그대로)을 보낸다.
       서버는 LLM 에 "이걸로 할 수 있는 일 3개를 chips 부품으로" 요청해 show_ui JSON 을 돌려준다. 3초 넘으면 레시피 기본 칩으로 대체.
   (다) 이런 것도 돼요: 갤러리 그리드. 카드 = before/after 이미지 + 한 줄. persona 일치 우선 정렬. 탭하면 그 레시피의 StepScreen.
   (라) 맨 아래 "다른 일이 있어요" 접힌 키워드 입력 하나. 펼치면 한 줄 입력 → 서버가 show_ui 로 단계 화면을 즉석 생성.
   로그인 미완료 상태는 실행 직전에 그 작업에 필요한 것만 한 번 안내한다 (전체 체크리스트 금지).

4. 단계 화면 + 확인 화면 (PRD 4.1, 5.3). 채팅 UI 가 아니다. 토스 입력 폼 문법이다.
   lib/agent/ 에 TaskIntake(상태 머신: 레시피 → steps 순서대로 → prompt_template 치환 → 확인)를 추가하고
   lib/ui/ 에 StepScreen 과 ConfirmScreen 을 만든다.
   StepScreen: 질문 한 줄이 제목(큰 글씨) · 아래 "왜 묻는지" 한 줄 · 답은 ChoiceChip 2~6개, 탭하면 자동으로 다음 ·
   칩으로 못 답하면 키워드 입력창 하나(autofocus, 플레이스홀더에 예시, 한 줄) · "직접 입력" 칩은 항상 마지막 ·
   하단 고정 "다음" 버튼 · 상단 뒤로 화살표와 진행 점 · 상단 보조 줄에 지금까지 조립된 문장.
   kind 가 file/photo 인 단계는 큰 버튼 하나. 올리면 다음 단계의 칩을 파일 내용(열 머리글 등)으로 채운다.
   ConfirmScreen: 전체 문장 + 제목 "이렇게 시킬까요?" + 버튼 "실행" "고치기" "복사". "고치기" 는 편집 가능한 텍스트 필드.
   "실행" 은 최종 문장을 AgentRunner(서버 모드)에 사용자 메시지로 넘긴다.
   단계 4개 이상인 카탈로그 항목은 로드 시 assert 로 막는다. 모든 문구는 한 줄. 문단 글 금지.

5. 브라우저 없는 작업 (PRD F6).
   engine 이 "llm" 인 레시피는 브라우저 도구 없이 서버가 LLM 을 직접 호출한다.
   입력 종류별로 file_picker(xlsx·csv → 머리글과 행을 텍스트 표로), image_picker(사진 → 비전 입력), 텍스트 붙여넣기를 받는다.
   xlsx 파싱은 순수 Dart 패키지(web 지원 확인)를 쓴다. 결과는 show_ui 의 table 또는 before_after 로 보여주고 "파일로 저장" 을 제공한다.

6. 로그 문장 한국어화 (PRD 5.4).
   lib/agent/agent_models.dart 의 로그 생성 지점에서 도구 이름 → 한국어 동사 매핑 테이블을 둔다.
   open_url → "{도메인} 열기", click → "{요소 텍스트} 누르기", type_text → "{필드} 입력", scroll → "아래로 내리기",
   gmail_search → "메일 찾기", gmail_read → "메일 읽기", request_approval → "승인 요청", finish → "완료".
   각 단계 완료 시 체크 표시. 기존 PiP 는 그대로.

7. 로그인 경로 단순화 (PRD 8). 웹 첫 버전은 "계정 없이 시작" 하나만 보인다.
   설정 화면에서 API 키 입력과 모델 선택을 "고급" 섹션으로 접는다. 웹은 항상 서버 모드이고 서버가 운영자 키(Gemini 무료 등급부터)로 실행한다.
   서버 .env 에 일일·월 토큰 한도 변수를 추가하고 초과 시 작업 생성을 거부하며 앱은 "오늘은 여기까지" 화면을 보여준다.
   "ChatGPT 로 로그인" 은 네이티브 앱 단계에서 켠다.
   lib/openai/chatgpt_auth.dart 의 Codex 기기 코드 로그인은 유지하되 파일 상단 주석에 "공식 Sign in with ChatGPT(PKCE) 로 교체 예정, developers.openai.com/siwc" 를 적는다.
   PKCE 교체 자체는 이번 범위 밖이다. Claude 구독 로그인은 추가하지 않는다 (Anthropic 정책, PRD 8).

8. 결과 뒤 다음 할 일 (PRD 5.5). finish 결과 아래 카탈로그 next 카드를 하나 보여준다. 없으면 생략.

9. 모바일 웹 빌드와 배포 (PRD 7, F8).
   flutter build web 이 통과해야 한다. 데스크톱 폭에서는 가운데 430px 컬럼으로 보여준다(바깥은 --soft 배경).
   build/web 을 Vercel 정적 배포로 올릴 수 있게 vercel.json(outputDirectory: build/web, SPA rewrite)을 추가한다. 배포 명령은 실행하지 말고 README 에 적는다.

## 끝낼 때

- README.md 의 "동작 흐름" 절을 새 흐름(3문답 → 카드 → 질문 → 미리보기 → 실행)으로 고친다.
- docs/guided-agent-prd.md 의 F1~F9 표에 구현 상태 열을 추가해 채운다.
- flutter test 와 server pytest 결과를 그대로 보고한다. 실패가 있으면 숨기지 말고 적어라.
```

## 붙여 넣기 전에 정할 것

1. 운영자 서버 키로 쓸 모델과 월 한도. PRD 8 은 저가 모델·가족 한정을 전제로 한다.
2. 카드 9개의 문구. 검증(PRD 9.1) 뒤 지난주 실제 한 일로 교체하는 것이 맞다. 검증 전에 구현하면 카드 문구는 자리 표시자다.
3. 갤러리 before/after 이미지 6쌍. 없으면 회색 자리 표시자로 두고 README 에 목록을 남긴다.
4. 서버 배포 위치. 웹이 호출할 server/ 가 어디에 떠 있어야 하는지(현재 server/README.md 기준).
