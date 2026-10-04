# 업무 필터 → Slack 설정 가이드

에이닷(통화 요약/녹음) 이나 문자에서 **공유** 버튼으로 이 앱에 내용을 보내면, LLM 이 업무 관련인지 판단해 업무 관련인 것만 Slack 채널로 보내줍니다.

## 왜 완전 자동(백그라운드 수집)이 안 되는가

iOS 는 제3자 앱이 다른 앱(에이닷)의 데이터나 문자(SMS/iMessage)를 백그라운드에서 읽을 수 있는 공개 API를 제공하지 않습니다.
탈옥 없이는 불가능하며, 이 앱은 탈옥이 필요한 방식을 지원하지 않습니다. 대신 **사람이 공유 버튼을 한 번 누르면 그 뒤로는 전부 자동**으로 처리되는 방식을 씁니다.

```
에이닷/문자 앱의 "공유" 버튼 → 이 앱 선택(1탭)
        │
        ▼
이 앱이 텍스트를 받음 (ShareIntentController)
        │
        ▼
LLM 이 "업무 / 개인" 판단 + 한 줄 요약 생성 (WorkFilterService)
        │
   업무 관련? ──No──▶ 기록만 남기고 끝
        │ Yes
        ▼
Slack Bot Token 으로 채널에 전송
```

## 1. Slack 연결 — 두 가지 방식

이 앱을 **여러 사람에게 배포**할 생각이라면, 사람마다 Slack App을 직접 만들고 토큰을 복사하게 하는 건 너무 번거롭습니다.
그래서 "Slack 워크스페이스 연동" 버튼 한 번으로 끝나는 **OAuth 방식**을 기본으로 두고, 직접 Bot Token을 발급받아
붙여넣는 방식은 "고급" 옵션으로 남겨뒀습니다.

### 1-A. OAuth 연동 (배포용, 추천)

Client Secret을 보관하고 code→token 교환을 대신해 줄 아주 작은 중계 서버가 필요합니다 (Cloudflare Workers 무료 플랜으로 충분).
설정 방법은 [slack_relay/README.md](../slack_relay/README.md)에 있습니다. 요약하면:

1. `slack_relay/` 를 Cloudflare Workers에 먼저 배포해 Worker 주소를 받습니다 (`npx wrangler deploy`).
2. `slack_relay/slack-app-manifest.yaml` 에 그 주소를 채워 넣고, Slack **Create New App → From an app manifest** 로 붙여넣어 앱을 만듭니다 (scope·Redirect URL이 이미 다 채워져 있어 따로 설정할 게 없습니다). 이어서 "Activate Public Distribution"을 켭니다 (여러 워크스페이스 설치 가능, Slack 심사 불필요).
3. 받은 Client ID/Secret을 Worker에 넣습니다 (`npx wrangler secret put ...`).
4. 앱을 빌드할 때 그 Worker 주소를 넣습니다:
   ```bash
   flutter build ios --dart-define=SLACK_RELAY_URL=https://ai-agent-slack-relay.<your-subdomain>.workers.dev
   ```
4. 이후 모든 사용자는 **업무 필터 → Slack** 화면에서 "Slack 워크스페이스 연동" 버튼만 누르면 됩니다
   (브라우저에서 워크스페이스 선택 → 허용 → 자동으로 앱에 연결).

`SLACK_RELAY_URL`을 빌드 시 넣지 않으면 이 버튼은 아예 보이지 않고, 1-B(직접 토큰 입력)만 쓸 수 있습니다.

### 1-B. 직접 Bot Token 입력 (고급, 중계 서버 없이도 됨)

1. https://api.slack.com/apps → **Create New App** → From scratch → 워크스페이스 선택
2. 왼쪽 메뉴 **OAuth & Permissions** → **Scopes → Bot Token Scopes** 에 추가:
   - `chat:write` (메시지 전송, 필수)
   - `channels:read` (공개 채널 목록을 보려면)
   - `groups:read` (비공개 채널도 쓰려면)
3. 같은 화면 위쪽 **Install to Workspace** → 권한 승인
4. 발급된 **Bot User OAuth Token** (`xoxb-...` 로 시작) 복사
5. 메시지를 보낼 채널에 봇을 초대: 그 채널에서 `/invite @앱이름` 입력

## 2. 앱에서 연결하기

앱 → **로그인** 탭 → **업무 필터 → Slack** 카드 → 들어가서:

1. "Slack 워크스페이스 연동" 버튼(1-A 설정을 했다면) 또는 "직접 Bot Token 입력"(1-B)으로 연결
2. **보낼 채널 선택** → 목록에서 1번에서 초대한 채널 선택
3. **텍스트로 테스트** 칸에 통화 요약/문자 내용을 복사해 붙여넣고 **분류 + 전송 테스트** 눌러서,
   공유 시트 설정 없이도 분류·Slack 전송이 되는지 먼저 확인하세요.

## 3. Android — 바로 동작합니다

`android/app/src/main/AndroidManifest.xml` 에 `ACTION_SEND` (text/\*) 인텐트 필터를 이미 추가해 두었습니다.
문자 앱 등에서 메시지를 길게 눌러 **공유** → 목록에서 **AI Agent** 를 선택하면 바로 들어옵니다. 추가 설정이 필요 없습니다.

## 4. iOS — Share Extension 수동 설정 (Xcode/Mac 필요)

iOS 는 공유 시트에 이 앱이 나타나려면 **Share Extension** 이라는 별도 네이티브 타깃이 꼭 필요합니다.
이 프로젝트를 빌드하는 환경(클라우드 컨테이너)에는 Xcode가 없어서, 이 부분은 **Mac + Xcode 가 있는 사람이 한 번만** 아래 순서로 해줘야 합니다. (Dart 쪽 코드는 이미 다 준비되어 있어서, 타깃만 추가하면 바로 동작합니다.)

1. `flutter config --enable-swift-package-manager` (한 번만)
2. `ios/Runner.xcworkspace` 를 Xcode 로 연다
3. **File → New → Target → Share Extension** 추가
   - Product Name: 예) `ShareExtension`
   - Language: Swift
4. **두 타깃 모두**(Runner, ShareExtension) → **Signing & Capabilities → + Capability → App Groups** 추가
   - 그룹 ID를 똑같이: 예) `group.ai.aioia.aiAgent`
5. **두 타깃 모두**의 Build Settings 에 User-Defined 설정 `CUSTOM_GROUP_ID` = 위에서 정한 그룹 ID 추가
6. `ShareExtension` 타깃의 `Info.plist` 에 `NSExtensionActivationRule` → `NSExtensionActivationSupportsText` = `true` 로 설정 (텍스트 공유만 받음)
7. `ShareExtension/ShareViewController.swift` 를 아래처럼 교체 (패키지가 제공하는 기반 클래스를 그대로 상속):

   ```swift
   import receive_sharing_intent

   class ShareViewController: RSIShareViewController {
   }
   ```

8. `ShareExtension` 타깃 → **General → Frameworks and Libraries** → `receive-sharing-intent` 추가
9. `ios/Runner/SceneDelegate.swift` 는 패키지 문서에 따라 공유로 들어온 URL을 처리하도록 조정이 필요할 수 있습니다
   (현재는 비워져 있는 기본 `FlutterSceneDelegate` 구독 클래스입니다). 패키지 README의 iOS 섹션을 따라
   `application(_:open:options:)` / Scene 쪽 URL 처리를 Google 로그인 콜백과 충돌하지 않게 추가하세요.
10. `flutter pub get` → 기기에서 실행 → 다른 앱(예: 메모 앱)에서 텍스트 공유 시트를 열어 **AI Agent** 가 보이는지 확인

> 참고: 패키지 버전이 올라가면 설정 방법이 바뀔 수 있습니다. 최신 안내는
> https://pub.dev/packages/receive_sharing_intent 의 Example/README를 확인하세요.

## 5. 에이닷 앱 자체에 공유 기능이 없다면

에이닷의 통화 요약 화면에 "공유" 버튼이 없는 경우, 요약 텍스트를 길게 눌러 복사한 뒤
**업무 필터 → Slack** 화면의 "텍스트로 테스트" 칸에 붙여넣어 같은 방식으로 처리할 수 있습니다.
(자동 공유가 안 될 뿐, 분류·Slack 전송 로직은 동일합니다.)
