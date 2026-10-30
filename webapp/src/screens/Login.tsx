import { FlexBox, Typography } from '@montage-ui/core';
import { useEffect, useRef } from 'react';

import { renderGoogleButton } from '../google';
import type { Account } from '../store';

/** 첫 화면: Google 로 계속하기. 처음이면 가입, 이미 썼다면 로그인. */
export default function Login({ onSignIn }: { onSignIn: (a: Account) => void }) {
  const button = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (button.current) void renderGoogleButton(button.current, onSignIn);
  }, [onSignIn]);

  return (
    <div className="page">
      <FlexBox flexDirection="column" gap="12px" sx={{ marginTop: '30vh' }}>
        <Typography variant="title1" weight="bold">
          할 일을 말하면
          <br />
          AI가 끝내 드려요
        </Typography>
        <Typography variant="body1-reading" color="semantic.foreground.neutral.tertiary">
          서류 만들기, 엑셀 정리, 사진 속 글자 옮기기까지
        </Typography>
      </FlexBox>
      <FlexBox flexDirection="column" gap="12px" alignItems="center" sx={{ marginTop: 'auto' }}>
        <div ref={button} style={{ width: '100%', display: 'flex', justifyContent: 'center' }} />
        <Typography variant="label2" color="semantic.foreground.neutral.tertiary" align="center">
          처음이면 가입, 이미 썼다면 로그인돼요. 이름과 이메일만 받아요.
        </Typography>
      </FlexBox>
    </div>
  );
}
