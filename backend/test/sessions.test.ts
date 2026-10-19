import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import {
  bearer,
  createTestApp,
  DOB,
  prisma,
  resetDatabase,
  signUp,
  type SignedInAccount,
  type TestContext,
} from './helpers.js';

let ctx: TestContext;
let student: SignedInAccount;

beforeEach(async () => {
  await resetDatabase();
  ctx = await createTestApp();
  student = await signUp(ctx, { dateOfBirth: DOB.student16 });
});

afterAll(async () => {
  await prisma.$disconnect();
});

const MIN = 60_000;

const as = (account: SignedInAccount) => ({
  get: (url: string) => ctx.app.inject({ method: 'GET', url, headers: bearer(account.accessToken) }),
  post: (url: string, payload: object = {}) =>
    ctx.app.inject({ method: 'POST', url, payload, headers: bearer(account.accessToken) }),
});

const sessionBody = (overrides: Record<string, unknown> = {}) => ({
  subject: 'Mathematics',
  topics: 'Algebra: linear equations',
  plannedMinutes: 30,
  lockedApps: ['com.facebook.katana', 'com.google.android.youtube', 'com.facebook.katana'],
  exam: { questionCount: 10, totalMarks: 50, passMarks: 25, questionTypes: ['MCQ', 'TRUE_FALSE'], difficulty: 'MEDIUM' },
  ...overrides,
});

const start = async (account = student, overrides: Record<string, unknown> = {}) =>
  as(account).post('/v1/sessions', sessionBody(overrides));

describe('config', () => {
  it('serves public defaults', async () => {
    const res = await ctx.app.inject({ method: 'GET', url: '/v1/config' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ minPassPercent: 50, maxQuestions: 30, aiEnabled: true });
    expect(res.json().subjects).toContain('Mathematics');
  });
});

describe('starting a session', () => {
  it('starts studying with the chosen apps locked', async () => {
    const res = await start();
    expect(res.statusCode).toBe(201);
    const s = res.json();
    expect(s).toMatchObject({ status: 'STUDYING', subject: 'Mathematics', plannedMinutes: 30, strict: true });
    expect(s.lockedApps).toEqual(['com.facebook.katana', 'com.google.android.youtube']);
    expect(new Date(s.endsAt).getTime() - new Date(s.startedAt).getTime()).toBe(30 * MIN);
    expect(new Date(s.canFinishAt).getTime() - new Date(s.startedAt).getTime()).toBe(15 * MIN);
  });

  it('never accepts a pass mark under 50%', async () => {
    const res = await start(student, {
      exam: { questionCount: 10, totalMarks: 50, passMarks: 24, questionTypes: ['MCQ'] },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.details.fields['exam.passMarks'][0]).toMatch(/25 of 50/);
  });

  it('respects a higher pass mark floor set by the admin', async () => {
    await prisma.appSetting.create({ data: { key: 'minPassPercent', value: '70' } });
    const res = await start(student, {
      exam: { questionCount: 10, totalMarks: 50, passMarks: 30, questionTypes: ['MCQ'] },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.message).toMatch(/70%/);
  });

  it('ignores an invalid admin value instead of breaking', async () => {
    await prisma.appSetting.create({ data: { key: 'minPassPercent', value: '10' } });
    const res = await ctx.app.inject({ method: 'GET', url: '/v1/config' });
    expect(res.json().minPassPercent).toBe(50);
  });

  it('validates the exam and the timer', async () => {
    const badExam = await start(student, {
      exam: { questionCount: 10, totalMarks: 8, passMarks: 9, questionTypes: [] },
    });
    expect(badExam.statusCode).toBe(400);
    expect(Object.keys(badExam.json().error.details.fields)).toEqual(
      expect.arrayContaining(['exam.passMarks', 'exam.totalMarks', 'exam.questionTypes']),
    );
    expect((await start(student, { plannedMinutes: 2 })).statusCode).toBe(400);
    expect((await start(student, { lockedApps: ['not a package'] })).statusCode).toBe(400);
  });

  it('allows only one running session', async () => {
    expect((await start()).statusCode).toBe(201);
    const second = await start();
    expect(second.statusCode).toBe(409);
    expect(second.json().error.code).toBe('SESSION_ACTIVE');
  });

  it('allows only one running session even with parallel requests', async () => {
    const results = await Promise.all([start(), start(), start()]);
    expect(results.filter((r) => r.statusCode === 201)).toHaveLength(1);
    expect(await prisma.studySession.count()).toBe(1);
  });

  it('requires a linked parent for students under 15, and forces strict mode', async () => {
    const young = await signUp(ctx, { dateOfBirth: DOB.student12 });
    const blocked = await start(young);
    expect(blocked.statusCode).toBe(403);
    expect(blocked.json().error.code).toBe('PARENT_REQUIRED');

    const parent = await signUp(ctx, { role: 'PARENT', dateOfBirth: DOB.parent });
    const { code } = (await as(young).post('/v1/family/pairing-code')).json();
    await as(parent).post('/v1/family/links', { code });

    const ok = await start(young, { strict: false });
    expect(ok.statusCode).toBe(201);
    expect(ok.json().strict).toBe(true);
  });

  it('is only for students', async () => {
    const parent = await signUp(ctx, { role: 'PARENT', dateOfBirth: DOB.parent });
    expect((await start(parent)).statusCode).toBe(403);
  });
});

describe('the timer', () => {
  it('cannot be finished before half the time', async () => {
    const { id } = (await start()).json();
    ctx.clock.advance(10 * MIN);
    const res = await as(student).post(`/v1/sessions/${id}/finish`);
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toMatchObject({ code: 'TOO_EARLY' });
  });

  it('can be finished early after half the time, and the apps stay locked', async () => {
    const { id } = (await start()).json();
    ctx.clock.advance(16 * MIN);
    const res = await as(student).post(`/v1/sessions/${id}/finish`);
    expect(res.json()).toMatchObject({ status: 'EXAM_PENDING', studiedMinutes: 16 });
    expect((await as(student).get('/v1/sessions/active')).json().session.status).toBe('EXAM_PENDING');
  });

  it('moves to the exam when time is up', async () => {
    await start();
    ctx.clock.advance(31 * MIN);
    const { session } = (await as(student).get('/v1/sessions/active')).json();
    expect(session).toMatchObject({ status: 'EXAM_PENDING', studiedMinutes: 30 });
    expect(session.studyEndedAt).toBe(session.endsAt);
  });

  it("hides other students' sessions", async () => {
    const { id } = (await start()).json();
    const other = await signUp(ctx, { dateOfBirth: DOB.student16 });
    expect((await as(other).get(`/v1/sessions/${id}`)).statusCode).toBe(404);
    expect((await as(other).post(`/v1/sessions/${id}/finish`)).statusCode).toBe(404);
  });
});

describe('history and stats', () => {
  /** Runs a full session of `minutes`, then marks it passed so the next can start. */
  const studyFor = async (minutes: number) => {
    const { id } = (await start(student, { plannedMinutes: minutes })).json();
    ctx.clock.advance(minutes * MIN);
    await prisma.studySession.update({ where: { id }, data: { status: 'PASSED', completedAt: new Date() } });
  };

  it('counts today, the week and a streak in the local calendar', async () => {
    await studyFor(30); // 2026-06-01
    ctx.clock.advance(24 * 60 * MIN - 30 * MIN);
    await studyFor(20); // 2026-06-02
    ctx.clock.advance(60 * MIN);
    await studyFor(10); // 2026-06-02

    const stats = (await as(student).get('/v1/sessions/stats?utcOffsetMinutes=360')).json();
    expect(stats.todayMinutes).toBe(30);
    expect(stats.streakDays).toBe(2);
    expect(stats.week).toHaveLength(7);
    expect(stats.week.at(-1)).toEqual({ day: '2026-06-02', minutes: 30 });
    expect(stats.week.at(-2)).toEqual({ day: '2026-06-01', minutes: 30 });
    expect(stats.totalMinutes).toBe(60);
    expect(stats.sessionsCompleted).toBe(3);

    const history = (await as(student).get('/v1/sessions?limit=2')).json().sessions;
    expect(history).toHaveLength(2);
    expect(history[0].plannedMinutes).toBe(10);
  });

  it('keeps a streak alive when today has no study yet', async () => {
    await studyFor(15);
    ctx.clock.advance(24 * 60 * MIN);
    const stats = (await as(student).get('/v1/sessions/stats')).json();
    expect(stats).toMatchObject({ todayMinutes: 0, streakDays: 1 });
  });
});

describe('server time', () => {
  it('is sent on every response', async () => {
    const res = await ctx.app.inject({ method: 'GET', url: '/health' });
    expect(res.headers['x-server-time']).toBe('2026-06-01T08:00:00.000Z');
  });
});
