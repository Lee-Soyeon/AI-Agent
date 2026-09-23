# AI Agent (Flutter)

OpenAI · Claude · Gemini 중 원하는 LLM으로 **웹사이트를 대신 조작하는 AI 에이전트 앱**입니다.

- **로그인만 사용자가 합니다.** 앱 안 브라우저로 쿠팡/Gmail에 로그인하면 창이 자동으로 닫힙니다.
- **나머지는 에이전트가 화면 없이(헤드리스 웹뷰) 처리합니다.** 상품 검색, 장바구니 담기, 메일 읽기·요약·작성 등.
- **결제와 메일 전송은 반드시 사용자 승인 후에만 합니다.** 이 규칙은 프롬프트뿐 아니라 코드에서도 강제됩니다.

## 동작 흐름

```
[홈] 쿠팡/Gmail 로그인 ──▶ 보이는 InAppWebView (사용자가 로그인) ──▶ 로그인 URL 감지 시 자동으로 닫힘
                                            │  (쿠키 공유)
[홈] "생수 12개 담고 결제 승인 받아줘" ──▶ AgentRunner ──▶ HeadlessInAppWebView (화면 없음)
                                            │
             LLM ◀── 페이지 스냅샷(텍스트 + 요소 id) ── read_page / open_url / click / type_text / scroll
                                            │
             request_approval ──▶ [작업 화면] 승인 카드 (승인 / 거절 / 수정 요청)
             request_user_help ──▶ 보이는 브라우저 (캡차, 2단계 인증, 결제 비밀번호)
             ask_user ──▶ 선택지 질문
             finish ──▶ 결과 보고 → 이어서 지시 가능 ("두 번째 메일에 답장 써줘")
```

## 폴더 구조

```
lib/
├── main.dart                     # Provider 구성, 앱 시작
├── llm/                          # LLM 공급자 추상화 (도구 호출 지원)
│   ├── llm_types.dart            #   공통 메시지/도구 타입
│   ├── openai_provider.dart      #   Chat Completions + function calling
│   ├── anthropic_provider.dart   #   Messages API + tool use
│   └── gemini_provider.dart      #   generateContent + function calling
├── browser/
│   ├── agent_browser.dart        # 헤드리스 웹뷰 제어 (이동/스냅샷/클릭/입력/스크린샷)
│   ├── dom_scripts.dart          # 주입 JS: 보이는 요소에 id 부여, React 호환 입력 등
│   ├── web_settings.dart         # 로그인용·에이전트용 웹뷰 공통 설정(UA, 쿠키)
│   ├── sites.dart                # 사이트 정의 (쿠팡, Gmail) — 여기에 새 사이트 추가
│   └── session_store.dart        # 사이트별 로그인 상태, 로그아웃(쿠키 삭제)
├── agent/
│   ├── agent_runner.dart         # LLM ↔ 도구 실행 루프, 스냅샷 압축, 재시도
│   ├── agent_tools.dart          # LLM 에게 주는 도구 목록
│   ├── safety.dart               # 결제/전송 버튼 승인 강제 (1회용, 10분)
│   ├── prompts.dart              # 시스템 프롬프트
│   ├── agent_models.dart         # 로그, 승인 요청, 질문 모델
│   └── agent_controller.dart     # UI 상태 (ChangeNotifier)
└── ui/
    ├── home_screen.dart          # 로그인 상태, 작업 입력, 예시
    ├── task_screen.dart          # 실시간 로그, 브라우저 스크린샷, 승인/질문 카드, 후속 지시
    ├── browser_screen.dart       # 사용자가 직접 조작하는 브라우저
    └── settings_screen.dart      # LLM 선택, API 키, 모델
```

## 실행 방법

```bash
flutter pub get
flutter run            # Android 기기/에뮬레이터 또는 iOS 기기/시뮬레이터
flutter test           # LLM 요청 변환, 승인 강제 로직 테스트
```

1. 앱 오른쪽 위 **설정**에서 사용할 LLM을 고르고 API 키를 입력합니다.
   - 기본 모델: OpenAI `gpt-4.1`, Claude `claude-sonnet-5`, Gemini `gemini-2.5-flash` (설정에서 변경 가능)
2. 홈에서 **쿠팡 / Gmail 로그인**을 누르고 직접 로그인합니다. 로그인되면 창이 자동으로 닫힙니다.
3. 할 일을 입력하고 **실행**을 누릅니다. 결제·전송 직전에 승인 카드가 뜹니다.

## 안전장치

| 위험 | 대응 |
| --- | --- |
| LLM이 승인 없이 결제/전송 | `SafetyPolicy`가 클릭 대상 버튼 문구(결제하기, 주문하기, 보내기, Send 등)를 검사해 **승인이 없으면 코드에서 차단**. 승인은 1회용이며 10분 뒤 만료 |
| 이메일·웹페이지 속 악성 지시(프롬프트 인젝션) | 시스템 프롬프트로 무시하도록 지시 + 위 코드 레벨 차단으로 최종 방어 |
| 비밀번호 유출 | 에이전트는 `type=password` 입력창에 입력할 수 없음. 로그인/결제 비밀번호는 항상 사용자가 직접 입력. 앱은 비밀번호를 저장하지 않음 |
| 임의 코드 실행 | LLM 에게 임의 JavaScript 실행 도구를 주지 않음 (정해진 스크립트만 사용) |
| API 키 | `flutter_secure_storage` (Keychain / Keystore) 에 저장 |
| 무한 루프·비용 | 작업당 최대 단계 수 제한, 오래된 페이지 스냅샷은 대화에서 요약해 토큰 절약 |

## 알아둘 제약 사항

- **Google 로그인**: Google 은 임베디드 웹뷰 로그인을 막는 경우가 있습니다(`disallowed_useragent`). 이를 피하려고 일반 모바일 브라우저 User-Agent 를 쓰지만, 계정·지역에 따라 여전히 막힐 수 있습니다. 안정적인 상용 서비스라면 Gmail 은 **Google Sign-In + Gmail API(OAuth)** 로 바꾸는 것을 권장합니다 (`sites.dart`/도구를 API 기반으로 추가하면 됩니다).
- **쿠팡**: 자동화 접근은 쿠팡 이용약관과 봇 탐지 정책의 영향을 받을 수 있습니다. 화면 구조가 바뀌어도 LLM 이 스냅샷을 보고 판단하므로 셀렉터를 하드코딩하지 않았지만, 결제 비밀번호(쿠페이) 입력은 항상 사용자에게 넘깁니다.
- **백그라운드 실행**: 에이전트는 화면에 보이지 않는 웹뷰에서 동작하므로 앱 안에서는 다른 화면을 봐도 계속 진행됩니다. 다만 앱 자체를 내리면 iOS 는 곧 실행을 멈추고, Android 도 절전 정책에 따라 멈출 수 있습니다. 완전한 백그라운드 실행이 필요하면 Android Foreground Service, 알림(승인 요청 푸시) 등을 추가해야 합니다.
- **도움 요청 시 페이지 상태**: 캡차·결제 비밀번호 등으로 사용자에게 넘길 때 같은 URL 을 보이는 브라우저에서 새로 엽니다. URL 에 담기지 않은 화면 상태(예: 결제 팝업)는 다시 열어야 할 수 있습니다.

## 새 사이트 추가

`lib/browser/sites.dart` 에 `SiteConfig` 를 하나 추가하고 `allSites` 에 넣으면 됩니다. 로그인 URL, 시작 URL, 로그인 완료를 판별할 URL 패턴, 에이전트에게 줄 팁만 적으면 홈 화면과 시스템 프롬프트에 자동으로 반영됩니다.
