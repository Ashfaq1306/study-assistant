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
let parent: SignedInAccount;

beforeEach(async () => {
  await resetDatabase();
  ctx = await createTestApp();
  student = await signUp(ctx, { dateOfBirth: DOB.student12, name: 'Nadia' });
  parent = await signUp(ctx, { role: 'PARENT', dateOfBirth: DOB.parent, name: 'Ammu' });
});

afterAll(async () => {
  await prisma.$disconnect();
});

const as = (account: SignedInAccount) => ({
  get: (url: string) => ctx.app.inject({ method: 'GET', url, headers: bearer(account.accessToken) }),
  post: (url: string, payload: object = {}) =>
    ctx.app.inject({ method: 'POST', url, payload, headers: bearer(account.accessToken) }),
  delete: (url: string) => ctx.app.inject({ method: 'DELETE', url, headers: bearer(account.accessToken) }),
});

const newCode = async (account = student) => {
  const res = await as(account).post('/v1/family/pairing-code');
  expect(res.statusCode).toBe(200);
  return res.json<{ code: string; qrPayload: string; expiresAt: string }>();
};

describe('pairing a parent by QR code', () => {
  it('links a parent who scans the QR payload', async () => {
    const { code, qrPayload } = await newCode();
    expect(code).toMatch(/^[0-9A-Z]{4}-[0-9A-Z]{4}$/);
    expect(qrPayload).toBe(`studyassistant://pair?code=${code.replace('-', '')}`);

    const link = await as(parent).post('/v1/family/links', { code: qrPayload });
    expect(link.statusCode).toBe(201);
    expect(link.json().person).toMatchObject({ name: 'Nadia', role: 'STUDENT', age: 12 });

    const me = await as(student).get('/v1/me');
    expect(me.json().parentalControl).toEqual({ required: true, linkedParents: 1 });
    expect((await as(parent).get('/v1/me')).json().linkedChildren).toBe(1);

    const studentView = (await as(student).get('/v1/family/links')).json();
    expect(studentView.links[0].person).toMatchObject({ name: 'Ammu', role: 'PARENT' });
  });

  it('accepts a code typed by hand in lower case', async () => {
    const { code } = await newCode();
    const res = await as(parent).post('/v1/family/links', { code: code.toLowerCase().replace('-', ' ') });
    expect(res.statusCode).toBe(201);
  });

  it('uses each code only once', async () => {
    const { code } = await newCode();
    const otherParent = await signUp(ctx, { role: 'PARENT', dateOfBirth: DOB.parent });
    expect((await as(parent).post('/v1/family/links', { code })).statusCode).toBe(201);
    const second = await as(otherParent).post('/v1/family/links', { code });
    expect(second.statusCode).toBe(400);
    expect(second.json().error.code).toBe('PAIRING_CODE_INVALID');
  });

  it('expires codes after 10 minutes and replaces older codes', async () => {
    const first = await newCode();
    const second = await newCode();
    expect((await as(parent).post('/v1/family/links', { code: first.code })).json().error.code).toBe(
      'PAIRING_CODE_INVALID',
    );
    ctx.clock.advance(10 * 60_000 + 1);
    expect((await as(parent).post('/v1/family/links', { code: second.code })).statusCode).toBe(400);
  });

  it('reports a duplicate link clearly', async () => {
    await as(parent).post('/v1/family/links', { code: (await newCode()).code });
    const again = await as(parent).post('/v1/family/links', { code: (await newCode()).code });
    expect(again.statusCode).toBe(409);
    expect(again.json().error.code).toBe('ALREADY_LINKED');
  });

  it('only lets students create codes and parents redeem them', async () => {
    expect((await as(parent).post('/v1/family/pairing-code')).statusCode).toBe(403);
    const { code } = await newCode();
    expect((await as(student).post('/v1/family/links', { code })).statusCode).toBe(403);
  });
});

describe('unlinking', () => {
  const link = async () =>
    (await as(parent).post('/v1/family/links', { code: (await newCode()).code })).json<{ id: string }>().id;

  it('stops a student under 15 removing their only parent', async () => {
    const id = await link();
    const res = await as(student).delete(`/v1/family/links/${id}`);
    expect(res.statusCode).toBe(403);
    expect(res.json().error.message).toMatch(/under 15/);
  });

  it('lets a parent unlink', async () => {
    const id = await link();
    expect((await as(parent).delete(`/v1/family/links/${id}`)).statusCode).toBe(204);
    expect((await as(student).get('/v1/me')).json().parentalControl.linkedParents).toBe(0);
  });

  it('lets a student aged 15 or over unlink', async () => {
    const older = await signUp(ctx, { dateOfBirth: DOB.student16 });
    const code = (await newCode(older)).code;
    const id = (await as(parent).post('/v1/family/links', { code })).json<{ id: string }>().id;
    expect((await as(older).get('/v1/me')).json().parentalControl.required).toBe(false);
    expect((await as(older).delete(`/v1/family/links/${id}`)).statusCode).toBe(204);
  });

  it('hides links that belong to other families', async () => {
    const id = await link();
    const stranger = await signUp(ctx, { role: 'PARENT', dateOfBirth: DOB.parent });
    expect((await as(stranger).delete(`/v1/family/links/${id}`)).statusCode).toBe(404);
  });
});

describe('concurrency', () => {
  it('never leaves a student under 15 without a parent, even with parallel unlinks', async () => {
    const second = await signUp(ctx, { role: 'PARENT', dateOfBirth: DOB.parent });
    const a = (await as(parent).post('/v1/family/links', { code: (await newCode()).code })).json<{ id: string }>().id;
    const b = (await as(second).post('/v1/family/links', { code: (await newCode()).code })).json<{ id: string }>().id;

    const results = await Promise.all([
      as(student).delete(`/v1/family/links/${a}`),
      as(student).delete(`/v1/family/links/${b}`),
    ]);
    expect(results.filter((r) => r.statusCode === 204).length).toBeLessThanOrEqual(1);
    expect(await prisma.familyLink.count({ where: { studentId: student.userId } })).toBeGreaterThanOrEqual(1);
  });
});
