# AI Agent 서버

앱이 보낸 작업을 **서버의 실제 크롬 브라우저**로 백그라운드에서 실행합니다.
앱을 꺼도 작업은 계속되고, 결제·전송처럼 되돌릴 수 없는 동작은 앱에서 승인해야만 진행됩니다.

- **어떤 웹 서비스든**: 사이트별 코드 없이 LLM 이 화면을 읽고 조작합니다.
- **로그인은 한 번만**: 앱의 "서버 브라우저" 화면에서 서버 브라우저에 직접 로그인합니다 (실시간 화면 + 탭/입력 전달).
  로그인 상태는 서버 프로필(`/data`)에 저장되어 재시작 후에도 유지됩니다.
- **사용자 도움**: 캡차·인증번호·결제 비밀번호가 나오면 작업이 멈추고, 앱에 같은 브라우저 화면이 떠서 직접 처리합니다.

## 실행 (Docker)

```bash
cp .env.example .env    # AGENT_TOKEN 과 LLM API 키 입력
docker build -t ai-agent-server .
docker run -d --name ai-agent --env-file .env -p 8000:8000 -v ai-agent-data:/data ai-agent-server
```

앱 → 설정 → **실행 위치: 서버** → 서버 주소(`https://…`)와 `AGENT_TOKEN` 입력.

### 배포 시 주의
- **HTTPS 필수**: 토큰과 로그인 화면이 오가므로 반드시 HTTPS 뒤에 두세요 (Caddy, Cloudflare Tunnel, 클라우드 로드밸런서 등).
- **서버 위치**: 한국 서비스(쿠팡·네이버 등)는 해외 데이터센터 IP 를 차단하거나 추가 인증을 요구하는 경우가 많습니다.
  **국내 리전**(AWS 서울, NCP, 가정용 PC/미니PC 등)을 권장합니다.
- **개인용 서버**: 토큰 하나로 보호되는 1인용 구조입니다. 서버 브라우저에는 로그인한 모든 서비스의 세션이 있으므로
  토큰을 비밀번호처럼 관리하세요. 여러 사용자를 받으려면 사용자별 프로필·인증을 추가해야 합니다.
- **세션 쿠키**: "로그인 상태 유지"를 체크하지 않은 로그인(만료일 없는 쿠키)은 서버 재시작 시 풀릴 수 있습니다.

## 직접 실행 (Docker 없이, Mac)

**Python 3.10 이상**이 필요합니다 (3.12 권장). conda/miniforge 를 쓰고 있다면 먼저 `conda deactivate`.

```bash
brew install python@3.12
cd server
python3.12 -m venv .venv && source .venv/bin/activate
python --version                      # 3.12.x 인지 확인
pip install -r requirements.txt
python -m playwright install chromium
cp .env.example .env                  # AGENT_TOKEN 과 LLM 키 입력
set -a; source .env; set +a
HEADLESS=0 DATA_DIR=./data python -m uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8000
```

`python -m uvicorn` 으로 실행해야 가상환경의 uvicorn 이 쓰입니다. `HEADLESS=0` 이면 에이전트가 조작하는 크롬 창이 화면에 보입니다.

## API 요약

| 메서드 | 경로 | 설명 |
| --- | --- | --- |
| POST | `/tasks` `{prompt}` | 작업 시작 (한 번에 하나) |
| GET | `/tasks/current`, `/tasks/{id}?since=N` | 상태·로그(N 번째 이후)·대기 중인 승인/질문/도움 |
| POST | `/tasks/{id}/approval` `{approved, feedback}` | 승인/거절 |
| POST | `/tasks/{id}/answer` `{text}` | 질문 답변 |
| POST | `/tasks/{id}/help_done` | 사용자 도움 완료 |
| POST | `/tasks/{id}/followup` `{prompt}` | 이어서 지시 |
| POST | `/tasks/{id}/cancel` | 취소 |
| GET | `/tasks/{id}/screenshot` | 최근 화면 (JPEG) |
| POST | `/browser/open` `{url}` | 로그인용으로 사이트 열기 |
| WS | `/live?token=` | 실시간 화면(`frame`) 수신, `tap/type/key/scroll/back/navigate` 전송 |

모든 요청은 `Authorization: Bearer <AGENT_TOKEN>` 이 필요합니다.

## 개발

```bash
pip install -r requirements-dev.txt && playwright install chromium
pytest            # 실제 크롬 통합 테스트 포함
AGENT_TOKEN=dev ANTHROPIC_API_KEY=... uvicorn app.main:create_app --factory --reload
```
