import {
  FlexBox,
  List,
  ListCell,
  ListCellContent,
  TextButton,
  TextField,
  TextFieldButton,
  Typography,
} from '@montage-ui/core';
import { IconChevronDown, IconChevronUp } from '@montage-ui/icon';
import { useState } from 'react';

import { forPersona, othersFor, pickFor, type Recipe } from '../catalog';
import type { Account, Profile } from '../store';

type Props = {
  account: Account | null;
  profile: Profile;
  onRecipe: (r: Recipe) => void;
  onFree: (text: string) => void;
};

function RecipeList({ recipes, pick, onRecipe }: { recipes: Recipe[]; pick?: Recipe; onRecipe: (r: Recipe) => void }) {
  return (
    <List>
      {recipes.map((r) => (
        <ListCell
          key={r.id}
          role="button"
          tabIndex={0}
          verticalPadding="medium"
          onClick={() => onRecipe(r)}
          textProps={{ description: r.can }}
          labelTrailing={
            r === pick ? (
              <Typography variant="caption1" weight="bold" color="semantic.foreground.neutral.tertiary">
                추천
              </Typography>
            ) : undefined
          }
          trailingContent={<ListCellContent chevron />}
        >
          {r.title}
        </ListCell>
      ))}
    </List>
  );
}

export default function Home({ account, profile, onRecipe, onFree }: Props) {
  const [free, setFree] = useState('');
  const [more, setMore] = useState(false);
  const pick = pickFor(profile.persona, profile.routine);
  const mine = forPersona(profile.persona, profile.routine);
  const others = othersFor(profile.persona);
  const first = account?.name.split(/\s+/)[0];

  const submit = () => {
    if (free.trim()) onFree(free.trim());
  };

  return (
    <div className="page">
      <FlexBox flexDirection="column" gap="8px" sx={{ marginTop: '16px' }}>
        <Typography variant="title2" weight="bold">
          {first ? `${first}님, ` : ''}무엇을 맡길까요?
        </Typography>
        <Typography variant="body1" color="semantic.foreground.neutral.tertiary">
          하고 싶은 일을 적거나 아래에서 골라 주세요
        </Typography>
      </FlexBox>

      <TextField
        size="large"
        placeholder="예: 재직증명서 만들어 줘"
        value={free}
        onChange={(e) => setFree(e.target.value)}
        onKeyDown={(e) => e.key === 'Enter' && !e.nativeEvent.isComposing && submit()}
        trailingButton={
          <TextFieldButton disabled={!free.trim()} onClick={submit}>
            맡기기
          </TextFieldButton>
        }
        sx={{ marginTop: '24px' }}
      />

      <Typography variant="heading1" weight="bold" sx={{ marginTop: '40px', marginBottom: '4px' }}>
        이런 일을 맡길 수 있어요
      </Typography>
      <RecipeList recipes={mine} pick={pick} onRecipe={onRecipe} />

      {others.length > 0 && (
        <>
          <TextButton
            color="assistive"
            sx={{ marginTop: '16px', alignSelf: 'flex-start' }}
            trailingContent={more ? <IconChevronUp /> : <IconChevronDown />}
            onClick={() => setMore(!more)}
          >
            다른 일 더 보기
          </TextButton>
          {more && <RecipeList recipes={others} onRecipe={onRecipe} />}
        </>
      )}
    </div>
  );
}
