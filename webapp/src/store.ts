// 이 브라우저에만 남는 값 (로그인한 계정·프로필·서버 주소). 사생활 모드에서는 저장이 막힐 수 있다.

const read = (key: string) => {
  try {
    return localStorage.getItem(key) ?? '';
  } catch {
    return '';
  }
};

const write = (key: string, value: string) => {
  try {
    if (value) localStorage.setItem(key, value);
    else localStorage.removeItem(key);
  } catch {
    // 저장이 막혀도 이번 접속 동안은 메모리 값으로 쓴다
  }
};

export type Account = { email: string; name: string; picture?: string };
export type Profile = { persona: string; routine: string };

export const store = {
  account(): Account | null {
    const raw = read('account');
    return raw ? (JSON.parse(raw) as Account) : null;
  },
  setAccount(a: Account | null) {
    write('account', a ? JSON.stringify(a) : '');
  },
  profile(): Profile | null {
    const raw = read('profile');
    return raw ? (JSON.parse(raw) as Profile) : null;
  },
  setProfile(p: Profile | null) {
    write('profile', p ? JSON.stringify(p) : '');
  },
  serverUrl: () => read('server_url') || (import.meta.env.VITE_AGENT_SERVER_URL as string | undefined) || '',
  serverToken: () => read('server_token') || (import.meta.env.VITE_AGENT_SERVER_TOKEN as string | undefined) || '',
  setServer(url: string, token: string) {
    write('server_url', url.trim().replace(/\/+$/, ''));
    write('server_token', token.trim());
  },
};
