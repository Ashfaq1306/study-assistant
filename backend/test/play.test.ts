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
  student = await signUp(ctx, { name: 'Nadia' });
});

afterAll(async () => {
  await prisma.$disconnect();
});

const req = (account: SignedInAccount, method: 'GET' | 'POST' | 'PATCH' | 'DELETE', url: string, payload?: object) =>
  ctx.app.inject({ method, url, payload, headers: bearer(account.accessToken) });

const startSession = (account: SignedInAccount) =>
  req(account, 'POST', '/v1/sessions', {
    subject: 'Mathematics',
    topics: 'Algebra',
    plannedMinutes: 30,
    lockedApps: ['com.google.android.youtube'],
    exam: { questionCount: 10, totalMarks: 50, passMarks: 25, questionTypes: ['MCQ'], difficulty: 'MEDIUM' },
  });

describe('deleting an account', () => {
  it('needs the right password', async () => {
    const res = await req(student, 'DELETE', '/v1/me', { password: 'nope-nope' });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('WRONG_PASSWORD');
    expect(await prisma.user.count({ where: { id: student.userId } })).toBe(1);
  });

  it('removes the account and everything that belongs to it', async () => {
    const parent = await signUp(ctx, { role: 'PARENT', dateOfBirth: DOB.parent });
    const code = (await req(student, 'POST', '/v1/family/pairing-code')).json<{ code: string }>().code;
    expect((await req(parent, 'POST', '/v1/family/links', { code })).statusCode).toBeLessThan(300);
    await req(student, 'POST', '/v1/calendar', { kind: 'EXAM', title: 'Maths', startsAt: '2026-06-10T09:00:00+06:00' });

    const res = await req(student, 'DELETE', '/v1/me', { password: student.password });
    expect(res.statusCode).toBe(204);
    expect(await prisma.user.count({ where: { id: student.userId } })).toBe(0);
    expect(await prisma.familyLink.count()).toBe(0);
    expect(await prisma.calendarEvent.count()).toBe(0);
    expect(await prisma.session.count({ where: { userId: student.userId } })).toBe(0);

    // Signed out everywhere and gone: the same email can sign up again.
    expect((await req(student, 'GET', '/v1/me')).statusCode).toBe(401);
    expect(await prisma.user.count({ where: { id: parent.userId } })).toBe(1);
  });

  it('is refused while the student is locked, so it is no way around the exam', async () => {
    expect((await startSession(student)).statusCode).toBe(201);
    const res = await req(student, 'DELETE', '/v1/me', { password: student.password });
    expect(res.statusCode).toBe(409);
    expect(res.json().error.code).toBe('LOCK_ACTIVE');
  });

  it('is not for admins', async () => {
    await prisma.user.update({ where: { id: student.userId }, data: { role: 'ADMIN' } });
    const res = await req(student, 'DELETE', '/v1/me', { password: student.password });
    expect(res.json().error.code).toBe('ADMIN_ACCOUNT');
  });
});

describe('reporting AI content', () => {
  it('stores a report that admins can list and resolve', async () => {
    const res = await req(student, 'POST', '/v1/reports', { kind: 'TUTOR', content: 'A wrong answer', reason: 'Wrong maths' });
    expect(res.statusCode).toBe(201);

    expect((await req(student, 'GET', '/v1/admin/reports')).statusCode).toBe(403);
    const admin = await signUp(ctx, { role: 'PARENT', dateOfBirth: DOB.parent });
    await prisma.user.update({ where: { id: admin.userId }, data: { role: 'ADMIN' } });

    const list = (await req(admin, 'GET', '/v1/admin/reports')).json<{ total: number; reports: { id: string; content: string; user: { name: string } }[] }>();
    expect(list.total).toBe(1);
    expect(list.reports[0]).toMatchObject({ content: 'A wrong answer', user: { name: 'Nadia' } });

    await req(admin, 'PATCH', `/v1/admin/reports/${list.reports[0]!.id}`, { resolved: true });
    expect((await req(admin, 'GET', '/v1/admin/reports')).json<{ total: number }>().total).toBe(0);
    expect((await req(admin, 'GET', '/v1/admin/reports?status=resolved')).json<{ total: number }>().total).toBe(1);
  });

  it('refuses an unknown kind', async () => {
    expect((await req(student, 'POST', '/v1/reports', { kind: 'SPAM', content: 'x' })).statusCode).toBe(400);
  });
});
