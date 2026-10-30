import { Button, Chip, FlexBox, TextArea, TextField, TopNavigation, TopNavigationButton, Typography } from '@montage-ui/core';
import { IconUpload } from '@montage-ui/icon';
import { useRef, useState } from 'react';

import { fillPrompt, type Recipe } from '../catalog';

const TEXT_FILE = /\.(txt|csv|md|json|tsv|html?)$/i;

/** 파일은 글자로 읽을 수 있으면 앞 6,000자, 아니면 이름만 넘긴다. */
async function readFile(file: File): Promise<string> {
  if (!TEXT_FILE.test(file.name)) return `(첨부: ${file.name})`;
  const text = (await file.text()).trim();
  return `${file.name}\n${text.length > 6000 ? text.slice(0, 6000) + '\n…(생략)' : text}`;
}

/** 레시피 단계: 한 화면에 질문 하나 (최대 3). 칩은 누르면 바로 다음. */
export default function RecipeSteps({
  recipe,
  onBack,
  onDone,
}: {
  recipe: Recipe;
  onBack: () => void;
  onDone: (prompt: string) => void;
}) {
  const [index, setIndex] = useState(0);
  const [answers, setAnswers] = useState<Record<string, string>>({});
  const [draft, setDraft] = useState('');
  const [fileName, setFileName] = useState('');
  const [freeOpen, setFreeOpen] = useState(false);
  const fileInput = useRef<HTMLInputElement>(null);

  const step = recipe.steps[index];
  const last = index === recipe.steps.length - 1;

  const next = (value: string) => {
    const all = { ...answers, [step.id]: value };
    setAnswers(all);
    setDraft('');
    setFileName('');
    setFreeOpen(false);
    if (last) onDone(fillPrompt(recipe, all));
    else setIndex(index + 1);
  };

  const pickFile = async (file: File | undefined) => {
    if (!file) return;
    setFileName(file.name);
    setDraft(await readFile(file));
  };

  const typed = step.kind === 'keyword' || step.kind === 'text' || freeOpen;
  const isFile = step.kind === 'file' || step.kind === 'photo';

  return (
    <>
      <TopNavigation
        leadingContent={
          <TopNavigationButton variant="back-button" onClick={() => (index === 0 ? onBack() : setIndex(index - 1))} />
        }
      >
        {recipe.title}
      </TopNavigation>
      <div className="page">
        <Typography variant="label1" weight="medium" color="semantic.foreground.neutral.tertiary">
          {index + 1} / {recipe.steps.length}
        </Typography>
        <FlexBox flexDirection="column" gap="8px" sx={{ marginTop: '12px', marginBottom: '32px' }}>
          <Typography variant="title2" weight="bold">
            {step.text}
          </Typography>
          {step.why && (
            <Typography variant="body1" color="semantic.foreground.neutral.tertiary">
              {step.why}
            </Typography>
          )}
        </FlexBox>

        {step.kind === 'chips' && !freeOpen && (
          <FlexBox flexWrap="wrap" gap="8px">
            {(step.options ?? []).map((o) => (
              <Chip key={o} size="large" variant="outlined" onClick={() => next(o)}>
                {o}
              </Chip>
            ))}
            {step.allow_free && (
              <Chip size="large" variant="outlined" onClick={() => setFreeOpen(true)}>
                직접 쓰기
              </Chip>
            )}
          </FlexBox>
        )}

        {typed &&
          (step.kind === 'text' ? (
            <TextArea
              size="large"
              minRows={6}
              placeholder={step.placeholder ?? '여기에 붙여 넣어 주세요'}
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
            />
          ) : (
            <TextField
              size="large"
              autoFocus
              placeholder={step.placeholder ?? '짧게 적어 주세요'}
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && !e.nativeEvent.isComposing && draft.trim() && next(draft.trim())}
            />
          ))}

        {isFile && (
          <>
            <input
              ref={fileInput}
              type="file"
              hidden
              accept={step.kind === 'photo' ? 'image/*' : undefined}
              onChange={(e) => void pickFile(e.target.files?.[0])}
            />
            <Button
              variant="outlined"
              color="assistive"
              size="large"
              fullWidth
              leadingContent={<IconUpload />}
              onClick={() => fileInput.current?.click()}
            >
              {fileName || step.button || '파일 올리기'}
            </Button>
          </>
        )}
      </div>

      {(typed || isFile) && (
        <div className="bottom-bar">
          <Button size="large" fullWidth disabled={!draft.trim()} onClick={() => next(draft.trim())}>
            {last ? '다 됐어요' : '다음'}
          </Button>
        </div>
      )}
    </>
  );
}
