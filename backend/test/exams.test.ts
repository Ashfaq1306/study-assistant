import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import {
  AiUnavailableError,
  type AiProvider,
  type ExamSpec,
  type GeneratedQuestion,
  type ShortAnswerToGrade,
  type TutorMessage,
} from '../src/modules/ai/ai.types.js';
import { distributeMarks, isValidQuestion } from '../src/modules/exams/exams.service.js';
import { PracticeProvider } from '../src/modules/ai/practice.provider.js';
import { bearer, createTestApp, DOB, prisma, resetDatabase, signUp, type SignedInAccount, type TestContext } from './helpers.js';

/** Deterministic AI: MCQ answer is always option 1, true/false is "true", short is "photosynthesis". */
class FakeAi implements AiProvider {
  readonly source = 'AI' as const;
  failNext = false;
  brokenQuestions = 0;
  shortScore = 1;
  /** Throws this from grading (once) when set. */
  gradeError: Error | null = null;
  /** Leaves these question ids out of the AI's grades. */
  skipGrades = new Set<string>();
  examCalls = 0;
  tutorCalls: TutorMessage[][] = [];

  generateExam(spec: ExamSpec): Promise<GeneratedQuestion[]> {
    this.examCalls++;
    if (this.failNext) {
      this.failNext = false;
      return Promise.reject(new AiUnavailableError('down'));
    }
    return Promise.resolve(
      Array.from({ length: spec.count }, (_, i): GeneratedQuestion => {
        const type = spec.types[i % spec.types.length]!;
        if (i < this.brokenQuestions) return { type: 'MCQ', prompt: 'Broken?', options: ['a'], answer: '7', keyPoints: [], explanation: '' };
        if (type === 'MCQ') return { type, prompt: `Q${i}?`, options: ['A', 'B', 'C', 'D'], answer: '1', keyPoints: [], explanation: 'B is right.' };
        if (type === 'TRUE_FALSE') return { type, prompt: `Statement ${i}`, options: [], answer: 'true', keyPoints: [], explanation: 'It is true.' };
        return { type, prompt: `Explain ${i}`, options: [], answer: 'photosynthesis', keyPoints: ['photosynthesis'], explanation: 'Plants make food.' };
      }),
    );
  }

  gradeShortAnswers(items: ShortAnswerToGrade[]) {
    if (this.gradeError) {
      const err = this.gradeError;
      this.gradeError = null;
      return Promise.reject(err);
    }
    return Promise.resolve(
      items.filter((i) => !this.skipGrades.has(i.id)).map((i) => ({ id: i.id, score: this.shortScore, feedback: 'AI feedback' })),
    );
  }

  tutor(messages: TutorMessage[]): Promise<string> {
    this.tutorCalls.push(messages);
    return Promise.resolve('Plants use sunlight to make food. What do they need besides sunlight?');
  }
}

let ctx: TestContext;
let ai: FakeAi;
let student: SignedInAccount;
const MIN = 60_000;

beforeEach(async () => {
  await resetDatabase();
  ai = new FakeAi();
  ctx = await createTestApp({ ai });
  student = await signUp(ctx, { dateOfBirth: DOB.student16 });
});

afterAll(async () => {
  await prisma.$disconnect();
});

const as = (account: SignedInAccount) => ({
  get: (url: string) => ctx.app.inject({ method: 'GET', url, headers: bearer(account.accessToken) }),
  post: (url: string, payload: object = {}) => ctx.app.inject({ method: 'POST', url, payload, headers: bearer(account.accessToken) }),
});

const startSession = async (exam: Record<string, unknown> = {}, account = student) => {
  const res = await as(account).post('/v1/sessions', {
    subject: 'Biology',
    topics: 'Photosynthesis',
    plannedMinutes: 10,
    lockedApps: ['com.instagram.android'],
    exam: { questionCount: 4, totalMarks: 10, passMarks: 6, questionTypes: ['MCQ', 'TRUE_FALSE'], ...exam },
  });
  expect(res.statusCode).toBe(201);
  return res.json<{ id: string }>().id;
};

/** Turns on the optional 2-minute break after a failed exam. */
const withBreak = () => prisma.appSetting.create({ data: { key: 'examRetryCooldownSeconds', value: '120' } });

/** Starts a session, lets the timer run out, and opens the exam. */
const examReady = async (exam: Record<string, unknown> = {}) => {
  const sessionId = await startSession(exam);
  ctx.clock.advance(11 * MIN);
  const res = await as(student).post(`/v1/sessions/${sessionId}/exam`);
  expect(res.statusCode).toBe(200);
  return { sessionId, exam: res.json() };
};

type Q = { id: string; type: string };
const rightAnswers = (questions: Q[]) =>
  Object.fromEntries(questions.map((q) => [q.id, q.type === 'MCQ' ? '1' : q.type === 'TRUE_FALSE' ? 'true' : 'Photosynthesis']));
const wrongAnswers = (questions: Q[]) =>
  Object.fromEntries(questions.map((q) => [q.id, q.type === 'MCQ' ? '0' : q.type === 'TRUE_FALSE' ? 'false' : 'no idea']));

describe('helpers', () => {
  it('spreads marks evenly and exactly', () => {
    expect(distributeMarks(10, 4)).toEqual([3, 3, 2, 2]);
    expect(distributeMarks(50, 10).reduce((a, b) => a + b)).toBe(50);
  });

  it('rejects malformed questions', () => {
    const ok = { type: 'MCQ' as const, prompt: 'Q?', options: ['a', 'b', 'c', 'd'], answer: '2', keyPoints: [], explanation: '' };
    expect(isValidQuestion(ok, ['MCQ'])).toBe(true);
    expect(isValidQuestion({ ...ok, answer: '4' }, ['MCQ'])).toBe(false);
    expect(isValidQuestion({ ...ok, options: ['a', 'a', 'b', 'c'] }, ['MCQ'])).toBe(false);
    expect(isValidQuestion(ok, ['TRUE_FALSE'])).toBe(false);
    expect(isValidQuestion({ ...ok, type: 'TRUE_FALSE', options: [], answer: 'maybe' }, ['TRUE_FALSE'])).toBe(false);
  });

  it('practice maths questions are always answerable and correct', async () => {
    const qs = await new PracticeProvider().generateExam({
      subject: 'Mathematics',
      topics: 'Arithmetic',
      difficulty: 'HARD',
      count: 30,
      types: ['MCQ', 'TRUE_FALSE', 'SHORT'],
      age: 12,
    });
    expect(qs).toHaveLength(30);
    for (const q of qs) {
      expect(isValidQuestion(q, ['MCQ', 'TRUE_FALSE', 'SHORT'])).toBe(true);
      if (q.type === 'SHORT') {
        const [a, op, b] = q.prompt.replace('Work out ', '').replace('.', '').split(' ');
        const value = op === '+' ? Number(a) + Number(b) : op === '-' ? Number(a) - Number(b) : Number(a) * Number(b);
        expect(q.answer).toBe(String(value));
      }
    }
  });
});

describe('starting an exam', () => {
  it('waits until studying is over', async () => {
    const sessionId = await startSession();
    const res = await as(student).post(`/v1/sessions/${sessionId}/exam`);
    expect(res.statusCode).toBe(409);
    expect(res.json().error.code).toBe('EXAM_NOT_READY');
  });

  it('builds the exam the student asked for, without revealing answers', async () => {
    const { exam } = await examReady();
    expect(exam).toMatchObject({ source: 'AI', status: 'ACTIVE', totalMarks: 10, passMarks: 6, result: null });
    expect(exam.questions).toHaveLength(4);
    expect(exam.questions.reduce((sum: number, q: { marks: number }) => sum + q.marks, 0)).toBe(10);
    expect(JSON.stringify(exam)).not.toMatch(/"answer"|explanation/);
    const tf = exam.questions.find((q: Q) => q.type === 'TRUE_FALSE');
    expect(tf.options).toEqual(['True', 'False']);
  });

  it('resumes the running exam instead of making a new one', async () => {
    const { sessionId, exam } = await examReady();
    const again = (await as(student).post(`/v1/sessions/${sessionId}/exam`)).json();
    expect(again.id).toBe(exam.id);
    expect(ai.examCalls).toBe(1);
  });

  it('falls back to practice questions when the AI is down, so nobody is stuck', async () => {
    ai.failNext = true;
    const { exam } = await examReady();
    expect(exam.source).toBe('PRACTICE');
    expect(exam.questions).toHaveLength(4);
  });

  it('drops broken AI questions and tops up with practice ones', async () => {
    ai.brokenQuestions = 2;
    const { exam } = await examReady();
    expect(exam.questions).toHaveLength(4);
    expect(exam.questions.filter((q: { prompt: string }) => q.prompt === 'Broken?')).toHaveLength(0);
  });

  it('uses practice questions when the admin switched AI off', async () => {
    await prisma.appSetting.create({ data: { key: 'aiEnabled', value: 'false' } });
    const { exam } = await examReady();
    expect(exam.source).toBe('PRACTICE');
    expect(ai.examCalls).toBe(0);
  });

  it("hides other students' exams", async () => {
    const { exam } = await examReady();
    const other = await signUp(ctx, { dateOfBirth: DOB.student16 });
    expect((await as(other).get(`/v1/exams/${exam.id}`)).statusCode).toBe(404);
    expect((await as(other).post(`/v1/exams/${exam.id}/submit`, { answers: {} })).statusCode).toBe(404);
  });
});

describe('passing and failing', () => {
  it('a pass unlocks the apps and finishes the session', async () => {
    const device = (
      await ctx.app.inject({
        method: 'POST',
        url: '/v1/devices',
        headers: bearer(student.accessToken),
        payload: { name: 'Phone', platform: 'android' },
      })
    ).json<{ deviceToken: string }>();
    const lock = () =>
      ctx.app.inject({ method: 'GET', url: '/v1/device/state', headers: { 'x-device-token': device.deviceToken } });

    const { sessionId, exam } = await examReady();
    expect((await lock()).json().locked).toBe(true);

    const res = await as(student).post(`/v1/exams/${exam.id}/submit`, { answers: rightAnswers(exam.questions) });
    expect(res.statusCode).toBe(200);
    const graded = res.json();
    expect(graded.result).toMatchObject({ score: 10, passed: true });
    expect(graded.result.questions[0]).toMatchObject({ correct: true, correctAnswer: 'B', explanation: 'B is right.' });

    expect((await lock()).json().locked).toBe(false);
    const session = (await as(student).get(`/v1/sessions/${sessionId}`)).json();
    expect(session.status).toBe('PASSED');
    expect((await as(student).get('/v1/sessions/stats')).json().sessionsCompleted).toBe(1);
  });

  it('by default a fail keeps the apps locked and a fresh exam can start straight away', async () => {
    const { sessionId, exam } = await examReady();
    await as(student).post(`/v1/exams/${exam.id}/submit`, { answers: wrongAnswers(exam.questions) });
    expect((await as(student).get(`/v1/sessions/${sessionId}`)).json().status).toBe('EXAM_PENDING');
    const retry = await as(student).post(`/v1/sessions/${sessionId}/exam`);
    expect(retry.statusCode).toBe(200);
    expect(retry.json().id).not.toBe(exam.id);
  });

  it('an admin can ask for a short break before retrying', async () => {
    await withBreak();
    const { sessionId, exam } = await examReady();
    const graded = (await as(student).post(`/v1/exams/${exam.id}/submit`, { answers: wrongAnswers(exam.questions) })).json();
    expect(graded.result).toMatchObject({ score: 0, passed: false });
    expect((await as(student).get(`/v1/sessions/${sessionId}`)).json().status).toBe('EXAM_PENDING');

    const tooSoon = await as(student).post(`/v1/sessions/${sessionId}/exam`);
    expect(tooSoon.statusCode).toBe(429);
    expect(tooSoon.json().error.code).toBe('EXAM_COOLDOWN');

    ctx.clock.advance(121_000);
    const retry = (await as(student).post(`/v1/sessions/${sessionId}/exam`)).json();
    expect(retry.id).not.toBe(exam.id);
    expect(ai.examCalls).toBe(2);
  });

  it('passes at exactly the pass mark', async () => {
    // 4 questions worth 3,3,2,2. Getting the first two right = 6 = pass mark.
    const { exam } = await examReady();
    const answers = wrongAnswers(exam.questions);
    for (const q of exam.questions.slice(0, 2)) answers[q.id] = rightAnswers([q])[q.id]!;
    const graded = (await as(student).post(`/v1/exams/${exam.id}/submit`, { answers })).json();
    expect(graded.result).toMatchObject({ score: 6, passed: true });
  });

  it('grades short answers with the AI (partial credit allowed)', async () => {
    ai.shortScore = 0.5;
    const { exam } = await examReady({ questionTypes: ['SHORT'], questionCount: 3, totalMarks: 9, passMarks: 5 });
    const answers = Object.fromEntries(exam.questions.map((q: Q) => [q.id, 'plants make food']));
    const graded = (await as(student).post(`/v1/exams/${exam.id}/submit`, { answers })).json();
    expect(graded.result).toMatchObject({ score: 4.5, passed: false });
    expect(graded.result.questions[0].feedback).toBe('AI feedback');
  });

  it('counts empty short answers as wrong without asking the AI', async () => {
    const { exam } = await examReady({ questionTypes: ['SHORT'], questionCount: 3, totalMarks: 9, passMarks: 5 });
    const graded = (await as(student).post(`/v1/exams/${exam.id}/submit`, { answers: {} })).json();
    expect(graded.result.score).toBe(0);
  });

  it('grades only once when the student taps submit twice', async () => {
    const { exam } = await examReady();
    const body = { answers: rightAnswers(exam.questions) };
    const [a, b] = await Promise.all([
      as(student).post(`/v1/exams/${exam.id}/submit`, body),
      as(student).post(`/v1/exams/${exam.id}/submit`, body),
    ]);
    expect([a.statusCode, b.statusCode]).toEqual([200, 200]);
    const again = (await as(student).post(`/v1/exams/${exam.id}/submit`, { answers: wrongAnswers(exam.questions) })).json();
    expect(again.result).toMatchObject({ score: 10, passed: true });
  });

  it('a grading crash leaves the exam open, so handing in again works', async () => {
    const { exam } = await examReady({ questionTypes: ['SHORT'], questionCount: 3, totalMarks: 9, passMarks: 5 });
    const answers = Object.fromEntries(exam.questions.map((q: Q) => [q.id, 'photosynthesis']));
    ai.gradeError = new Error('database hiccup');
    const failed = await as(student).post(`/v1/exams/${exam.id}/submit`, { answers });
    expect(failed.statusCode).toBe(500);
    expect((await as(student).get(`/v1/exams/${exam.id}`)).json().status).toBe('ACTIVE');

    const graded = (await as(student).post(`/v1/exams/${exam.id}/submit`, { answers })).json();
    expect(graded.result).toMatchObject({ score: 9, passed: true });
  });

  it('answers the AI did not grade fall back to keyword grading instead of zero', async () => {
    const { exam } = await examReady({ questionTypes: ['SHORT'], questionCount: 3, totalMarks: 9, passMarks: 5 });
    ai.skipGrades = new Set([exam.questions[0].id]);
    const answers = Object.fromEntries(exam.questions.map((q: Q) => [q.id, 'photosynthesis']));
    const graded = (await as(student).post(`/v1/exams/${exam.id}/submit`, { answers })).json();
    expect(graded.result.score).toBe(9);
    expect(graded.result.questions[0].feedback).toBe('Correct!');
  });

  it('two starts at once give one exam, and the retry break still applies', async () => {
    await withBreak();
    const sessionId = await startSession();
    ctx.clock.advance(11 * MIN);
    const [a, b] = await Promise.all([
      as(student).post(`/v1/sessions/${sessionId}/exam`),
      as(student).post(`/v1/sessions/${sessionId}/exam`),
    ]);
    expect(a.json().id).toBe(b.json().id);
    expect(await prisma.exam.count({ where: { status: 'ACTIVE' } })).toBe(1);

    await as(student).post(`/v1/exams/${a.json().id}/submit`, { answers: wrongAnswers(a.json().questions) });
    const again = await as(student).post(`/v1/sessions/${sessionId}/exam`);
    expect(again.json().error.code).toBe('EXAM_COOLDOWN');
  });

  it('an exam left to run out counts as a try: break, then a fresh exam', async () => {
    await withBreak();
    // 4 questions: 6 minutes, then 1 minute of grace; the 2-minute break counts from the time limit.
    const { sessionId, exam } = await examReady();
    ctx.clock.advance(7.5 * MIN);
    const tooSoon = await as(student).post(`/v1/sessions/${sessionId}/exam`);
    expect(tooSoon.json().error.code).toBe('EXAM_COOLDOWN');
    ctx.clock.advance(MIN);
    const retry = await as(student).post(`/v1/sessions/${sessionId}/exam`);
    expect(retry.statusCode).toBe(200);
    expect(retry.json().id).not.toBe(exam.id);
  });

  it('refuses late submissions after the time limit', async () => {
    // 4 questions: 6 minutes plus 1 minute of grace.
    const { exam } = await examReady();
    ctx.clock.advance(8 * MIN);
    const res = await as(student).post(`/v1/exams/${exam.id}/submit`, { answers: rightAnswers(exam.questions) });
    expect(res.statusCode).toBe(409);
    expect(res.json().error.code).toBe('EXAM_EXPIRED');
  });

  it('lists finished exams', async () => {
    const { exam } = await examReady();
    await as(student).post(`/v1/exams/${exam.id}/submit`, { answers: rightAnswers(exam.questions) });
    const list = (await as(student).get('/v1/exams')).json().exams;
    expect(list).toHaveLength(1);
    expect(list[0].result.passed).toBe(true);
  });
});

describe('AI study helper', () => {
  const ask = (account = student, content = 'What is photosynthesis?') =>
    as(account).post('/v1/tutor', { messages: [{ role: 'user', content }] });

  it('answers with the study session as context', async () => {
    await startSession();
    const res = await ask();
    expect(res.statusCode).toBe(200);
    expect(res.json().reply).toMatch(/sunlight/);
    expect(res.json().remainingToday).toBe(59);
  });

  it('takes a break while an exam is open (no help with answers)', async () => {
    await examReady();
    const res = await ask();
    expect(res.statusCode).toBe(409);
    expect(res.json().error.code).toBe('EXAM_IN_PROGRESS');
  });

  it('enforces the daily limit', async () => {
    await prisma.appSetting.create({ data: { key: 'tutorDailyLimit', value: '1' } });
    expect((await ask()).statusCode).toBe(200);
    const second = await ask();
    expect(second.statusCode).toBe(429);
    expect(second.json().error.code).toBe('TUTOR_LIMIT');
  });

  it('says so when AI is off', async () => {
    await prisma.appSetting.create({ data: { key: 'aiEnabled', value: 'false' } });
    expect((await ask()).json().error.code).toBe('AI_OFF');
  });

  it('follows the parent gate for younger students', async () => {
    const young = await signUp(ctx, { dateOfBirth: DOB.student12 });
    expect((await ask(young)).json().error.code).toBe('PARENT_REQUIRED');
  });

  it('parallel questions cannot beat the daily limit', async () => {
    await prisma.appSetting.create({ data: { key: 'tutorDailyLimit', value: '2' } });
    const results = await Promise.all(Array.from({ length: 6 }, () => ask()));
    expect(results.filter((r) => r.statusCode === 200).length).toBeLessThanOrEqual(2);
    expect(await prisma.aiUsage.count({ where: { kind: 'TUTOR' } })).toBeLessThanOrEqual(2);
  });

  it('accepts long helper replies sent back as history', async () => {
    const res = await as(student).post('/v1/tutor', {
      messages: [
        { role: 'user', content: 'Explain' },
        { role: 'assistant', content: 'x'.repeat(5000) },
        { role: 'user', content: 'Thanks, and?' },
      ],
    });
    expect(res.statusCode).toBe(200);
  });

  it('validates the conversation', async () => {
    const res = await as(student).post('/v1/tutor', { messages: [{ role: 'assistant', content: 'Hi' }] });
    expect(res.statusCode).toBe(400);
  });
});
