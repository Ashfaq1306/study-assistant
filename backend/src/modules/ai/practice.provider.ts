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
    { type: 'MCQ', prompt: 'What is the centre of an atom called?', options: ['Electron', 'Nucleus', 'Shell', 'Molecule'], answer: '1', explanation: 'Protons and neutrons sit in the nucleus at the centre of an atom.' },
    { type: 'MCQ', prompt: 'Which force pulls objects towards the Earth?', options: ['Friction', 'Magnetism', 'Gravity', 'Tension'], answer: '2', explanation: 'Gravity pulls masses towards each other, so things fall to the ground.' },
    { type: 'MCQ', prompt: 'What is the unit of force?', options: ['Joule', 'Watt', 'Newton', 'Volt'], answer: '2', explanation: 'Force is measured in newtons (N).' },
    { type: 'MCQ', prompt: 'Which part of a plant cell carries out photosynthesis?', options: ['Nucleus', 'Chloroplast', 'Cell wall', 'Vacuole'], answer: '1', explanation: 'Chloroplasts contain chlorophyll, which captures light energy.' },
    { type: 'MCQ', prompt: 'Which planet is closest to the Sun?', options: ['Venus', 'Earth', 'Mercury', 'Mars'], answer: '2', explanation: 'Mercury orbits closest to the Sun.' },
    { type: 'MCQ', prompt: 'What is the chemical symbol for sodium?', options: ['So', 'Sd', 'Na', 'S'], answer: '2', explanation: 'Sodium’s symbol Na comes from its Latin name, natrium.' },
    { type: 'MCQ', prompt: 'Which blood cells help fight infection?', options: ['Red blood cells', 'White blood cells', 'Platelets', 'Plasma'], answer: '1', explanation: 'White blood cells defend the body against germs.' },
    { type: 'MCQ', prompt: 'A solution with pH 2 is…', options: ['Strongly acidic', 'Neutral', 'Weakly alkaline', 'Strongly alkaline'], answer: '0', explanation: 'pH below 7 is acidic; 2 is strongly acidic.' },
    { type: 'TRUE_FALSE', prompt: 'Metals are generally good conductors of electricity.', options: [], answer: 'true', explanation: 'Free electrons let metals conduct electricity well.' },
    { type: 'TRUE_FALSE', prompt: 'Humans breathe out mostly oxygen.', options: [], answer: 'false', explanation: 'Breathed-out air is mostly nitrogen; we use some oxygen and add carbon dioxide.' },
    { type: 'SHORT', prompt: 'What gas do humans need to breathe in to live?', options: [], answer: 'Oxygen', keyPoints: ['oxygen'], explanation: 'Our cells use oxygen to release energy from food.' },
  ],
  english: [
    { type: 'MCQ', prompt: 'Which word is a noun?', options: ['Quickly', 'Happy', 'River', 'Run'], answer: '2', explanation: 'A noun names a person, place or thing: river.' },
    { type: 'MCQ', prompt: 'Choose the correct past tense of "go".', options: ['Goed', 'Went', 'Gone', 'Going'], answer: '1', explanation: '"Went" is the simple past of "go".' },
    { type: 'TRUE_FALSE', prompt: '"Their" and "there" mean the same thing.', options: [], answer: 'false', explanation: '"Their" shows ownership; "there" is a place.' },
    { type: 'MCQ', prompt: 'What is the plural of "child"?', options: ['Childs', 'Childes', 'Children', 'Childrens'], answer: '2', explanation: '"Children" is an irregular plural.' },
    { type: 'SHORT', prompt: 'Write the opposite of "ancient".', options: [], answer: 'Modern', keyPoints: ['modern'], explanation: 'Ancient means very old; modern means new.' },
    { type: 'TRUE_FALSE', prompt: 'An adjective describes a noun.', options: [], answer: 'true', explanation: 'Adjectives like "tall" or "red" describe nouns.' },
    { type: 'MCQ', prompt: 'Which word is a verb?', options: ['Table', 'Jump', 'Blue', 'Soft'], answer: '1', explanation: 'A verb is an action word: jump.' },
    { type: 'MCQ', prompt: 'Choose the correct sentence.', options: ['She go to school.', 'She goes to school.', 'She going to school.', 'She gone to school.'], answer: '1', explanation: 'With "she", the present simple verb takes -s: goes.' },
    { type: 'MCQ', prompt: 'What is a synonym of "happy"?', options: ['Sad', 'Angry', 'Joyful', 'Tired'], answer: '2', explanation: 'A synonym has a similar meaning: joyful.' },
    { type: 'MCQ', prompt: 'Which word is an adverb?', options: ['Slowly', 'Slow', 'Slowness', 'Slower'], answer: '0', explanation: 'Adverbs often end in -ly and describe how something is done.' },
    { type: 'MCQ', prompt: 'Pick the correct article: "___ apple a day."', options: ['A', 'An', 'The', 'No article'], answer: '1', explanation: 'Use "an" before a vowel sound: an apple.' },
    { type: 'MCQ', prompt: 'What punctuation ends a question?', options: ['Full stop', 'Comma', 'Question mark', 'Colon'], answer: '2', explanation: 'Questions end with a question mark.' },
    { type: 'MCQ', prompt: 'What is the past tense of "write"?', options: ['Writed', 'Wrote', 'Written', 'Writes'], answer: '1', explanation: '"Wrote" is the simple past; "written" is the past participle.' },
    { type: 'MCQ', prompt: 'Which is a pronoun?', options: ['They', 'Garden', 'Quick', 'Sing'], answer: '0', explanation: 'Pronouns like "they" stand in for nouns.' },
    { type: 'TRUE_FALSE', prompt: 'A sentence should begin with a capital letter.', options: [], answer: 'true', explanation: 'Every sentence starts with a capital letter.' },
    { type: 'TRUE_FALSE', prompt: '"Beautiful" is a verb.', options: [], answer: 'false', explanation: '"Beautiful" is an adjective.' },
    { type: 'SHORT', prompt: 'Write the plural of "mouse" (the animal).', options: [], answer: 'Mice', keyPoints: ['mice'], explanation: '"Mice" is the irregular plural of "mouse".' },
  ],
  ict: [
    { type: 'MCQ', prompt: 'What does CPU stand for?', options: ['Central Processing Unit', 'Computer Power Unit', 'Central Program Utility', 'Core Print Unit'], answer: '0', explanation: 'The CPU is the computer’s main processor.' },
    { type: 'TRUE_FALSE', prompt: 'RAM keeps its data when the computer is switched off.', options: [], answer: 'false', explanation: 'RAM is temporary memory and is cleared when power is off.' },
    { type: 'MCQ', prompt: 'Which of these is an input device?', options: ['Monitor', 'Printer', 'Keyboard', 'Speaker'], answer: '2', explanation: 'A keyboard sends input to the computer.' },
    { type: 'SHORT', prompt: 'How many bits make one byte?', options: [], answer: '8', keyPoints: ['8'], explanation: 'One byte is 8 bits.' },
    { type: 'TRUE_FALSE', prompt: 'A strong password mixes letters, numbers and symbols.', options: [], answer: 'true', explanation: 'Mixing character types makes a password harder to guess.' },
    { type: 'MCQ', prompt: 'Which of these is an output device?', options: ['Mouse', 'Scanner', 'Microphone', 'Printer'], answer: '3', explanation: 'A printer puts information out on paper.' },
    { type: 'MCQ', prompt: 'What does "www" stand for?', options: ['World Wide Web', 'Wide Web World', 'World Web Wire', 'Web Wide World'], answer: '0', explanation: 'www is short for World Wide Web.' },
    { type: 'MCQ', prompt: 'Which of these is an operating system?', options: ['Google Chrome', 'Android', 'Microsoft Word', 'WhatsApp'], answer: '1', explanation: 'Android runs the phone; the others are apps.' },
    { type: 'MCQ', prompt: 'What is the binary number 101 in decimal?', options: ['3', '5', '6', '101'], answer: '1', explanation: '101 in binary is 4 + 0 + 1 = 5.' },
    { type: 'MCQ', prompt: 'Which storage is the largest?', options: ['1 KB', '1 MB', '1 GB', '1 TB'], answer: '3', explanation: '1 TB is about a thousand GB.' },
    { type: 'MCQ', prompt: 'What does "LAN" stand for?', options: ['Large Area Network', 'Local Area Network', 'Long Access Node', 'Linked Area Net'], answer: '1', explanation: 'A LAN connects computers in a small area like a school.' },
    { type: 'MCQ', prompt: 'Which language is used to build web page structure?', options: ['HTML', 'Excel', 'PDF', 'JPEG'], answer: '0', explanation: 'HTML describes the structure of a web page.' },
    { type: 'MCQ', prompt: 'What is phishing?', options: ['A fishing game', 'Tricking people into giving private information', 'A type of keyboard', 'Speeding up the internet'], answer: '1', explanation: 'Phishing messages pretend to be trusted to steal passwords or data.' },
    { type: 'MCQ', prompt: 'Which device connects a home network to the internet?', options: ['Router', 'Monitor', 'Printer', 'Webcam'], answer: '0', explanation: 'A router links your home network to the internet.' },
    { type: 'TRUE_FALSE', prompt: 'A computer virus can spread through email attachments.', options: [], answer: 'true', explanation: 'Opening unknown attachments can install harmful software.' },
    { type: 'TRUE_FALSE', prompt: 'An SSD has moving parts.', options: [], answer: 'false', explanation: 'SSDs use flash memory and have no moving parts.' },
    { type: 'SHORT', prompt: 'What does "AI" stand for?', options: [], answer: 'Artificial intelligence', keyPoints: ['artificial', 'intelligence'], explanation: 'AI means artificial intelligence.' },
  ],
  general: [
    { type: 'MCQ', prompt: 'What is the capital of Bangladesh?', options: ['Chattogram', 'Dhaka', 'Khulna', 'Sylhet'], answer: '1', explanation: 'Dhaka is the capital of Bangladesh.' },
    { type: 'MCQ', prompt: 'How many continents are there?', options: ['5', '6', '7', '8'], answer: '2', explanation: 'There are seven continents.' },
    { type: 'TRUE_FALSE', prompt: 'The Padma is a river in Bangladesh.', options: [], answer: 'true', explanation: 'The Padma is one of the main rivers of Bangladesh.' },
    { type: 'MCQ', prompt: 'Which is the largest ocean?', options: ['Atlantic', 'Indian', 'Arctic', 'Pacific'], answer: '3', explanation: 'The Pacific is the largest ocean.' },
    { type: 'SHORT', prompt: 'In which year did Bangladesh become independent?', options: [], answer: '1971', keyPoints: ['1971'], explanation: 'Bangladesh became independent in 1971.' },
    { type: 'TRUE_FALSE', prompt: 'A week has eight days.', options: [], answer: 'false', explanation: 'A week has seven days.' },
    { type: 'MCQ', prompt: 'Which planet is known as the Red Planet?', options: ['Venus', 'Mars', 'Jupiter', 'Saturn'], answer: '1', explanation: 'Mars looks red because of iron oxide on its surface.' },
    { type: 'MCQ', prompt: 'What is the national flower of Bangladesh?', options: ['Rose', 'Water lily (shapla)', 'Lotus', 'Sunflower'], answer: '1', explanation: 'The water lily, shapla, is the national flower.' },
    { type: 'MCQ', prompt: 'Which river is usually listed as the longest in the world?', options: ['Amazon', 'Nile', 'Ganges', 'Mississippi'], answer: '1', explanation: 'The Nile is usually listed as the longest river.' },
    { type: 'MCQ', prompt: 'On which date is Bangladesh’s Victory Day?', options: ['26 March', '21 February', '16 December', '14 April'], answer: '2', explanation: 'Victory Day is 16 December.' },
    { type: 'MCQ', prompt: 'International Mother Language Day is on…', options: ['21 February', '26 March', '1 May', '16 December'], answer: '0', explanation: 'It remembers the 1952 Language Movement on 21 February.' },
    { type: 'MCQ', prompt: 'Which is the largest mangrove forest in the world?', options: ['Amazon', 'Sundarbans', 'Black Forest', 'Congo'], answer: '1', explanation: 'The Sundarbans, shared by Bangladesh and India, is the largest mangrove forest.' },
    { type: 'MCQ', prompt: 'How many days are in a leap year?', options: ['364', '365', '366', '367'], answer: '2', explanation: 'A leap year adds 29 February: 366 days.' },
    { type: 'MCQ', prompt: 'Which is the largest planet in our solar system?', options: ['Earth', 'Saturn', 'Jupiter', 'Neptune'], answer: '2', explanation: 'Jupiter is the largest planet.' },
    { type: 'TRUE_FALSE', prompt: 'Mount Everest is the highest mountain above sea level.', options: [], answer: 'true', explanation: 'Everest is about 8,849 m above sea level.' },
    { type: 'TRUE_FALSE', prompt: 'Bangladesh’s Independence Day is on 16 December.', options: [], answer: 'false', explanation: 'Independence Day is 26 March; 16 December is Victory Day.' },
    { type: 'SHORT', prompt: 'What is the national language of Bangladesh?', options: [], answer: 'Bangla', keyPoints: ['bangla'], explanation: 'Bangla (Bengali) is the national language.' },
  ],
};

const SUBJECT_KEYS: [RegExp, string][] = [
  [/(science|physics|chemistry|biology)/i, 'science'],
  [/(english|grammar)/i, 'english'],
  [/(ict|computer|technology|programming|coding)/i, 'ict'],
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
    // The subject's own questions first, then general knowledge, then arithmetic.
    const usable = (key: string) => shuffle(BANK[key]!.filter((q) => spec.types.includes(q.type)));
    const pool = isMath ? [] : [...usable(bankKey), ...(bankKey === 'general' ? [] : usable('general'))];
    const questions: GeneratedQuestion[] = [];
    for (let i = 0; i < spec.count; i++) {
      const type = spec.types[i % spec.types.length]!;
      const fromBank = pool.shift();
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
