// Google Identity Services 로 로그인(처음이면 가입). 이름·이메일만 받는다.
// GIS 는 로그인을 기억하지 않으므로 받은 계정은 store 에 두고 로그아웃 때만 지운다.

import type { Account } from './store';

export const clientId = (import.meta.env.VITE_GOOGLE_WEB_CLIENT_ID as string | undefined) ?? '';

type CredentialResponse = { credential: string };

declare global {
  interface Window {
    google?: {
      accounts: {
        id: {
          initialize(o: { client_id: string; callback: (r: CredentialResponse) => void; auto_select?: boolean }): void;
          renderButton(el: HTMLElement, o: Record<string, unknown>): void;
          disableAutoSelect(): void;
        };
      };
    };
  }
}

/** ID 토큰(JWT) 가운데 부분에서 이름·이메일을 꺼낸다. 서버 검증은 하지 않는다(화면 표시용). */
function decode(credential: string): Account {
  const part = credential.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
  const json = decodeURIComponent(
    atob(part)
      .split('')
      .map((c) => '%' + c.charCodeAt(0).toString(16).padStart(2, '0'))
      .join(''),
  );
  const p = JSON.parse(json) as { email: string; name?: string; given_name?: string; picture?: string };
  return { email: p.email, name: p.name ?? p.email, picture: p.picture };
}

const whenLoaded = () =>
  new Promise<NonNullable<Window['google']>>((resolve) => {
    const tick = () => (window.google ? resolve(window.google) : setTimeout(tick, 50));
    tick();
  });

export async function renderGoogleButton(el: HTMLElement, onSignIn: (a: Account) => void) {
  const google = await whenLoaded();
  google.accounts.id.initialize({ client_id: clientId, callback: (r) => onSignIn(decode(r.credential)) });
  google.accounts.id.renderButton(el, {
    type: 'standard',
    theme: 'outline',
    size: 'large',
    text: 'continue_with',
    shape: 'rectangular',
    width: el.clientWidth || 320,
    locale: 'ko',
  });
}

export function googleSignOut() {
  window.google?.accounts.id.disableAutoSelect();
}
