import { Button, FlexBox, TextArea, TopNavigation, TopNavigationButton, Typography } from '@montage-ui/core';
import { useState } from 'react';

import { api } from '../api';

/** "이렇게 시킬까요?" — 에이전트에게 갈 글을 보여 주고, 고칠 수 있게 한다. */
export default function Confirm({
  title,
  prompt,
  onBack,
  onStarted,
}: {
  title: string;
  prompt: string;
  onBack: () => void;
  onStarted: (id: string) => void;
}) {
  const [text, setText] = useState(prompt);
  const [editing, setEditing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const start = async () => {
    setBusy(true);
    setError('');
    try {
      const task = await api.createTask(text);
      onStarted(task.id);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <TopNavigation leadingContent={<TopNavigationButton variant="back-button" onClick={onBack} />}>{title}</TopNavigation>
      <div className="page">
        <FlexBox flexDirection="column" gap="8px" sx={{ marginTop: '12px', marginBottom: '24px' }}>
          <Typography variant="title2" weight="bold">
            이렇게 시킬까요?
          </Typography>
          <Typography variant="body1" color="semantic.foreground.neutral.tertiary">
            AI에게 이 글이 그대로 전달돼요
          </Typography>
        </FlexBox>
        {editing ? (
          <TextArea size="large" minRows={8} value={text} onChange={(e) => setText(e.target.value)} />
        ) : (
          <Typography variant="body2-reading" className="box">
            {text}
          </Typography>
        )}
        {error && (
          <Typography variant="label1" color="semantic.foreground.negative.primary" sx={{ marginTop: '12px' }}>
            {error}
          </Typography>
        )}
      </div>
      <div className="bottom-bar">
        <FlexBox gap="8px">
          <Button variant="outlined" color="assistive" size="large" onClick={() => setEditing(!editing)}>
            {editing ? '다 고쳤어요' : '고치기'}
          </Button>
          <Button size="large" fullWidth loading={busy} disabled={!text.trim()} onClick={start}>
            시키기
          </Button>
        </FlexBox>
      </div>
    </>
  );
}
