# AI Agent (Flutter)

OpenAI · Claude · Gemini 중 원하는 LLM으로 **웹사이트를 대신 조작하는 AI 에이전트 앱**입니다.

- **로그인만 사용자가 합니다.**
  - 쿠팡: 앱 안 브라우저로 로그인하면 창이 자동으로 닫히고, 이후 에이전트가 화면 없는 웹뷰(헤드리스)로 조작합니다.
  - Gmail: 공식 **Google 로그인**으로 계정을 연결하면, 에이전트가 **Gmail API**로 메일을 검색·읽기·전송합니다.
    보낸 메일로 **내 말투를 학습**해 인사말·호칭·어미·서명까지 내가 쓴 것처럼 답장합니다.
- **나머지는 에이전트가 알아서 처리합니다.** 상품 검색, 장바구니 담기, 메일 요약, 답장 작성 등.
- **결제와 메일 전송은 반드시 사용자 승인 후에만 합니다.** 이 규칙은 프롬프트뿐 아니라 코드에서도 강제됩니다.

## 실행 위치: 이 폰 / 서버

| | 이 폰 | 서버 (백그라운드) |
| --- | --- | --- |
| 브라우저 | 폰 안의 보이지 않는 웹뷰 | 서버의 실제 크롬 ([`server/`](server/README.md)) |
| 앱을 꺼도 계속? | ❌ 멈출 수 있음 | ✅ 서버에서 계속, 앱을 열면 이어서 표시 |
| 다룰 수 있는 서비스 | 쿠팡(웹) + Gmail(API) | **어떤 웹 서비스든** |
| 로그인 | 앱 안 브라우저 | 앱의 **서버 브라우저** 화면(실시간 화면 + 탭/입력 전달)에서 한 번 |
| LLM 키 | 폰 (API 키 또는 ChatGPT 구독) | 서버 환경 변수 |

설정 → **실행 위치: 서버** → 서버 주소와 토큰 입력 → **연결 테스트**.
서버 설치·배포는 [server/README.md](server/README.md) 를 보세요.

```
[앱] 작업 입력 ──POST /tasks──▶ [서버] AgentRunner ──▶ 크롬(Playwright, 로그인 프로필 유지)
[앱] 1.5초마다 상태·로그·스크린샷 ◀──GET /tasks/{id}──┘
[앱] 승인 카드 / 질문 ──POST approval·answer──▶ 멈춰 있던 작업 재개
[앱] 서버 브라우저 화면 ◀══WS /live══▶ 캡차·인증번호·결제 비밀번호를 사용자가 직접 입력
```

## 동작 흐름

```
[홈] 쿠팡 로그인 ──▶ 보이는 InAppWebView (사용자가 로그인) ──▶ 로그인 URL 감지 시 자동으로 닫힘
                                            │  (쿠키 공유)
[홈] "생수 12개 담고 결제 승인 받아줘" ──▶ AgentRunner ──▶ HeadlessInAppWebView (화면 없음)
                                            │
             LLM ◀── 페이지 스냅샷(텍스트 + 요소 id) ── read_page / open_url / click / type_text / scroll
                                            │
             gmail_search / gmail_read ──▶ Gmail API (Google 로그인 토큰)
             gmail_send ──▶ 승인 카드에 받는 사람·제목·본문 표시 → 승인 시 그 내용 그대로 전송
             request_approval ──▶ [작업 화면] 승인 카드 (승인 / 거절 / 수정 요청)
             request_user_help ──▶ 보이는 브라우저 (캡차, 2단계 인증, 결제 비밀번호)
             ask_user ──▶ 선택지 질문
             finish ──▶ 결과 보고 → 이어서 지시 가능 ("두 번째 메일에 답장 써줘")
```

## 지원 서비스 (한국 주요 서비스 109개)

한국인이 많이 쓰는 서비스 109개를 조사해 **브라우저로 되는 90개**(완전 지원 81 + 일부 9)를 지원합니다.
배달의민족·카카오톡·카카오 T 처럼 웹이 없는 앱 전용 서비스와, 은행·송금·본인인증은 지원하지 않습니다.
전체 목록과 선정 방법: [docs/korea-top100-services.md](docs/korea-top100-services.md)

- 앱 홈 → **한국 주요 서비스** 에서 서비스를 골라 로그인해 두면, 에이전트가 그 계정으로 작업합니다.
- 에이전트는 `service_info` 도구로 각 서비스의 시작·로그인·검색 URL 과 사용 팁을 확인합니다.
- 카탈로그는 `server/app/services.json` 한 파일이며 앱(asset)과 서버가 함께 씁니다. 서비스 추가·수정은 이 파일만 고치면 됩니다.

## 폴더 구조

```
server/                           # 서버 모드 (Python · FastAPI · Playwright) — server/README.md
lib/
├── main.dart                     # Provider 구성, 앱 시작
├── llm/                          # LLM 공급자 추상화 (도구 호출 지원)
│   ├── llm_types.dart            #   공통 메시지/도구 타입
│   ├── openai_provider.dart      #   Chat Completions + function calling (API 키)
│   ├── chatgpt_codex_provider.dart #  ChatGPT 구독: Codex 백엔드 Responses API (SSE)
│   ├── anthropic_provider.dart   #   Messages API + tool use
│   └── gemini_provider.dart      #   generateContent + function calling
├── browser/
│   ├── agent_browser.dart        # 헤드리스 웹뷰 제어 (이동/스냅샷/클릭/입력/스크린샷)
│   ├── dom_scripts.dart          # 주입 JS: 보이는 요소에 id 부여, React 호환 입력 등
│   ├── web_settings.dart         # 로그인용·에이전트용 웹뷰 공통 설정(UA, 쿠키)
│   ├── sites.dart                # 웹 자동화 사이트 정의 (쿠팡) — 여기에 새 사이트 추가
│   └── session_store.dart        # 사이트별 로그인 상태, 로그아웃(쿠키 삭제)
├── openai/
│   └── chatgpt_auth.dart         # ChatGPT 구독 로그인 (기기 코드 OAuth, 토큰 갱신)
├── google/
│   ├── google_auth.dart          # Google 로그인 + Gmail 권한(access token) 관리
│   ├── gmail_api.dart            # Gmail REST: 검색, 읽기(HTML→텍스트), 전송(MIME, 답장 스레드)
│   └── writing_style.dart        # 보낸 메일 → 말투 가이드 학습, 인용문 제거, 수신자별 예시
├── agent/
│   ├── agent_runner.dart         # LLM ↔ 도구 실행 루프, 스냅샷 압축, 재시도
│   ├── agent_tools.dart          # LLM 에게 주는 도구 목록
│   ├── safety.dart               # 결제/전송 버튼 승인 강제 (1회용, 10분)
│   ├── prompts.dart              # 시스템 프롬프트
│   ├── agent_models.dart         # 로그, 승인 요청, 질문 모델
│   └── agent_controller.dart     # UI 상태 (ChangeNotifier)
├── remote/
│   └── agent_server_client.dart  # 서버 REST 클라이언트
└── ui/
    ├── home_screen.dart          # 로그인 상태, 작업 입력, 예시
    ├── remote_browser_screen.dart # 서버 브라우저 실시간 화면 (로그인·사용자 도움)
    ├── task_screen.dart          # 실시간 로그, 브라우저 스크린샷, 승인/질문 카드, 후속 지시
    ├── browser_pip.dart          # 작업 화면 위에 떠 있는 브라우저 미니 화면(PiP)·전체 화면 보기
    ├── browser_screen.dart       # 사용자가 직접 조작하는 브라우저
    └── settings_screen.dart      # LLM 선택, API 키, 모델
```

## 실행 방법

```bash
flutter pub get
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=<웹 클라이언트 ID>   # Android
flutter run                                                             # iOS (xcconfig 사용)
flutter test           # LLM 요청 변환, 승인 강제, Gmail API 테스트
AGENT_SERVER_PYTHON=<server 의존성이 설치된 python> flutter test   # 앱↔서버 E2E 포함
```

### Gmail(Google 로그인) 설정 — 한 번만

1. [Google Cloud Console](https://console.cloud.google.com/)에서 프로젝트를 만들고 **Gmail API 사용 설정**.
2. **OAuth 동의 화면**(Google Auth Platform)
   - 사용자 유형: 외부, 게시 상태: **테스트**
   - 범위(Data access): `gmail.readonly`, `gmail.send`
   - **테스트 사용자**에 사용할 Gmail 주소 추가 (테스트 모드에서는 최대 100명, 이 사람들만 로그인 가능)
3. **사용자 인증 정보 → OAuth 클라이언트 ID** 를 만든다.
   - **iOS**: 번들 ID `ai.aioia.aiAgent` → 발급된 클라이언트 ID 와 역방향 ID(`com.googleusercontent.apps.…`)를
     `ios/Flutter/GoogleSignIn.xcconfig` 에 입력
   - **Android**: 패키지 이름 `ai.aioia.ai_agent` + 서명 인증서 SHA-1 (`cd android && ./gradlew signingReport`).
     디버그/릴리스/Play 앱 서명 키마다 SHA-1 을 각각 등록해야 함
   - **웹 애플리케이션**: 하나 만들어 그 ID 를 Android 실행 시 `--dart-define=GOOGLE_SERVER_CLIENT_ID=...` 로 전달
4. 앱 홈에서 **Google 계정 연결** → 계정 선택 → Gmail 권한 허용.

> `gmail.readonly` / `gmail.send` 는 Google 의 **제한된(restricted) 범위**입니다. 테스트 모드(등록한 테스트 사용자)로는 바로 쓸 수 있지만,
> 일반 사용자에게 공개하려면 Google 앱 인증(보안 평가 포함)을 받아야 합니다.

### ChatGPT 구독(Plus/Pro)으로 쓰기

API 키 대신 ChatGPT 구독 사용량으로 에이전트를 돌릴 수 있습니다. OpenClaw · Hermes Agent 와 같은 방식입니다.

1. 설정 → **ChatGPT 구독 (Plus/Pro)** 선택 → **ChatGPT 계정으로 로그인**
2. 표시된 코드를 **복사 후 열기** → Safari 에서 ChatGPT 로그인 → 코드 붙여넣기 → 승인
3. 창이 자동으로 닫히면 완료. 토큰은 Keychain/Keystore 에 저장되고 자동 갱신됩니다.

- 로그인 화면에는 "Codex"가 표시되고, Codex 계열 모델(기본 `gpt-5.5`)만 쓸 수 있습니다.
- 앱은 Codex CLI 로 위장하지 않고 자체 `originator`(`ai_agent_flutter`)로 요청합니다.
- 외부 앱용 공식 "ChatGPT 로그인"이 아직 없어 공개 문서가 없는 방식입니다. OpenAI 정책에 따라 바뀌거나 막힐 수 있습니다.
- **Claude 구독(Pro/Max)은 지원하지 않습니다.** Anthropic 약관상 구독 토큰은 Claude.ai·Claude Code 전용이므로 Claude 는 API 키로 사용하세요.

### 내 메일 말투 학습

홈 → Gmail 카드의 **내 메일 말투** → **보낸 메일로 말투 학습하기**

1. **학습**: 보낸편지함 최근 메일 최대 50통을 읽습니다.
   - 답장에 딸려 있는 상대방 원문(인용문)은 제거해 내가 쓴 부분만 남깁니다.
   - 현재 선택한 LLM이 인사말, 호칭, 존댓말 수준, 문단 구성, 맺음말, 서명, 상대별 차이를 정리한 **말투 가이드**를 만듭니다.
   - 가이드는 기기 보안 저장소에만 저장되고, 화면에서 직접 고칠 수 있습니다.
2. **메일 작성**: 에이전트는 먼저 `gmail_style_examples` 로 **같은 받는 사람에게 예전에 보낸 메일**을 찾아보고, 가이드와 함께 참고해 씁니다.
   - 사람마다 다른 말투도 반영됩니다 (예: 상사에게는 격식, 동료에게는 편하게).
   - 이 확인 없이 `gmail_send` 를 호출하면 **코드에서 한 번 막고** 확인하도록 되돌려 보냅니다.
3. **전송**: 기존과 같이 승인 카드에서 내용을 확인한 뒤에만 보내집니다.

> 학습할 때 보낸 메일 내용이 선택한 LLM 공급자에게 전송됩니다. 앱은 시작 전에 이 점을 안내하고 동의를 받습니다.

### 사용 순서

1. 앱 오른쪽 위 **설정**에서 사용할 LLM을 고르고 API 키를 입력합니다 (또는 ChatGPT 계정으로 로그인).
   - 기본 모델: OpenAI `gpt-4.1`, Claude `claude-sonnet-5`, Gemini `gemini-3.6-flash` (설정에서 변경 가능)
2. 홈에서 **쿠팡 로그인**(인앱 브라우저, 로그인되면 자동으로 닫힘)과 **Google 계정 연결**을 합니다.
3. 할 일을 입력하고 **실행**을 누릅니다. 결제·전송 직전에 승인 카드가 뜹니다.

## 안전장치

| 위험 | 대응 |
| --- | --- |
| LLM이 승인 없이 결제 | `SafetyPolicy`가 클릭 대상 버튼 문구(결제하기, 주문하기, 보내기, Send 등)를 검사해 **승인이 없으면 코드에서 차단**. 승인은 1회용이며 10분 뒤 만료 |
| LLM이 승인 없이 메일 전송 / 승인 후 내용 바꿔치기 | `gmail_send` 도구 자체가 승인 카드를 띄우고, **승인 카드에 보인 받는 사람·제목·본문 그대로만** 전송. 헤더 줄바꿈 제거로 헤더 인젝션(Bcc 추가 등) 차단 |
| Gmail 계정 비밀번호 | 앱을 거치지 않고 Google 공식 로그인 화면에서만 입력. 앱은 access token 만 사용하며 연결 해제 시 권한 철회(disconnect) |
| 이메일·웹페이지 속 악성 지시(프롬프트 인젝션) | 시스템 프롬프트로 무시하도록 지시 + 위 코드 레벨 차단으로 최종 방어 |
| 비밀번호 유출 | 에이전트는 `type=password` 입력창에 입력할 수 없음. 로그인/결제 비밀번호는 항상 사용자가 직접 입력. 앱은 비밀번호를 저장하지 않음 |
| 임의 코드 실행 | LLM 에게 임의 JavaScript 실행 도구를 주지 않음 (정해진 스크립트만 사용) |
| API 키 | `flutter_secure_storage` (Keychain / Keystore) 에 저장 |
| 무한 루프·비용 | 작업당 최대 단계 수 제한, 오래된 페이지 스냅샷은 대화에서 요약해 토큰 절약 |

## 알아둘 제약 사항

- **쿠팡**: 자동화 접근은 쿠팡 이용약관과 봇 탐지 정책의 영향을 받을 수 있습니다. 화면 구조가 바뀌어도 LLM 이 스냅샷을 보고 판단하므로 셀렉터를 하드코딩하지 않았지만, 결제 비밀번호(쿠페이) 입력은 항상 사용자에게 넘깁니다.
- **백그라운드 실행**: 에이전트는 화면에 보이지 않는 웹뷰에서 동작하므로 앱 안에서는 다른 화면을 봐도 계속 진행됩니다. 다만 앱 자체를 내리면 iOS 는 곧 실행을 멈추고, Android 도 절전 정책에 따라 멈출 수 있습니다. 완전한 백그라운드 실행이 필요하면 Android Foreground Service, 알림(승인 요청 푸시) 등을 추가해야 합니다.
- **도움 요청 시 페이지 상태**: 캡차·결제 비밀번호 등으로 사용자에게 넘길 때 같은 URL 을 보이는 브라우저에서 새로 엽니다. URL 에 담기지 않은 화면 상태(예: 결제 팝업)는 다시 열어야 할 수 있습니다.

## 새 사이트 추가

웹 자동화 사이트는 `lib/browser/sites.dart` 에 `SiteConfig` 를 하나 추가하고 `allSites` 에 넣으면 됩니다. 로그인 URL, 시작 URL, 로그인 완료를 판별할 URL 패턴, 에이전트에게 줄 팁만 적으면 홈 화면과 시스템 프롬프트에 자동으로 반영됩니다.
