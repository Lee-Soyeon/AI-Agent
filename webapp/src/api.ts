import { store } from './store';

// 에이전트 서버(server/app/main.py) 호출. 주소·토큰은 설정 화면 값이 빌드 값보다 우선.

export type TaskLog = { kind: string; text: string; detail?: string | null };
export type Pending = { type: string; question?: string; options?: string[]; summary?: string; [k: string]: unknown };
export type Task = {
  id: string;
  prompt: string;
  status: string;
  logs: TaskLog[];
  log_count: number;
  pending: Pending | null;
  result: string | null;
};

export class ServerMissing extends Error {}

async function call<T>(method: string, path: string, body?: unknown): Promise<T> {
  const base = store.serverUrl();
  if (!base) throw new ServerMissing('서버 주소가 없어요. 설정에서 서버 주소를 넣어 주세요.');
  const token = store.serverToken();
  const res = await fetch(base + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!res.ok) {
    const j = (await res.json().catch(() => null)) as { detail?: string } | null;
    throw new Error(j?.detail ?? `서버 오류 (${res.status})`);
  }
  return (await res.json().catch(() => null)) as T;
}

export const api = {
  health: () => call<{ ok?: boolean }>('GET', '/health'),
  createTask: (prompt: string) => call<Task>('POST', '/tasks', { prompt }),
  task: (id: string, since = 0) => call<Task>('GET', `/tasks/${id}?since=${since}`),
  answer: (id: string, text: string) => call('POST', `/tasks/${id}/answer`, { text }),
  approve: (id: string, approved: boolean) => call('POST', `/tasks/${id}/approval`, { approved }),
  cancel: (id: string) => call('POST', `/tasks/${id}/cancel`),
};
