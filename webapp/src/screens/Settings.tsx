import { Button, FlexBox, List, ListCell, ListCellContent, TextField, Typography } from '@montage-ui/core';
import { useState } from 'react';

import { api } from '../api';
import { personas } from '../catalog';
import { googleSignOut } from '../google';
import { type Account, type Profile, store } from '../store';

export default function Settings({
  account,
  profile,
  onEditProfile,
  onSignOut,
}: {
  account: Account | null;
  profile: Profile;
  onEditProfile: () => void;
  onSignOut: () => void;
}) {
  const [url, setUrl] = useState(store.serverUrl());
  const [token, setToken] = useState(store.serverToken());
  const [check, setCheck] = useState('');

  const persona = personas.find((p) => p.id === profile.persona)?.label;
  const profileText = [persona, profile.routine].filter(Boolean).join(' · ') || '아직 안 정했어요';

  const save = async () => {
    store.setServer(url, token);
    setCheck('확인 중…');
    try {
      await api.health();
      setCheck('연결됐어요');
    } catch (e) {
      setCheck((e as Error).message);
    }
  };

  return (
    <div className="page">
      <Typography variant="title2" weight="bold" sx={{ marginTop: '16px', marginBottom: '16px' }}>
        설정
      </Typography>
      <List>
        {account && (
          <ListCell
            verticalPadding="medium"
            textProps={{ description: account.email }}
            trailingContent={
              <Button
                variant="outlined"
                color="assistive"
                size="small"
                onClick={() => {
                  googleSignOut();
                  onSignOut();
                }}
              >
                로그아웃
              </Button>
            }
          >
            {account.name}
          </ListCell>
        )}
        <ListCell
          role="button"
          tabIndex={0}
          verticalPadding="medium"
          textProps={{ description: profileText }}
          trailingContent={<ListCellContent chevron />}
          onClick={onEditProfile}
        >
          하는 일 다시 고르기
        </ListCell>
      </List>

      <Typography variant="heading2" weight="bold" sx={{ marginTop: '32px', marginBottom: '12px' }}>
        에이전트 서버
      </Typography>
      <FlexBox flexDirection="column" gap="8px">
        <TextField size="large" placeholder="https://agent.example.com" value={url} onChange={(e) => setUrl(e.target.value)} />
        <TextField size="large" placeholder="토큰" type="password" value={token} onChange={(e) => setToken(e.target.value)} />
        <Button size="large" variant="outlined" color="assistive" onClick={save}>
          저장하고 연결 확인
        </Button>
        {check && (
          <Typography variant="label1" color="semantic.foreground.neutral.tertiary">
            {check}
          </Typography>
        )}
      </FlexBox>
    </div>
  );
}
