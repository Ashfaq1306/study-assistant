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

const register = async (account = student) => {
  const res = await ctx.app.inject({
    method: 'POST',
    url: '/v1/devices',
    headers: bearer(account.accessToken),
    payload: { name: 'Galaxy A12', platform: 'android', appVersion: '0.2.0' },
  });
  expect(res.statusCode).toBe(201);
  return res.json<{ deviceId: string; deviceToken: string }>();
};

const state = (token: string) =>
  ctx.app.inject({ method: 'GET', url: '/v1/device/state', headers: { 'x-device-token': token } });

const startSession = (lockedApps: string[], strict = true) =>
  ctx.app.inject({
    method: 'POST',
    url: '/v1/sessions',
    headers: bearer(student.accessToken),
    payload: {
      subject: 'Science',
      topics: 'Photosynthesis',
      plannedMinutes: 20,
      lockedApps,
      strict,
      exam: { questionCount: 5, totalMarks: 10, passMarks: 5, questionTypes: ['MCQ'] },
    },
  });

describe('device sync', () => {
  it('rejects unknown or missing device tokens', async () => {
    expect((await state('nope')).statusCode).toBe(401);
    expect((await ctx.app.inject({ method: 'GET', url: '/v1/device/state' })).json().error.code).toBe(
      'DEVICE_UNAUTHORIZED',
    );
  });

  it('is unlocked when nothing is running', async () => {
    const { deviceToken } = await register();
    expect((await state(deviceToken)).json()).toEqual({
      locked: false,
      wholePhone: false,
      packages: [],
      strict: false,
      reasons: [],
    });
  });

  it('locks the session apps while studying and while the exam is pending', async () => {
    const { deviceToken } = await register();
    const session = (await startSession(['com.instagram.android', 'com.facebook.katana'])).json();

    const studying = (await state(deviceToken)).json();
    expect(studying).toMatchObject({
      locked: true,
      wholePhone: false,
      strict: true,
      packages: ['com.facebook.katana', 'com.instagram.android'],
    });
    expect(studying.reasons[0]).toMatchObject({ kind: 'SESSION', id: session.id, status: 'STUDYING' });

    ctx.clock.advance(21 * 60_000);
    const pending = (await state(deviceToken)).json();
    expect(pending.locked).toBe(true);
    expect(pending.reasons[0].status).toBe('EXAM_PENDING');

    await prisma.studySession.update({ where: { id: session.id }, data: { status: 'PASSED' } });
    expect((await state(deviceToken)).json().locked).toBe(false);
  });

  it('supports locking the whole phone', async () => {
    const { deviceToken } = await register();
    await startSession(['*'], false);
    expect((await state(deviceToken)).json()).toMatchObject({ locked: true, wholePhone: true, strict: false });
  });

  it('records heartbeats and returns the lock state', async () => {
    const { deviceId, deviceToken } = await register();
    await startSession(['com.instagram.android']);
    ctx.clock.advance(5_000);
    const res = await ctx.app.inject({
      method: 'POST',
      url: '/v1/device/heartbeat',
      headers: { 'x-device-token': deviceToken },
      payload: {
        protectionOn: true,
        usageAccess: true,
        installedApps: [{ package: 'com.instagram.android', label: 'Instagram' }],
      },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().locked).toBe(true);

    const device = await prisma.device.findUniqueOrThrow({ where: { id: deviceId } });
    expect(device).toMatchObject({ protectionOn: true, usageAccess: true });
    expect(device.lastSeenAt.toISOString()).toBe('2026-06-01T08:00:05.000Z');

    const list = (
      await ctx.app.inject({ method: 'GET', url: '/v1/devices', headers: bearer(student.accessToken) })
    ).json();
    expect(list.devices[0].installedApps).toEqual([{ package: 'com.instagram.android', label: 'Instagram' }]);
  });

  it('rejects bad app data in a heartbeat', async () => {
    const { deviceToken } = await register();
    const res = await ctx.app.inject({
      method: 'POST',
      url: '/v1/device/heartbeat',
      headers: { 'x-device-token': deviceToken },
      payload: { protectionOn: true, installedApps: [{ package: '*', label: 'Everything' }] },
    });
    expect(res.statusCode).toBe(400);
  });

  it('stops working once revoked, and only the owner can revoke', async () => {
    const { deviceId, deviceToken } = await register();
    const other = await signUp(ctx, { dateOfBirth: DOB.student16 });
    const foreign = await ctx.app.inject({
      method: 'DELETE',
      url: `/v1/devices/${deviceId}`,
      headers: bearer(other.accessToken),
    });
    expect(foreign.statusCode).toBe(404);

    const own = await ctx.app.inject({
      method: 'DELETE',
      url: `/v1/devices/${deviceId}`,
      headers: bearer(student.accessToken),
    });
    expect(own.statusCode).toBe(204);
    expect((await state(deviceToken)).statusCode).toBe(401);
  });

  it("keeps a student's lock separate from other students", async () => {
    const other = await signUp(ctx, { dateOfBirth: DOB.student16 });
    const { deviceToken } = await register(other);
    await startSession(['com.instagram.android']);
    expect((await state(deviceToken)).json().locked).toBe(false);
  });

  it('is only for students', async () => {
    const parent = await signUp(ctx, { role: 'PARENT', dateOfBirth: DOB.parent });
    const res = await ctx.app.inject({
      method: 'POST',
      url: '/v1/devices',
      headers: bearer(parent.accessToken),
      payload: { name: 'Pixel', platform: 'android' },
    });
    expect(res.statusCode).toBe(403);
  });
});
