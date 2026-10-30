import tasks from '../../server/app/tasks.json';

// 레시피 카탈로그 — Flutter 앱·서버와 같은 server/app/tasks.json.

export type StepKind = 'file' | 'photo' | 'text' | 'chips' | 'keyword';

export type Step = {
  id: string;
  kind: StepKind;
  text: string;
  why?: string;
  placeholder?: string;
  button?: string;
  accept?: string;
  options?: string[];
  allow_free?: boolean;
};

export type Recipe = {
  id: string;
  title: string;
  can: string;
  cannot?: string;
  personas: string[];
  steps: Step[];
  prompt_template: string;
};

export type Persona = { id: string; label: string };

export const personas = tasks.personas as Persona[];
export const recipes = tasks.recipes as unknown as Recipe[];
const routines = tasks.routines as Record<string, string[]>;

export const routinesFor = (persona: string) => routines[persona] ?? routines.other ?? ['없음'];

const routineWord = (routine: string) => {
  const word = routine.trim().split(/\s+/)[0] ?? '';
  return word.length >= 2 && word !== '없음' ? word : '';
};

const matches = (r: Recipe, word: string) => !!word && (r.title.includes(word) || r.can.includes(word));

/** 내 직업에 맞는 것만. 반복하는 일과 이름이 겹치는 것이 맨 앞. 직업을 안 골랐으면 전부. */
export function forPersona(persona: string, routine = ''): Recipe[] {
  if (!persona) return recipes;
  const mine = recipes.filter((r) => r.personas.includes(persona));
  const word = routineWord(routine);
  return [...mine.filter((r) => matches(r, word)), ...mine.filter((r) => !matches(r, word))];
}

export const othersFor = (persona: string) => (persona ? recipes.filter((r) => !r.personas.includes(persona)) : []);

/** 반복하는 일과 맞는 레시피 (추천 표시). */
export function pickFor(persona: string, routine: string): Recipe | undefined {
  const first = forPersona(persona, routine)[0];
  return first && matches(first, routineWord(routine)) ? first : undefined;
}

/** server/app/recipes.py fill_prompt 와 같다: {id} 자리를 답으로, 없는 자리는 빈칸. */
export const fillPrompt = (recipe: Recipe, answers: Record<string, string>) =>
  recipe.prompt_template.replace(/\{(\w+)\}/g, (_, id: string) => answers[id] ?? '').trim();
