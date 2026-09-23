FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    DATA_DIR=/data \
    HEADLESS=0

WORKDIR /srv
COPY requirements.txt .
# xvfb: 화면 있는(headed) 크롬을 가상 디스플레이에서 띄운다 — headless 보다 봇 탐지에 덜 걸린다.
# fonts-noto-cjk: 한글 페이지가 네모(□)로 깨지지 않게.
RUN pip install --no-cache-dir -r requirements.txt \
 && playwright install --with-deps chromium \
 && apt-get update && apt-get install -y --no-install-recommends xvfb xauth fonts-noto-cjk \
 && rm -rf /var/lib/apt/lists/*

COPY app ./app

# 로그인 상태(브라우저 프로필)가 담기는 곳. 반드시 볼륨으로 유지하세요.
VOLUME ["/data"]
EXPOSE 8000
CMD ["xvfb-run", "-a", "--server-args=-screen 0 1280x1024x24", \
     "uvicorn", "app.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000"]
