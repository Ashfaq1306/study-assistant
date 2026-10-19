import { randomInt } from 'node:crypto';
import {
  AiUnavailableError,
  type AiProvider,
  type ExamSpec,
  type GeneratedQuestion,
  type ShortAnswerGrade,
  type ShortAnswerToGrade,
} from './ai.types.js';
import type { QuestionType } from '../sessions/sessions.schemas.js';

type BankItem = Omit<GeneratedQuestion, 'keyPoints'> & { keyPoints?: string[] };

/** A small, checked bank used only when no AI key is configured. */
const BANK: Record<string, BankItem[]> = {
  science: [
    { type: 'MCQ', prompt: 'Which gas do plants take in for photosynthesis?', options: ['Oxygen', 'Carbon dioxide', 'Nitrogen', 'Helium'], answer: '1', explanation: 'Plants use carbon dioxide, water and sunlight to make food.' },
    { type: 'MCQ', prompt: 'What is the boiling point of water at sea level?', options: ['50 °C', '90 °C', '100 °C', '120 °C'], answer: '2', explanation: 'Pure water boils at 100 °C at sea level.' },
    { type: 'TRUE_FALSE', prompt: 'The Sun is a star.', options: [], answer: 'true', explanation: 'The Sun is the star at the centre of our solar system.' },
    { type: 'TRUE_FALSE', prompt: 'Sound travels faster than light.', options: [], answer: 'false', explanation: 'Light is far faster than sound.' },
    { type: 'MCQ', prompt: 'Which organ pumps blood around the body?', options: ['Lungs', 'Liver', 'Heart', 'Kidney'], answer: '2', explanation: 'The heart pumps blood through the blood vessels.' },
    { type: 'SHORT', prompt: 'What do we call the process by which plants make their own food?', options: [], answer: 'Photosynthesis', keyPoints: ['photosynthesis'], explanation: 'Photosynthesis uses sunlight to make food.' },
    { type: 'MCQ', prompt: 'What is H2O commonly called?', options: ['Salt', 'Water', 'Sugar', 'Air'], answer: '1', explanation: 'H2O is water: two hydrogen atoms and one oxygen atom.' },
    { type: 'TRUE_FALSE', prompt: 'Ice is the solid form of water.', options: [], answer: 'true', explanation: 'Water freezes into ice at 0 °C.' },
  ],
  english: [
    { type: 'MCQ', prompt: 'Which word is a noun?', options: ['Quickly', 'Happy', 'River', 'Run'], answer: '2', explanation: 'A noun names a person, place or thing: river.' },
    { type: 'MCQ', prompt: 'Choose the correct past tense of "go".', options: ['Goed', 'Went', 'Gone', 'Going'], answer: '1', explanation: '"Went" is the simple past of "go".' },
    { type: 'TRUE_FALSE', prompt: '"Their" and "there" mean the same thing.', options: [], answer: 'false', explanation: '"Their" shows ownership; "there" is a place.' },
    { type: 'MCQ', prompt: 'What is the plural of "child"?', options: ['Childs', 'Childes', 'Children', 'Childrens'], answer: '2', explanation: '"Children" is an irregular plural.' },
    { type: 'SHORT', prompt: 'Write the opposite of "ancient".', options: [], answer: 'Modern', keyPoints: ['modern'], explanation: 'Ancient means very old; modern means new.' },
    { type: 'TRUE_FALSE', prompt: 'An adjective describes a noun.', options: [], answer: 'true', explanation: 'Adjectives like "tall" or "red" describe nouns.' },
  ],
  ict: [
    { type: 'MCQ', prompt: 'What does CPU stand for?', options: ['Central Processing Unit', 'Computer Power Unit', 'Central Program Utility', 'Core Print Unit'], answer: '0', explanation: 'The CPU is the computer’s main processor.' },
    { type: 'TRUE_FALSE', prompt: 'RAM keeps its data when the computer is switched off.', options: [], answer: 'false', explanation: 'RAM is temporary memory and is cleared when power is off.' },
    { type: 'MCQ', prompt: 'Which of these is an input device?', options: ['Monitor', 'Printer', 'Keyboard', 'Speaker'], answer: '2', explanation: 'A keyboard sends input to the computer.' },
    { type: 'SHORT', prompt: 'How many bits make one byte?', options: [], answer: '8', keyPoints: ['8'], explanation: 'One byte is 8 bits.' },
    { type: 'TRUE_FALSE', prompt: 'A strong password mixes letters, numbers and symbols.', options: [], answer: 'true', explanation: 'Mixing character types makes a password harder to guess.' },
  ],
  general: [
    { type: 'MCQ', prompt: 'What is the capital of Bangladesh?', options: ['Chattogram', 'Dhaka', 'Khulna', 'Sylhet'], answer: '1', explanation: 'Dhaka is the capital of Bangladesh.' },
    { type: 'MCQ', prompt: 'How many continents are there?', options: ['5', '6', '7', '8'], answer: '2', explanation: 'There are seven continents.' },
    { type: 'TRUE_FALSE', prompt: 'The Padma is a river in Bangladesh.', options: [], answer: 'true', explanation: 'The Padma is one of the main rivers of Bangladesh.' },
    { type: 'MCQ', prompt: 'Which is the largest ocean?', options: ['Atlantic', 'Indian', 'Arctic', 'Pacific'], answer: '3', explanation: 'The Pacific is the largest ocean.' },
    { type: 'SHORT', prompt: 'In which year did Bangladesh become independent?', options: [], answer: '1971', keyPoints: ['1971'], explanation: 'Bangladesh became independent in 1971.' },
    { type: 'TRUE_FALSE', prompt: 'A week has eight days.', options: [], answer: 'false', explanation: 'A week has seven days.' },
    { type: 'MCQ', prompt: 'Which planet is known as the Red Planet?', options: ['Venus', 'Mars', 'Jupiter', 'Saturn'], answer: '1', explanation: 'Mars looks red because of iron oxide on its surface.' },
  ],
};

const SUBJECT_KEYS: [RegExp, string][] = [
  [/(science|physics|chemistry|biology)/i, 'science'],
  [/(english|grammar)/i, 'english'],
  [/(ict|computer|technology)/i, 'ict'],
];

const pick = <T>(list: readonly T[]): T => list[randomInt(list.length)]!;

function shuffle<T>(list: T[]): T[] {
  const out = [...list];
  for (let i = out.length - 1; i > 0; i--) {
    const j = randomInt(i + 1);
    [out[i], out[j]] = [out[j]!, out[i]!];
  }
  return out;
}

/** An arithmetic question whose answer is computed, so it is always right. */
function mathQuestion(type: QuestionType, difficulty: ExamSpec['difficulty']): GeneratedQuestion {
  const max = difficulty === 'EASY' ? 20 : difficulty === 'MEDIUM' ? 100 : 1000;
  const op = pick(['+', '-', '×'] as const);
  const a = randomInt(2, op === '×' ? Math.min(max, 30) : max);
  const b = randomInt(2, op === '×' ? 12 : max);
  const value = op === '+' ? a + b : op === '-' ? a - b : a * b;
  const expr = `${a} ${op} ${b}`;

  if (type === 'TRUE_FALSE') {
    const shown = randomInt(2) === 0 ? value : value + pick([-2, -1, 1, 2, 10]);
    return {
      type,
      prompt: `${expr} = ${shown}`,
      options: [],
      answer: String(shown === value),
      keyPoints: [],
      explanation: `${expr} = ${value}.`,
    };
  }
  if (type === 'SHORT') {
    return { type, prompt: `Work out ${expr}.`, options: [], answer: String(value), keyPoints: [String(value)], explanation: `${expr} = ${value}.` };
  }
  const wrong = new Set<number>();
  while (wrong.size < 3) {
    const candidate = value + pick([-10, -3, -2, -1, 1, 2, 3, 10]);
    if (candidate !== value) wrong.add(candidate);
  }
  const options = shuffle([value, ...wrong]).map(String);
  return { type, prompt: `What is ${expr}?`, options, answer: String(options.indexOf(String(value))), keyPoints: [], explanation: `${expr} = ${value}.` };
}

const normalize = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();

/**
 * Used when no AI key is configured, so the app still works end to end.
 * Exams are labelled "practice" in the app. The study helper says it is off.
 */
export class PracticeProvider implements AiProvider {
  readonly source = 'PRACTICE' as const;

  generateExam(spec: ExamSpec): Promise<GeneratedQuestion[]> {
    const isMath = /math|arithmetic|algebra/i.test(spec.subject);
    const bankKey = SUBJECT_KEYS.find(([re]) => re.test(spec.subject))?.[1] ?? 'general';
    const pool = shuffle(BANK[bankKey]!.filter((q) => spec.types.includes(q.type)));
    const questions: GeneratedQuestion[] = [];
    for (let i = 0; i < spec.count; i++) {
      const type = spec.types[i % spec.types.length]!;
      const fromBank = !isMath && pool.length > 0 ? pool.shift() : undefined;
      questions.push(fromBank ? { keyPoints: [], ...fromBank } : mathQuestion(type, spec.difficulty));
    }
    return Promise.resolve(questions);
  }

  /** Right if it matches the model answer or contains every key point. */
  gradeShortAnswers(items: ShortAnswerToGrade[]): Promise<ShortAnswerGrade[]> {
    return Promise.resolve(
      items.map((item) => {
        const given = normalize(item.studentAnswer);
        const right =
          given.length > 0 &&
          (given === normalize(item.modelAnswer) ||
            (item.keyPoints.length > 0 && item.keyPoints.every((k) => given.includes(normalize(k)))));
        return {
          id: item.id,
          score: right ? 1 : 0,
          feedback: right ? 'Correct!' : `The answer is: ${item.modelAnswer}`,
        };
      }),
    );
  }

  tutor(): Promise<string> {
    return Promise.reject(new AiUnavailableError('The AI study helper is not switched on yet. Ask the app admin to set it up.'));
  }
}
