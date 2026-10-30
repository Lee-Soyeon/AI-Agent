import { Button, Chip, FlexBox, Loading, TextField, TextFieldButton, TopNavigation, TopNavigationButton, Typography } from '@montage-ui/core';
import { useEffect, useState } from 'react';

import { api, type Task } from '../api';

const STATUS: Record<string, string> = {
  running: '하는 중이에요',
  waiting_approval: '확인이 필요해요',
  waiting_user: '물어볼 게 있어요',
  finished: '다 했어요',
  failed: '하다가 막혔어요',
  cancelled: '멈췄어요',
};

const done = (status: string) => ['finished', 'failed', 'cancelled'].includes(status);

/** 실행 화면: 1.5초마다 진행 상황을 받아 온다. 질문·승인이 오면 답하게 한다. */
export default function TaskView({ id, onBack }: { id: string; onBack: () => void }) {
  const [task, setTask] = useState<Task | null>(null);
  const [answer, setAnswer] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    let alive = true;
    const poll = async () => {
      try {
        const t = await api.task(id);
        if (!alive) return;
        setTask(t);
        if (!done(t.status)) setTimeout(poll, 1500);
      } catch (e) {
        if (alive) setError((e as Error).message);
      }
    };
    void poll();
    return () => {
      alive = false;
    };
  }, [id]);

  const reply = async (text: string) => {
    setAnswer('');
    await api.answer(id, text).catch((e: Error) => setError(e.message));
  };

  const pending = task?.pending;
  const status = task ? (STATUS[task.status] ?? task.status) : '불러오는 중이에요';
  const lastLog = task?.logs.at(-1)?.text;

  return (
    <>
      <TopNavigation leadingContent={<TopNavigationButton variant="back-button" onClick={onBack} />} />
      <div className="page">
        <FlexBox alignItems="center" gap="10px" sx={{ marginTop: '12px' }}>
          {task && !done(task.status) && !pending && <Loading variant="circular" size={20} />}
          <Typography variant="title2" weight="bold">
            {status}
          </Typography>
        </FlexBox>
        {lastLog && !done(task!.status) && (
          <Typography variant="body1" color="semantic.foreground.neutral.tertiary" sx={{ marginTop: '8px' }}>
            {lastLog}
          </Typography>
        )}

        {pending?.type === 'question' && (
          <FlexBox flexDirection="column" gap="12px" sx={{ marginTop: '24px' }}>
            <Typography variant="headline1" weight="bold">
              {pending.question}
            </Typography>
            <FlexBox flexWrap="wrap" gap="8px">
              {(pending.options ?? []).map((o) => (
                <Chip key={o} size="large" variant="outlined" onClick={() => void reply(o)}>
                  {o}
                </Chip>
              ))}
            </FlexBox>
            <TextField
              size="large"
              placeholder="직접 답하기"
              value={answer}
              onChange={(e) => setAnswer(e.target.value)}
              trailingButton={
                <TextFieldButton disabled={!answer.trim()} onClick={() => void reply(answer.trim())}>
                  보내기
                </TextFieldButton>
              }
            />
          </FlexBox>
        )}

        {pending && pending.type !== 'question' && (
          <FlexBox flexDirection="column" gap="12px" sx={{ marginTop: '24px' }}>
            <Typography variant="body2-reading" className="box">
              {String(pending.summary ?? pending.question ?? '진행하기 전에 확인해 주세요')}
            </Typography>
            <FlexBox gap="8px">
              <Button variant="outlined" color="assistive" size="large" onClick={() => void api.approve(id, false)}>
                안 할게요
              </Button>
              <Button size="large" fullWidth onClick={() => void api.approve(id, true)}>
                진행해 주세요
              </Button>
            </FlexBox>
          </FlexBox>
        )}

        {task?.result && (
          <Typography variant="body2-reading" className="box" sx={{ marginTop: '24px' }}>
            {task.result}
          </Typography>
        )}

        {error && (
          <Typography variant="label1" color="semantic.foreground.negative.primary" sx={{ marginTop: '16px' }}>
            {error}
          </Typography>
        )}
      </div>
      {task && !done(task.status) && (
        <div className="bottom-bar">
          <Button variant="outlined" color="assistive" size="large" fullWidth onClick={() => void api.cancel(id)}>
            멈추기
          </Button>
        </div>
      )}
    </>
  );
}
