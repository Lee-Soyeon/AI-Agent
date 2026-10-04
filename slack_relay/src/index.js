/**
 * Slack OAuth 중계 서버 (Cloudflare Worker).
 *
 * 역할: Slack Client Secret 을 보관하고, code→token 교환만 대신해 준다.
 * 앱(폰) 쪽은 비밀키를 전혀 몰라도 되고, "state" 라는 임시 번호표로 결과를 가져간다.
 *
 *   1. GET /slack/oauth/start      → Slack 인증 URL + state 발급 (상태를 KV에 'pending'으로 기록)
 *   2. (브라우저) 사용자가 Slack 에서 워크스페이스 선택 후 "허용"
 *   3. GET /slack/oauth/callback   → Slack 이 이 주소로 돌려보냄. code→token 교환 후 KV에 결과 저장, 안내 페이지 표시
 *   4. GET /slack/oauth/result     → 앱이 state 로 결과를 가져감 (한 번 가져가면 삭제됨)
 *
 * 필요한 바인딩/환경변수 (wrangler.toml, README 참고):
 *   - KV 네임스페이스: OAUTH_STATE
 *   - SLACK_CLIENT_ID, SLACK_CLIENT_SECRET (wrangler secret)
 *   - SLACK_SCOPES (선택, 기본 "chat:write,channels:read,groups:read")
 */

const DEFAULT_SCOPES = 'chat:write,channels:read,groups:read';
const PENDING_TTL_SECONDS = 600; // state 발급 후 10분 안에 승인해야 함
const RESULT_TTL_SECONDS = 300; // 승인 후 앱이 5분 안에 가져가야 함

function redirectUriFor(requestUrl) {
  return new URL('/slack/oauth/callback', requestUrl).toString();
}

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'access-control-allow-origin': '*' },
  });
}

function htmlResponse(title, message, status = 200) {
  const html = `<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<style>
  body { font-family: -apple-system, system-ui, sans-serif; background: #0b0b0c; color: #eee;
         display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
  .card { text-align: center; padding: 32px; max-width: 420px; }
  h1 { font-size: 20px; margin-bottom: 8px; }
  p { color: #aaa; font-size: 14px; line-height: 1.6; }
</style></head>
<body><div class="card"><h1>${title}</h1><p>${message}</p></div></body></html>`;
  return new Response(html, { status, headers: { 'content-type': 'text/html; charset=utf-8' } });
}

async function handleStart(request, env) {
  if (!env.SLACK_CLIENT_ID) return jsonResponse({ error: 'SLACK_CLIENT_ID 가 설정되지 않았습니다.' }, 500);
  const state = crypto.randomUUID();
  const redirectUri = redirectUriFor(request.url);
  const scopes = env.SLACK_SCOPES || DEFAULT_SCOPES;
  await env.OAUTH_STATE.put(`state:${state}`, JSON.stringify({ status: 'pending' }), {
    expirationTtl: PENDING_TTL_SECONDS,
  });
  const authorizeUrl = new URL('https://slack.com/oauth/v2/authorize');
  authorizeUrl.searchParams.set('client_id', env.SLACK_CLIENT_ID);
  authorizeUrl.searchParams.set('scope', scopes);
  authorizeUrl.searchParams.set('redirect_uri', redirectUri);
  authorizeUrl.searchParams.set('state', state);
  return jsonResponse({ state, authorizeUrl: authorizeUrl.toString() });
}

async function handleCallback(request, env) {
  const url = new URL(request.url);
  const state = url.searchParams.get('state') || '';
  const code = url.searchParams.get('code');
  const error = url.searchParams.get('error');
  const key = `state:${state}`;
  const existingRaw = state ? await env.OAUTH_STATE.get(key) : null;
  if (!existingRaw) {
    return htmlResponse('연동 요청을 찾을 수 없습니다', '다시 앱에서 "Slack 연동"을 눌러 처음부터 시도해 주세요.', 400);
  }

  if (error) {
    await env.OAUTH_STATE.put(key, JSON.stringify({ status: 'denied' }), { expirationTtl: RESULT_TTL_SECONDS });
    return htmlResponse('연동을 취소했습니다', '앱으로 돌아가 다시 시도할 수 있습니다.');
  }
  if (!code) {
    return htmlResponse('잘못된 요청입니다', 'Slack 에서 code 값을 받지 못했습니다.', 400);
  }

  const redirectUri = redirectUriFor(request.url);
  const tokenRes = await fetch('https://slack.com/api/oauth.v2.access', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: env.SLACK_CLIENT_ID,
      client_secret: env.SLACK_CLIENT_SECRET,
      code,
      redirect_uri: redirectUri,
    }),
  });
  const tokenJson = await tokenRes.json();

  if (!tokenJson.ok) {
    await env.OAUTH_STATE.put(
      key,
      JSON.stringify({ status: 'error', message: tokenJson.error || 'unknown_error' }),
      { expirationTtl: RESULT_TTL_SECONDS },
    );
    return htmlResponse('연동에 실패했습니다', `Slack 오류: ${tokenJson.error || 'unknown_error'}`, 400);
  }

  await env.OAUTH_STATE.put(
    key,
    JSON.stringify({
      status: 'done',
      botToken: tokenJson.access_token,
      teamName: tokenJson.team?.name || '',
      teamId: tokenJson.team?.id || '',
    }),
    { expirationTtl: RESULT_TTL_SECONDS },
  );
  return htmlResponse(
    'Slack 연동 완료',
    `${tokenJson.team?.name || '워크스페이스'}에 연동되었습니다. 이제 앱으로 돌아가 주세요.`,
  );
}

async function handleResult(request, env) {
  const url = new URL(request.url);
  const state = url.searchParams.get('state') || '';
  if (!state) return jsonResponse({ status: 'error', message: 'state 파라미터가 필요합니다.' }, 400);
  const key = `state:${state}`;
  const raw = await env.OAUTH_STATE.get(key);
  if (!raw) return jsonResponse({ status: 'unknown' }, 404);
  const data = JSON.parse(raw);
  if (data.status === 'pending') return jsonResponse({ status: 'pending' }, 202);
  // 성공/거부/오류는 한 번 내주고 지운다 (재사용 방지).
  await env.OAUTH_STATE.delete(key);
  return jsonResponse(data);
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'access-control-allow-origin': '*',
          'access-control-allow-methods': 'GET, OPTIONS',
        },
      });
    }
    if (url.pathname === '/healthz') return jsonResponse({ ok: true });
    if (url.pathname === '/slack/oauth/start') return handleStart(request, env);
    if (url.pathname === '/slack/oauth/callback') return handleCallback(request, env);
    if (url.pathname === '/slack/oauth/result') return handleResult(request, env);
    return jsonResponse({ error: 'not_found' }, 404);
  },
};
