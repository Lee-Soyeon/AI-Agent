# Slack OAuth 중계 서버 (Cloudflare Worker)

이 앱을 **여러 사람에게 배포**할 때, 각자 Slack App을 만들고 Bot Token을 발급받는 번거로움 없이
**"Slack 연동" 버튼 한 번**으로 끝내기 위한 작은 중계 서버입니다.

- Slack Client Secret은 **여기(개발자가 한 번 배포하는 이 Worker)에만** 있고, 앱(폰)에는 전혀 들어가지 않습니다.
- 앱은 Slack Bot Token을 직접 다루지 않고, 이 Worker가 발급한 일회용 `state` 로 결과만 받아 갑니다.
- 무료 플랜(Cloudflare Workers Free)으로 충분합니다. 서버 관리가 필요 없습니다.

## 왜 서버가 꼭 필요한가

Slack OAuth는 code→token 교환에 **Client Secret**이 필요하고, Slack 정책상 이 비밀값은 앱(클라이언트) 안에 넣을 수 없습니다
(디컴파일하면 누구나 추출해 다른 워크스페이스의 토큰을 가로챌 수 있음). 이건 Slack 구조상 불가피하며,
이 Worker가 그 역할(비밀값 보관 + 교환 대행)만 **하나만** 전담합니다 — 에이전트 실행 자체와는 무관합니다
(`server/` 와는 완전히 다른, 별개의 아주 작은 서비스입니다).

아래 순서대로 하면 **Worker 주소를 먼저 확보한 뒤** 그 주소가 이미 채워진 매니페스트로 Slack App을 만들기 때문에,
나중에 Redirect URL을 다시 고칠 필요가 없습니다.

## 1. Worker 먼저 배포해서 주소 확보

```bash
cd slack_relay
npm install
npx wrangler login
npx wrangler kv namespace create OAUTH_STATE   # 출력된 id 를 wrangler.toml 의 id 에 넣기
npx wrangler deploy
```

마지막 명령 출력에 `https://ai-agent-slack-relay.<your-subdomain>.workers.dev` 같은 주소가 나옵니다 (아직 Slack 비밀값을
안 넣은 상태라 `/slack/oauth/*` 호출은 실패하지만, 배포 자체는 문제없이 됩니다). 이 주소를 적어두세요.

## 2. Slack App 만들기 — 매니페스트로 한 번에

1. `slack-app-manifest.yaml` 을 열어 `REPLACE-WITH-YOUR-WORKER-URL` 부분을 1번에서 받은 실제 주소로 바꿉니다.
2. https://api.slack.com/apps → **Create New App** → **From an app manifest** → 워크스페이스 선택
3. 수정한 `slack-app-manifest.yaml` 내용을 그대로 붙여넣기 (YAML/JSON 탭 전환 가능) → **Next** → **Create**
4. **Manage Distribution** → **Activate Public Distribution** (여러 워크스페이스에서 설치 가능하게. Slack 심사는 필요 없습니다 —
   심사는 Slack 마켓플레이스에 "등록"할 때만 필요합니다)
5. **Basic Information** 에서 **Client ID**, **Client Secret** 확인

## 3. Worker에 Slack 비밀값 넣기

```bash
npx wrangler secret put SLACK_CLIENT_ID
npx wrangler secret put SLACK_CLIENT_SECRET
```

재배포 없이 바로 적용됩니다. (`npx wrangler dev` 로 로컬 테스트할 때는 `.dev.vars` 에 같은 값을 넣으세요 — `.dev.vars.example` 참고.)

## 4. 앱에 연결하기

Flutter 앱 빌드 시 이 Worker 주소를 넣어줍니다:

```bash
flutter build ios --dart-define=SLACK_RELAY_URL=https://ai-agent-slack-relay.<your-subdomain>.workers.dev
flutter build appbundle --dart-define=SLACK_RELAY_URL=https://ai-agent-slack-relay.<your-subdomain>.workers.dev
```

이후 사용자는 앱의 **로그인 → 업무 필터 → Slack** 화면에서 **"Slack 워크스페이스 연동"** 버튼만 누르면 됩니다.
Bot Token을 직접 발급해 붙여넣는 기존 방식도 "직접 토큰 입력(고급)"으로 계속 남아 있습니다.

## 로컬 개발/테스트

```bash
npm test                 # 순수 로직 단위 테스트 (KV·Slack API 를 모킹, 네트워크 불필요)
npx wrangler dev          # 실제 Cloudflare 런타임으로 로컬 실행 (.dev.vars 에 시크릿 필요)
```

## 엔드포인트

| 메서드 | 경로 | 설명 |
| --- | --- | --- |
| GET | `/slack/oauth/start` | `state` 와 Slack 인증 URL 발급 |
| GET | `/slack/oauth/callback` | Slack 이 리다이렉트하는 주소. code→token 교환 후 안내 페이지 표시 |
| GET | `/slack/oauth/result?state=` | 앱이 결과를 가져감 (한 번만, 가져가면 삭제) |
| GET | `/healthz` | 상태 확인 |

## 보안 참고

- `state` 는 서버가 `crypto.randomUUID()` 로 발급하며, 10분 안에 승인하지 않으면 만료됩니다.
- 결과(토큰 포함)는 KV에 최대 5분만 남고, `result` 로 한 번 가져가면 즉시 삭제됩니다(재사용/가로채기 방지).
- 이 Worker는 Bot Token을 저장하지 않습니다 — 교환 즉시 앱에 전달하고 지웁니다.
