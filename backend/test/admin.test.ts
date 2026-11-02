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
  student = await signUp(ctx, { name: 'Nadia Rahman' });
  parent = await signUp(ctx, { role: 'PARENT', dateOfBirth: DOB.parent, name: 'Ammu' });
});

afterAll(async () => {
  await prisma.$disconnect();
});

const as = (account: SignedInAccount) => ({
  get: (url: string) => ctx.app.inject({ method: 'GET', url, headers: bearer(account.accessToken) }),
  patch: (url: string, payload: object) =>
    ctx.app.inject({ method: 'PATCH', url, payload, headers: bearer(account.accessToken) }),
  post: (url: string, payload: object = {}) =>
    ctx.app.inject({ method: 'POST', url, payload, headers: bearer(account.accessToken) }),
});

describe('admin access', () => {
  it('is for admins only', async () => {
    expect((await ctx.app.inject({ method: 'GET', url: '/v1/admin/stats' })).statusCode).toBe(401);
    expect((await as(student).get('/v1/admin/stats')).statusCode).toBe(403);
    expect((await as(parent).get('/v1/admin/users')).statusCode).toBe(403);
    expect((await as(admin).get('/v1/admin/stats')).statusCode).toBe(200);
  });
});

describe('GET /v1/admin/stats', () => {
  it('counts accounts and fills every day of the activity chart', async () => {
    // Rows get the real time by default; put them on the test clock's day.
    await prisma.user.updateMany({ data: { createdAt: ctx.clock.fn() } });
    const res = await as(admin).get('/v1/admin/stats');
    const body = res.json<{
      users: { total: number; students: number; parents: number; admins: number; newThisWeek: number };
      exams: { passRate: number | null };
      activity: { date: string; signups: number }[];
    }>();
    expect(body.users).toMatchObject({ total: 3, students: 1, parents: 1, admins: 1, newThisWeek: 3 });
    expect(body.exams.passRate).toBeNull();
    expect(body.activity).toHaveLength(14);
    expect(body.activity.at(-1)).toMatchObject({ date: '2026-06-01', signups: 3 });
  });
});

describe('users', () => {
  it('lists, searches and filters accounts', async () => {
    const all = (await as(admin).get('/v1/admin/users')).json<{ total: number }>();
    expect(all.total).toBe(3);

    const search = (await as(admin).get('/v1/admin/users?q=Nadia')).json<{ users: { id: string }[] }>();
    expect(search.users.map((u) => u.id)).toEqual([student.userId]);

    const parents = (await as(admin).get('/v1/admin/users?role=PARENT')).json<{ users: { id: string }[] }>();
    expect(parents.users.map((u) => u.id)).toEqual([parent.userId]);

    expect((await as(admin).get('/v1/admin/users?role=ROBOT')).statusCode).toBe(400);
  });

  it('shows one account in detail and never its password hash', async () => {
    const res = await as(admin).get(`/v1/admin/users/${student.userId}`);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ id: student.userId, name: 'Nadia Rahman', sessions: [], exams: [], devices: [] });
    expect(res.body).not.toContain('passwordHash');
    expect((await as(admin).get('/v1/admin/users/nope')).statusCode).toBe(404);
  });

  it('disabling signs the account out everywhere; enabling lets it back in', async () => {
    const off = await as(admin).patch(`/v1/admin/users/${student.userId}`, { disabled: true });
    expect(off.json()).toMatchObject({ disabled: true });

    expect((await as(student).get('/v1/me')).statusCode).toBe(401);
    const refresh = await ctx.app.inject({
      method: 'POST',
      url: '/v1/auth/refresh',
      payload: { refreshToken: student.refreshToken },
    });
    expect(refresh.statusCode).toBe(401);

    await as(admin).patch(`/v1/admin/users/${student.userId}`, { disabled: false });
    const login = await ctx.app.inject({
      method: 'POST',
      url: '/v1/auth/login',
      payload: { identifier: student.email, password: student.password },
    });
    expect(login.statusCode).toBe(200);
  });

  it('an admin cannot disable themselves or another admin', async () => {
    const self = await as(admin).patch(`/v1/admin/users/${admin.userId}`, { disabled: true });
    expect(self.json<{ error: { code: string } }>().error.code).toBe('CANNOT_DISABLE_SELF');

    await prisma.user.update({ where: { id: parent.userId }, data: { role: 'ADMIN' } });
    const other = await as(admin).patch(`/v1/admin/users/${parent.userId}`, { disabled: true });
    expect(other.json<{ error: { code: string } }>().error.code).toBe('CANNOT_MANAGE_ADMIN');
  });
});

describe('settings', () => {
  it('changes one setting without touching the others, and the app sees it', async () => {
    const before = (await as(admin).get('/v1/admin/settings')).json<{ maxQuestions: number; minPassPercent: number }>();

    const res = await as(admin).patch('/v1/admin/settings', { minPassPercent: 60, announcement: 'Exams week!' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ minPassPercent: 60, announcement: 'Exams week!', maxQuestions: before.maxQuestions });
    expect(await prisma.appSetting.count()).toBe(2);

    const app = (await ctx.app.inject({ method: 'GET', url: '/v1/config' })).json();
    expect(app).toMatchObject({ minPassPercent: 60, announcement: 'Exams week!' });
  });

  it('never lets the pass mark drop under 50% and refuses unknown settings', async () => {
    const low = await as(admin).patch('/v1/admin/settings', { minPassPercent: 40 });
    expect(low.statusCode).toBe(400);
    const typo = await as(admin).patch('/v1/admin/settings', { minPasPercent: 70 });
    expect(typo.statusCode).toBe(400);
    const crossed = await as(admin).patch('/v1/admin/settings', { minStudyMinutes: 50, maxStudyMinutes: 20 });
    expect(crossed.statusCode).toBe(400);
  });
});

describe('web panel', () => {
  it('serves the admin panel at /admin/', async () => {
    const redirect = await ctx.app.inject({ method: 'GET', url: '/admin' });
    expect(redirect.statusCode).toBe(302);
    const page = await ctx.app.inject({ method: 'GET', url: '/admin/' });
    expect(page.statusCode).toBe(200);
    expect(page.headers['content-type']).toContain('text/html');
    expect((await ctx.app.inject({ method: 'GET', url: '/admin/..%2Fbackend%2F.env' })).statusCode).toBe(404);
  });
});
