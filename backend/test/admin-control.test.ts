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
let admin: SignedInAccount;
let student: SignedInAccount;
let parent: SignedInAccount;

beforeEach(async () => {
  await resetDatabase();
  ctx = await createTestApp();
  admin = await signUp(ctx, { role: 'PARENT', dateOfBirth: DOB.parent, name: 'Owner' });
  await prisma.user.update({ where: { id: admin.userId }, data: { role: 'ADMIN' } });
  student = await signUp(ctx, { name: 'Nadia' });
  parent = await signUp(ctx, { role: 'PARENT', dateOfBirth: DOB.parent, name: 'Ammu' });
});

afterAll(async () => {
  await prisma.$disconnect();
});

const as = (account: SignedInAccount) => ({
  get: (url: string) => ctx.app.inject({ method: 'GET', url, headers: bearer(account.accessToken) }),
  post: (url: string, payload: object = {}) =>
    ctx.app.inject({ method: 'POST', url, payload, headers: bearer(account.accessToken) }),
});

const login = (account: SignedInAccount, password = account.password, userAgent?: string) =>
  ctx.app.inject({
    method: 'POST',
    url: '/v1/auth/login',
    payload: { identifier: account.email, password },
    headers: userAgent ? { 'user-agent': userAgent } : {},
  });

const startSession = (account: SignedInAccount, subject = 'Mathematics', plannedMinutes = 30) =>
  as(account).post('/v1/sessions', {
    subject,
    topics: 'Algebra',
    plannedMinutes,
    lockedApps: ['com.google.android.youtube'],
    exam: { questionCount: 10, totalMarks: 50, passMarks: 25, questionTypes: ['MCQ'], difficulty: 'MEDIUM' },
  });

describe('sign-in history and presence', () => {
  it('logs sign-ups, sign-ins and sign-outs, and shows who is signed in', async () => {
    const res = await login(student, student.password, 'QA phone');
    expect(res.statusCode).toBe(200);
    const { refreshToken } = res.json<{ tokens: { refreshToken: string } }>().tokens;
    await ctx.app.inject({ method: 'POST', url: '/v1/auth/logout', payload: { refreshToken } });

    const log = (await as(admin).get(`/v1/admin/activity?userId=${student.userId}`)).json<{
      events: { kind: string; userAgent: string | null }[];
    }>();
    expect(log.events.map((e) => e.kind)).toEqual(['LOGOUT', 'LOGIN', 'SIGNUP']);
    expect(log.events[1]?.userAgent).toBe('QA phone');

    // The sign-up session is still open, so the student counts as signed in.
    const detail = (await as(admin).get(`/v1/admin/users/${student.userId}`)).json<{
      presence: string;
      signedInDevices: unknown[];
    }>();
    expect(detail.signedInDevices).toHaveLength(1);
    expect(['online', 'signedIn']).toContain(detail.presence);

    const out = await as(admin).post(`/v1/admin/users/${student.userId}/sign-out`);
    expect(out.json()).toMatchObject({ presence: 'signedOut', signedInDevices: [] });
    const refresh = await ctx.app.inject({
      method: 'POST',
      url: '/v1/auth/refresh',
      payload: { refreshToken: student.refreshToken },
    });
    expect(refresh.statusCode).toBe(401);
  });

  it('filters the list by who is signed out', async () => {
    await as(admin).post(`/v1/admin/users/${parent.userId}/sign-out`);
    const res = (await as(admin).get('/v1/admin/users?presence=signedOut')).json<{ users: { id: string }[] }>();
    expect(res.users.map((u) => u.id)).toEqual([parent.userId]);
  });
});

describe('study time', () => {
  it('adds up minutes studied per student and per subject', async () => {
    expect((await startSession(student, 'Physics', 30)).statusCode).toBe(201);
    ctx.clock.advance(20 * 60_000);

    const study = (await as(admin).get('/v1/admin/study?days=7')).json<{
      totalMinutes: number;
      students: { id: string; minutes: number; subjects: { subject: string; minutes: number }[] }[];
      subjects: { subject: string; minutes: number; students: number }[];
    }>();
    expect(study.totalMinutes).toBe(20);
    expect(study.students[0]).toMatchObject({
      id: student.userId,
      minutes: 20,
      subjects: [{ subject: 'Physics', minutes: 20 }],
    });
    expect(study.subjects).toEqual([{ subject: 'Physics', minutes: 20, sessions: 1, students: 1 }]);

    const list = (await as(admin).get('/v1/admin/users?role=STUDENT')).json<{ users: { studyMinutes: number }[] }>();
    expect(list.users.map((u) => u.studyMinutes)).toEqual([20]);
  });
});

describe('unlocking a phone without an exam', () => {
  it('ends the study lock, keeps the time studied, and tells the student and parents', async () => {
    expect((await startSession(student)).statusCode).toBe(201);
    ctx.clock.advance(10 * 60_000);

    const res = await as(admin).post(`/v1/admin/users/${student.userId}/unlock`, { reason: 'Emailed support' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ endedSessions: 1, user: { lock: { locked: false } } });

    const active = (await as(student).get('/v1/sessions/active')).json<{ session: unknown }>();
    expect(active.session).toBeNull();
    const stats = (await as(student).get('/v1/sessions/stats?utcOffsetMinutes=0')).json<{ totalMinutes: number }>();
    expect(stats.totalMinutes).toBe(10);

    const notes = await prisma.notification.count({ where: { userId: student.userId, kind: 'ADMIN_UNLOCK' } });
    expect(notes).toBe(1);
    const log = await prisma.activityEvent.findFirstOrThrow({ where: { userId: student.userId, kind: 'ADMIN_UNLOCKED' } });
    expect(log).toMatchObject({ actorId: admin.userId, detail: '1 lock(s) ended: Emailed support' });
  });

  it('is only for students, and only admins can do it', async () => {
    const res = await as(admin).post(`/v1/admin/users/${parent.userId}/unlock`);
    expect(res.json<{ error: { code: string } }>().error.code).toBe('NOT_A_STUDENT');
    expect((await as(parent).post(`/v1/admin/users/${student.userId}/unlock`)).statusCode).toBe(403);
  });
});

describe('password reset by an admin', () => {
  it('gives a new password; the old one stops working', async () => {
    const res = await as(admin).post(`/v1/admin/users/${student.userId}/reset-password`);
    const { password } = res.json<{ password: string }>();
    expect(password).toHaveLength(12);

    expect((await login(student)).statusCode).toBe(401);
    expect((await login(student, password)).statusCode).toBe(200);
  });

  it('never touches another admin', async () => {
    await prisma.user.update({ where: { id: parent.userId }, data: { role: 'ADMIN' } });
    const res = await as(admin).post(`/v1/admin/users/${parent.userId}/reset-password`);
    expect(res.json<{ error: { code: string } }>().error.code).toBe('CANNOT_MANAGE_ADMIN');
  });
});

describe('panel session', () => {
  it('gives the in-app panel its own tokens', async () => {
    const res = await as(admin).post('/v1/admin/panel-session');
    const { tokens } = res.json<{ tokens: { accessToken: string; refreshToken: string } }>();
    expect(tokens.refreshToken).not.toBe(admin.refreshToken);
    const stats = await ctx.app.inject({ method: 'GET', url: '/v1/admin/stats', headers: bearer(tokens.accessToken) });
    expect(stats.statusCode).toBe(200);
    expect((await as(student).post('/v1/admin/panel-session')).statusCode).toBe(403);
  });
});
