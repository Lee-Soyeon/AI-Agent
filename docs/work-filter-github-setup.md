# 업무 필터 → GitHub 설정 가이드

에이닷(통화 요약/녹음) 이나 문자에서 **공유** 버튼으로 이 앱에 내용을 보내면, LLM 이 업무 관련인지 판단합니다.
업무 관련으로 분류된 내용은 바로 올라가지 않고 기기에 쌓여 있다가, **하루치를 모아 "오늘 분 GitHub PR로 올리기"**
버튼을 누르면 GitHub 저장소에 브랜치 하나 + 파일 하나 + PR 하나로 올라갑니다.

## 왜 완전 자동(백그라운드 수집도, 자동 업로드도)이 안 되는가

- **수집**: iOS 는 제3자 앱이 다른 앱(에이닷)의 데이터나 문자(SMS/iMessage)를 백그라운드에서 읽을 수 있는 공개 API를
  제공하지 않습니다. 탈옥 없이는 불가능하며, 이 앱은 탈옥이 필요한 방식을 지원하지 않습니다. 대신 **사람이 공유
  버튼을 한 번 누르면 그 뒤로는 분류까지 전부 자동**으로 처리되는 방식을 씁니다.
- **업로드**: 앱이 백그라운드에서 계속 돌며 "자정이 되면 자동으로 PR을 만드는" 스케줄 실행도 iOS 에서는 보장되지
  않습니다 (앱을 내리면 곧 멈춤). 그래서 하루 업로드는 사용자가 **버튼을 한 번** 누르는 방식입니다 — 그 버튼을
  누르는 순간부터 브랜치 생성, 파일 커밋, PR 생성까지는 전부 자동입니다.

```
에이닷/문자 앱의 "공유" 버튼 → 이 앱 선택(1탭)
        │
        ▼
이 앱이 텍스트를 받음 (ShareIntentController)
        │
        ▼
LLM 이 "업무 / 개인" 판단 + 한 줄 요약 생성 (WorkFilterService) → 기기에 기록
        │
   (하루 동안 반복, 여러 건 쌓임)
        │
사용자가 "오늘 분 GitHub PR로 올리기" 버튼 1번 클릭
        │
        ▼
GithubUploadService: worklog/YYYY-MM-DD 브랜치 생성 → worklog/YYYY-MM-DD.md 파일에
그날 업무 항목을 모아 커밋 → 그 브랜치로 PR 생성(이미 있으면 같은 PR에 이어서 커밋)
```

## 1. GitHub 쪽 설정 (Personal Access Token 발급)

이 저장소(`booboobook/aidol-ir`)는 개인 저장소 하나뿐이라, Slack 의 "여러 워크스페이스 배포"와 달리
중계 서버 없이 **Fine-grained Personal Access Token** 을 앱에 직접 넣는 방식이 가장 간단합니다.

1. https://github.com/settings/personal-access-tokens/new (Fine-grained tokens)
2. **Resource owner**: 저장소 소유자(`booboobook`) 선택
3. **Repository access** → **Only select repositories** → `aidol-ir` 선택
4. **Permissions → Repository permissions**:
   - **Contents**: Read and write
   - **Pull requests**: Read and write
5. **Generate token** → 토큰 복사 (`github_pat_...`)

## 2. 앱에서 연결하기

앱 → **로그인** 탭 → **업무 필터 → GitHub** 카드 → 들어가서:

1. 저장소 소유자(`booboobook`), 저장소 이름(`aidol-ir`), Personal Access Token 입력 → **연결**
2. **텍스트로 테스트** 칸에 통화 요약/문자 내용을 복사해 붙여넣고 **분류 테스트** 눌러서,
   공유 시트 설정 없이도 분류가 되는지 먼저 확인하세요 (이 버튼은 GitHub에 올리지 않고 분류만 합니다).
3. 하루 동안 공유된 업무 관련 내용이 쌓이면, **"오늘 분 GitHub PR로 올리기"** 버튼을 눌러 한 번에 PR로 올립니다.
   같은 날 여러 번 눌러도 같은 브랜치/PR에 이어서 커밋됩니다.

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
**업무 필터 → GitHub** 화면의 "텍스트로 테스트" 칸에 붙여넣어 같은 방식으로 분류할 수 있습니다.
(자동 공유가 안 될 뿐, 분류 로직은 동일하고, 분류된 내용은 그대로 하루 업로드 대상에 들어갑니다.)

## 알아둘 점

- PR은 하루 단위(`worklog/YYYY-MM-DD` 브랜치, `worklog/YYYY-MM-DD.md` 파일)로 쌓입니다. 같은 날 여러 번 올리면
  기존 PR에 이어서 커밋만 추가됩니다.
- 그 날짜의 PR이 이미 **머지되거나 닫힌 뒤** 다시 업로드하면, 같은 브랜치에 커밋만 추가되고 새 PR이 자동으로
  열리지는 않습니다(병합된 브랜치에 새 PR을 또 만드는 건 혼란을 줄 수 있어 의도적으로 막아두지 않았지만, 이런
  경우는 거의 없을 것으로 예상합니다). 이런 경우를 발견하면 알려주세요.
