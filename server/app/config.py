"""환경 변수로 읽는 서버 설정."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Settings:
    # 앱과 서버가 공유하는 접근 토큰 (필수). 앱 설정의 '서버 토큰'에 같은 값을 넣는다.
    agent_token: str = field(default_factory=lambda: os.getenv("AGENT_TOKEN", ""))
    # 개발용: 토큰 없이 실행 허용 (로컬에서만!)
    allow_no_auth: bool = field(default_factory=lambda: os.getenv("ALLOW_NO_AUTH") == "1")

    llm_provider: str = field(default_factory=lambda: os.getenv("LLM_PROVIDER", "anthropic"))
    llm_model: str = field(default_factory=lambda: os.getenv("LLM_MODEL", ""))
    anthropic_api_key: str = field(default_factory=lambda: os.getenv("ANTHROPIC_API_KEY", ""))
    # 워크스페이스에 속하지 않은(조직 단위) 키를 쓸 때만: wrkspc_...
    anthropic_workspace_id: str = field(default_factory=lambda: os.getenv("ANTHROPIC_WORKSPACE_ID", ""))
    openai_api_key: str = field(default_factory=lambda: os.getenv("OPENAI_API_KEY", ""))
    gemini_api_key: str = field(default_factory=lambda: os.getenv("GEMINI_API_KEY", ""))
    xai_api_key: str = field(default_factory=lambda: os.getenv("XAI_API_KEY", ""))
    openrouter_api_key: str = field(default_factory=lambda: os.getenv("OPENROUTER_API_KEY", ""))

    max_steps: int = field(default_factory=lambda: int(os.getenv("MAX_STEPS", "60")))
    # 운영자 키로 돌릴 때 LLM 호출 수 한도. 0 = 무제한. 넘으면 새 작업·intake 를 429 로 거부한다.
    daily_request_limit: int = field(default_factory=lambda: int(os.getenv("DAILY_REQUEST_LIMIT", "0")))
    monthly_request_limit: int = field(default_factory=lambda: int(os.getenv("MONTHLY_REQUEST_LIMIT", "0")))
    # 웹 앱(Vercel 등)이 이 서버를 부를 수 있는 출처. 쉼표로 구분. 기본 * (전부 허용)
    cors_origins: list[str] = field(
        default_factory=lambda: [o.strip() for o in os.getenv("CORS_ORIGINS", "*").split(",") if o.strip()]
    )
    # 로그인 쿠키 등 브라우저 프로필이 저장되는 곳 (볼륨으로 유지해야 재시작 후에도 로그인 유지)
    data_dir: Path = field(default_factory=lambda: Path(os.getenv("DATA_DIR", "./data")))
    headless: bool = field(default_factory=lambda: os.getenv("HEADLESS", "1") != "0")
    chromium_path: str | None = field(default_factory=lambda: os.getenv("CHROMIUM_PATH") or None)

    def validate(self) -> None:
        if not self.agent_token and not self.allow_no_auth:
            raise RuntimeError("AGENT_TOKEN 환경 변수를 설정하세요 (앱과 공유하는 비밀 토큰).")
