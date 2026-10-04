import { test, mock } from 'node:test';
import assert from 'node:assert/strict';
import worker from '../src/index.js';

class FakeKv {
  constructor() {
    this.map = new Map();
  }
  async get(key) {
    return this.map.has(key) ? this.map.get(key) : null;
  }
  async put(key, value) {
    this.map.set(key, value);
  }
  async delete(key) {
    this.map.delete(key);
  }
}

function env(overrides = {}) {
  return {
    OAUTH_STATE: new FakeKv(),
    SLACK_CLIENT_ID: 'client123',
    SLACK_CLIENT_SECRET: 'secret456',
    ...overrides,
  };
}

test('start: state 를 발급하고 pending 으로 기록한다', async () => {
  const e = env();
  const res = await worker.fetch(new Request('https://relay.example.com/slack/oauth/start'), e);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.ok(body.state);
  assert.match(body.authorizeUrl, /^https:\/\/slack\.com\/oauth\/v2\/authorize\?/);
  assert.match(body.authorizeUrl, /redirect_uri=https%3A%2F%2Frelay\.example\.com%2Fslack%2Foauth%2Fcallback/);
  const stored = JSON.parse(await e.OAUTH_STATE.get(`state:${body.state}`));
  assert.equal(stored.status, 'pending');
});

test('callback 성공 → result 가 done + 토큰을 한 번만 돌려준다', async (t) => {
  const e = env();
  const startRes = await worker.fetch(new Request('https://relay.example.com/slack/oauth/start'), e);
  const { state } = await startRes.json();

  t.mock.method(globalThis, 'fetch', async (url) => {
    assert.equal(url, 'https://slack.com/api/oauth.v2.access');
    return new Response(
      JSON.stringify({ ok: true, access_token: 'xoxb-abc', team: { name: '우리회사', id: 'T1' } }),
      { status: 200 },
    );
  });

  const cbUrl = `https://relay.example.com/slack/oauth/callback?code=abc&state=${state}`;
  const cbRes = await worker.fetch(new Request(cbUrl), e);
  assert.equal(cbRes.status, 200);
  assert.match(await cbRes.text(), /연동 완료/);

  const r1 = await worker.fetch(
    new Request(`https://relay.example.com/slack/oauth/result?state=${state}`),
    e,
  );
  assert.equal(r1.status, 200);
  const body1 = await r1.json();
  assert.deepEqual(body1, { status: 'done', botToken: 'xoxb-abc', teamName: '우리회사', teamId: 'T1' });

  // 한 번 가져간 뒤엔 사라져야 한다 (재사용 방지).
  const r2 = await worker.fetch(
    new Request(`https://relay.example.com/slack/oauth/result?state=${state}`),
    e,
  );
  assert.equal(r2.status, 404);
});

test('아직 승인 전이면 result 가 202 pending', async () => {
  const e = env();
  const startRes = await worker.fetch(new Request('https://relay.example.com/slack/oauth/start'), e);
  const { state } = await startRes.json();
  const res = await worker.fetch(
    new Request(`https://relay.example.com/slack/oauth/result?state=${state}`),
    e,
  );
  assert.equal(res.status, 202);
  assert.deepEqual(await res.json(), { status: 'pending' });
});

test('사용자가 거부하면 callback 이 denied 로 기록한다', async () => {
  const e = env();
  const startRes = await worker.fetch(new Request('https://relay.example.com/slack/oauth/start'), e);
  const { state } = await startRes.json();
  const cbUrl = `https://relay.example.com/slack/oauth/callback?error=access_denied&state=${state}`;
  const cbRes = await worker.fetch(new Request(cbUrl), e);
  assert.equal(cbRes.status, 200);

  const res = await worker.fetch(
    new Request(`https://relay.example.com/slack/oauth/result?state=${state}`),
    e,
  );
  assert.deepEqual(await res.json(), { status: 'denied' });
});

test('모르는 state 로 callback 을 받으면 400', async () => {
  const e = env();
  const res = await worker.fetch(
    new Request('https://relay.example.com/slack/oauth/callback?code=x&state=bogus'),
    e,
  );
  assert.equal(res.status, 400);
});

test('모르는 state 로 result 를 물으면 404 unknown', async () => {
  const e = env();
  const res = await worker.fetch(
    new Request('https://relay.example.com/slack/oauth/result?state=bogus'),
    e,
  );
  assert.equal(res.status, 404);
  assert.deepEqual(await res.json(), { status: 'unknown' });
});

test('healthz', async () => {
  const e = env();
  const res = await worker.fetch(new Request('https://relay.example.com/healthz'), e);
  assert.deepEqual(await res.json(), { ok: true });
});
