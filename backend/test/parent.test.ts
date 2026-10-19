import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import type { AiProvider, ExamSpec, GeneratedQuestion, ShortAnswerToGrade } from '../src/modules/ai/ai.types.js';
import { bearer, createTestApp, DOB, prisma, resetDatabase, signUp, type SignedInAccount, type TestContext } from './helpers.js';

/** Deterministic AI: every MCQ answer is option 1 ("B"). */
class FakeAi implements AiProvider {
  readonly source = 'AI' as const;
  generateExam(spec: ExamSpec): Promise<GeneratedQuestion[]> {
    return Promise.resolve(
      Array.from({ length: spec.count }, (_, i) => ({
        type: 'MCQ' as const,
        prompt: `Q${i}?`,
        options: ['A', 'B', 'C', 'D'],
        answer: '1',
        keyPoints: [],
        explanation: 'B is right.',
      })),
    );
  }
  gradeShortAnswers(items: ShortAnswerToGrade[]) {
    return Promise.resolve(items.map((i) => ({ id: i.id, score: 1, feedback: 'Good' })));
  }
  tutor(): Promise<string> {
    return Promise.resolve('Hello');
  }
}

let ctx: TestContext;
let parent: SignedInAccount;
let child: SignedInAccount;
const MIN = 60_000;

const as = (account: SignedInAccount) => ({
  get: (url: string) => ctx.app.inject({ method: 'GET', url, headers: bearer(account.accessToken) }),
  post: (url: string, payload: object = {}) =>
    ctx.app.inject({ method: 'POST', url, payload, headers: bearer(account.accessToken) }),
  put: (url: string, payload: object) => ctx.app.inject({ method: 'PUT', url, payload, headers: bearer(account.accessToken) }),
});

const link = async (p: SignedInAccount, c: SignedInAccount) => {
  const { code } = (await as(c).post('/v1/family/pairing-code')).json();
  expect((await as(p).post('/v1/family/links', { code })).statusCode).toBe(201);
};

const registerPhone = async (account: SignedInAccount, previousDeviceToken?: string) => {
  const res = await as(account).post('/v1/devices', { name: 'Galaxy A12', platform: 'android', previousDeviceToken });
  return res;
};

const heartbeat = (token: string, payload: object = {}) =>
  ctx.app.inject({
    method: 'POST',
    url: '/v1/device/heartbeat',
    headers: { 'x-device-token': token },
    payload: { protectionOn: true, ...payload },
  });

const lockBody = (over: Record<string, unknown> = {}) => ({
  title: 'Homework first',
  subject: 'Maths',
  topics: 'Fractions',
  lockedApps: ['com.google.android.youtube'],
  exam: { questionCount: 4, totalMarks: 10, passMarks: 6, questionTypes: ['MCQ'] },
  ...over,
});

const questionSet = {
  title: 'Fractions check',
  subject: 'Maths',
  questions: [
    { type: 'MCQ', prompt: 'What is 1/2 + 1/4?', options: ['3/4', '2/6', '1/6', '2/4'], answer: '0', explanation: 'Quarters.' },
    { type: 'TRUE_FALSE', prompt: '2/4 equals 1/2.', answer: 'true' },
    { type: 'SHORT', prompt: 'Write one half as a decimal.', answer: '0.5', keyPoints: ['0.5'] },
  ],
};

const rightAnswer = (q: { type: string; options: string[] }, set = questionSet.questions) => {
  if (q.type === 'TRUE_FALSE') return 'true';
  if (q.type === 'SHORT') return '0.5';
  // Options are shuffled per attempt: find the right one by text for the set, or "B" for the AI.
  const right = set[0]!.options!.includes(q.options[0]!) ? '3/4' : 'B';
  return String(q.options.indexOf(right));
};

beforeEach(async () => {
  await resetDatabase();
  ctx = await createTestApp({ ai: new FakeAi() });
  parent = await signUp(ctx, { role: 'PARENT', dateOfBirth: DOB.parent, name: 'Ammu Rahman' });
  child = await signUp(ctx, { dateOfBirth: DOB.student16, name: 'Tania' });
  await link(parent, child);
});

afterAll(async () => {
  await prisma.$disconnect();
});

describe('children', () => {
  it('a parent sees each linked child with today at a glance', async () => {
    const { deviceToken } = (await registerPhone(child)).json();
    await heartbeat(deviceToken);
    const res = await as(parent).get('/v1/parent/children');
    expect(res.statusCode).toBe(200);
    const [summary] = res.json().children;
    expect(summary).toMatchObject({
      id: child.userId,
      name: 'Tania',
      age: 16,
      activeSession: null,
      activeLocks: [],
      protection: { status: 'ON' },
    });
  });

  it('only for parents, and only their own children', async () => {
    expect((await as(child).get('/v1/parent/children')).statusCode).toBe(403);
    const stranger = await signUp(ctx, { role: 'PARENT', dateOfBirth: DOB.parent });
    expect((await as(stranger).get(`/v1/parent/children/${child.userId}`)).statusCode).toBe(404);
    expect((await as(stranger).post(`/v1/parent/children/${child.userId}/locks`, lockBody())).statusCode).toBe(404);
  });

  it('shows screen time per day with app names, and the apps on the phone', async () => {
    const { deviceToken } = (await registerPhone(child)).json();
    await heartbeat(deviceToken, {
      installedApps: [{ package: 'com.google.android.youtube', label: 'YouTube' }],
      usage: [
        {
          day: '2026-06-01',
          apps: [
            { package: 'com.google.android.youtube', minutes: 45 },
            { package: 'com.whatsapp', minutes: 15 },
          ],
        },
      ],
    });
    const detail = (await as(parent).get(`/v1/parent/children/${child.userId}`)).json();
    expect(detail.todayScreenMinutes).toBe(60);
    expect(detail.screenTime[0]).toMatchObject({ day: '2026-06-01', totalMinutes: 60 });
    expect(detail.screenTime[0].apps[0]).toEqual({ package: 'com.google.android.youtube', label: 'YouTube', minutes: 45 });
    expect(detail.screenTime).toHaveLength(7);
    expect(detail.installedApps).toEqual([{ package: 'com.google.android.youtube', label: 'YouTube' }]);
  });
});

describe('parent locks', () => {
  it('locks the apps until the child passes the exam, then tells the parent', async () => {
    const { deviceToken } = (await registerPhone(child)).json();
    const created = await as(parent).post(`/v1/parent/children/${child.userId}/locks`, lockBody());
    expect(created.statusCode).toBe(201);
    const lock = created.json();

    const state = (await heartbeat(deviceToken)).json();
    expect(state).toMatchObject({ locked: true, packages: ['com.google.android.youtube'] });
    expect(state.reasons).toEqual([{ kind: 'PARENT', id: lock.id, title: 'Homework first', status: 'ACTIVE' }]);
    expect((await as(child).get('/v1/locks')).json().locks).toHaveLength(1);
    expect((await as(child).get('/v1/notifications')).json().notifications[0].kind).toBe('PARENT_LOCK');

    const exam = (await as(child).post(`/v1/locks/${lock.id}/exam`)).json();
    expect(exam.parentLockId).toBe(lock.id);
    const answers = Object.fromEntries(exam.questions.map((q: { id: string; type: string; options: string[] }) => [q.id, rightAnswer(q)]));
    const graded = (await as(child).post(`/v1/exams/${exam.id}/submit`, { answers })).json();
    expect(graded.result.passed).toBe(true);

    expect((await heartbeat(deviceToken)).json().locked).toBe(false);
    expect((await as(child).get('/v1/locks')).json().locks).toEqual([]);
    const alerts = (await as(parent).get('/v1/notifications')).json();
    expect(alerts.notifications[0]).toMatchObject({ kind: 'LOCK_PASSED', title: 'Tania unlocked "Homework first"' });
    expect(alerts.unread).toBe(1);
  });

  it('a failed exam keeps the lock and the parent hears about it', async () => {
    const lock = (await as(parent).post(`/v1/parent/children/${child.userId}/locks`, lockBody())).json();
    const exam = (await as(child).post(`/v1/locks/${lock.id}/exam`)).json();
    await as(child).post(`/v1/exams/${exam.id}/submit`, { answers: {} });
    expect((await as(child).get('/v1/locks')).json().locks).toHaveLength(1);
    expect((await as(parent).get('/v1/notifications')).json().notifications[0].kind).toBe('EXAM_FAILED');
    // A fresh try straight away, as with a study session.
    const retry = (await as(child).post(`/v1/locks/${lock.id}/exam`)).json();
    expect(retry.id).not.toBe(exam.id);
  });

  it('keeps the pass mark at 50% or more', async () => {
    const res = await as(parent).post(
      `/v1/parent/children/${child.userId}/locks`,
      lockBody({ exam: { questionCount: 4, totalMarks: 10, passMarks: 4, questionTypes: ['MCQ'] } }),
    );
    expect(res.statusCode).toBe(400);
    expect(res.json().error.details.fields['exam.passMarks']).toBeDefined();
  });

  it('the parent who set it can lift it; nobody else can', async () => {
    const { deviceToken } = (await registerPhone(child)).json();
    const lock = (await as(parent).post(`/v1/parent/children/${child.userId}/locks`, lockBody())).json();
    const other = await signUp(ctx, { role: 'PARENT', dateOfBirth: DOB.parent });
    await link(other, child);
    expect((await as(other).post(`/v1/parent/locks/${lock.id}/cancel`)).statusCode).toBe(404);
    expect((await as(child).post(`/v1/parent/locks/${lock.id}/cancel`)).statusCode).toBe(403);

    const lifted = await as(parent).post(`/v1/parent/locks/${lock.id}/cancel`);
    expect(lifted.json().status).toBe('CANCELLED');
    expect((await heartbeat(deviceToken)).json().locked).toBe(false);
  });

  it('whole phone, strict for younger children, and at most 5 at a time', async () => {
    const young = await signUp(ctx, { dateOfBirth: DOB.student12 });
    await link(parent, young);
    const lock = (await as(parent).post(`/v1/parent/children/${young.userId}/locks`, lockBody({ lockedApps: ['*', 'com.x.y'] }))).json();
    expect(lock).toMatchObject({ lockedApps: ['*'], strict: true });

    for (let i = 0; i < 4; i++) await as(parent).post(`/v1/parent/children/${young.userId}/locks`, lockBody());
    const sixth = await as(parent).post(`/v1/parent/children/${young.userId}/locks`, lockBody());
    expect(sixth.json().error.code).toBe('TOO_MANY_LOCKS');
  });
});

describe('question sets', () => {
  it('validates questions', async () => {
    const bad = await as(parent).post('/v1/parent/question-sets', {
      ...questionSet,
      questions: [{ type: 'MCQ', prompt: 'Pick', options: ['a', 'a', 'b', 'c'], answer: '9' }, ...questionSet.questions],
    });
    expect(bad.statusCode).toBe(400);
    expect(Object.keys(bad.json().error.details.fields)).toEqual(
      expect.arrayContaining(['questions.0.options', 'questions.0.answer']),
    );
  });

  it("a lock with the parent's questions: shuffled, answers hidden until passed", async () => {
    const set = (await as(parent).post('/v1/parent/question-sets', questionSet)).json();
    expect(set.questions).toHaveLength(3);
    const lock = (
      await as(parent).post(
        `/v1/parent/children/${child.userId}/locks`,
        lockBody({ questionSetId: set.id, exam: { questionCount: 3, totalMarks: 6, passMarks: 6, questionTypes: ['MCQ'] } }),
      )
    ).json();
    expect(lock.exam).toMatchObject({ questionCount: 3, questionTypes: ['MCQ', 'TRUE_FALSE', 'SHORT'] });

    // In use: can't be changed under the child.
    expect((await as(parent).put(`/v1/parent/question-sets/${set.id}`, questionSet)).json().error.code).toBe('SET_IN_USE');

    const first = (await as(child).post(`/v1/locks/${lock.id}/exam`)).json();
    expect(first.source).toBe('PARENT');
    expect(first.questions.map((q: { prompt: string }) => q.prompt).sort()).toEqual(
      questionSet.questions.map((q) => q.prompt).sort(),
    );
    const failed = (await as(child).post(`/v1/exams/${first.id}/submit`, { answers: {} })).json();
    expect(failed.result.passed).toBe(false);
    for (const r of failed.result.questions) expect(r).toMatchObject({ correctAnswer: '', explanation: '' });

    ctx.clock.advance(3 * MIN);
    const second = (await as(child).post(`/v1/locks/${lock.id}/exam`)).json();
    const answers = Object.fromEntries(
      second.questions.map((q: { id: string; type: string; options: string[] }) => [q.id, rightAnswer(q)]),
    );
    const passed = (await as(child).post(`/v1/exams/${second.id}/submit`, { answers })).json();
    expect(passed.result).toMatchObject({ score: 6, passed: true });
    expect(passed.result.questions.find((r: { correctAnswer: string }) => r.correctAnswer === '3/4')).toBeDefined();
  });

  it('lists, updates and deletes sets that are not in use', async () => {
    const set = (await as(parent).post('/v1/parent/question-sets', questionSet)).json();
    const updated = (await as(parent).put(`/v1/parent/question-sets/${set.id}`, { ...questionSet, title: 'Halves' })).json();
    expect(updated.title).toBe('Halves');
    expect((await as(parent).get('/v1/parent/question-sets')).json().questionSets).toHaveLength(1);
    const del = await ctx.app.inject({
      method: 'DELETE',
      url: `/v1/parent/question-sets/${set.id}`,
      headers: bearer(parent.accessToken),
    });
    expect(del.statusCode).toBe(204);
  });
});

describe('alerts and phones', () => {
  it('tells parents once when App lock is switched off, and when studying starts', async () => {
    const { deviceToken } = (await registerPhone(child)).json();
    await heartbeat(deviceToken);
    await heartbeat(deviceToken, { protectionOn: false });
    await heartbeat(deviceToken, { protectionOn: false });
    await as(child).post('/v1/sessions', {
      subject: 'Maths',
      topics: 'Fractions',
      plannedMinutes: 10,
      lockedApps: [],
      exam: { questionCount: 4, totalMarks: 10, passMarks: 6, questionTypes: ['MCQ'] },
    });
    const { notifications, unread } = (await as(parent).get('/v1/notifications')).json();
    expect(notifications.map((n: { kind: string }) => n.kind)).toEqual(['SESSION_STARTED', 'PROTECTION_OFF']);
    expect(unread).toBe(2);

    expect((await as(parent).post('/v1/notifications/read', {})).statusCode).toBe(204);
    expect((await as(parent).get('/v1/notifications')).json().unread).toBe(0);
  });

  it("handing a phone to a sibling retires the old registration, but not during the old owner's lock", async () => {
    const sibling = await signUp(ctx, { dateOfBirth: DOB.student16 });
    const { deviceToken } = (await registerPhone(child)).json();

    const lock = (await as(parent).post(`/v1/parent/children/${child.userId}/locks`, lockBody())).json();
    expect((await registerPhone(sibling, deviceToken)).json().error.code).toBe('LOCK_ACTIVE');

    await as(parent).post(`/v1/parent/locks/${lock.id}/cancel`);
    expect((await registerPhone(sibling, deviceToken)).statusCode).toBe(201);
    expect((await as(child).get('/v1/devices')).json().devices).toEqual([]);
    expect((await heartbeat(deviceToken)).statusCode).toBe(401);
  });
});
