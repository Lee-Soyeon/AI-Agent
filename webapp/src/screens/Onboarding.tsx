import { Button, Chip, FlexBox, TopNavigation, TopNavigationButton, Typography } from '@montage-ui/core';
import { useState } from 'react';

import { personas, routinesFor } from '../catalog';
import type { Profile } from '../store';

/** 질문 둘: 하는 일, 반복하는 일. 한 화면에 하나씩. */
export default function Onboarding({ onDone }: { onDone: (p: Profile) => void }) {
  const [step, setStep] = useState(0);
  const [persona, setPersona] = useState('');

  const question = step === 0 ? '주로 어떤 일을 하세요?' : '요즘 반복해서 하는 일이 있나요?';
  const why = step === 0 ? '맞는 일부터 보여 드릴게요' : '그 일을 맨 위에 둘게요';
  const options = step === 0 ? personas.map((p) => p.label) : routinesFor(persona);

  const pick = (label: string) => {
    if (step === 0) {
      setPersona(personas.find((p) => p.label === label)?.id ?? 'other');
      setStep(1);
    } else {
      onDone({ persona, routine: label === '없음' ? '' : label });
    }
  };

  return (
    <>
      <TopNavigation
        leadingContent={
          step > 0 ? <TopNavigationButton variant="back-button" onClick={() => setStep(0)} /> : undefined
        }
        trailingContent={
          <TopNavigationButton variant="text-button" color="assistive" onClick={() => onDone({ persona: '', routine: '' })}>
            건너뛰기
          </TopNavigationButton>
        }
      />
      <div className="page">
        <Typography variant="label1" weight="medium" color="semantic.foreground.neutral.tertiary">
          {step + 1} / 2
        </Typography>
        <FlexBox flexDirection="column" gap="8px" sx={{ marginTop: '12px', marginBottom: '32px' }}>
          <Typography variant="title2" weight="bold">
            {question}
          </Typography>
          <Typography variant="body1" color="semantic.foreground.neutral.tertiary">
            {why}
          </Typography>
        </FlexBox>
        <FlexBox flexWrap="wrap" gap="8px">
          {options.map((o) => (
            <Chip key={o} size="large" variant="outlined" onClick={() => pick(o)}>
              {o}
            </Chip>
          ))}
        </FlexBox>
        {step === 1 && (
          <Button
            variant="outlined"
            color="assistive"
            size="large"
            sx={{ marginTop: '32px' }}
            onClick={() => onDone({ persona, routine: '' })}
          >
            나중에 할게요
          </Button>
        )}
      </div>
    </>
  );
}
