import { afterAll, afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { AiHealth } from '../src/modules/ai/ai.types.js';
import { PracticeProvider } from '../src/modules/ai/practice.provider.js';
import { bearer, createTestApp, DOB, prisma, resetDatabase, signUp, type TestContext } from './helpers.js';

/** Practice questions plus a check() whose answer the test controls, like a real AI with a key. */
class CheckableAi extends PracticeProvider {
  health: AiHealth = { state: 'OK', model: 'test-model-1' };
  checks = 0;

  check(): Promise<AiHealth> {
    this.checks += 1;
    return Promise.resolve(this.health);
  }
}

let ctx: TestContext;
let ai: CheckableAi;

beforeEach(async () => {
  await resetDatabase();
  ai = new CheckableAi();
  ctx = await createTestApp({ ai });
});

afterEach(async () => {
  await ctx.app.close();
});

afterAll(async () => {
  await prisma.$disconnect();
});

const health = async () => (await ctx.app.inject({ method: 'GET', url: '/health' })).json<{ ai: string }>();

async function admin() {
  const account = await signUp(ctx, { role: 'PARENT', dateOfBirth: DOB.parent, name: 'Owner' });
  await prisma.user.update({ where: { id: account.userId }, data: { role: 'ADMIN' } });
  return bearer(account.accessToken);
}

describe('AI status', () => {
  it('is unchecked until the first check, then public on /health (state only)', async () => {
    expect(await health()).toEqual({ status: 'ok', ai: 'UNCHECKED' });

    const headers = await admin();
    const res = await ctx.app.inject({ method: 'POST', url: '/v1/admin/ai/check', headers });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ state: 'OK', model: 'test-model-1' });
    expect(await health()).toEqual({ status: 'ok', ai: 'OK' });
  });

  it('reports a rejected key, and recovers once a working key answers', async () => {
    const headers = await admin();
    ai.health = { state: 'KEY_REJECTED' };
    await ctx.app.inject({ method: 'POST', url: '/v1/admin/ai/check', headers });
    expect(await health()).toMatchObject({ ai: 'KEY_REJECTED' });
    const last = (await ctx.app.inject({ method: 'GET', url: '/v1/admin/ai', headers })).json<{ checkedAt: string }>();
    expect(last.checkedAt).toBeTruthy();

    ai.health = { state: 'OK', model: 'test-model-2' };
    ctx.clock.advance(60_000); // on-demand checks are spaced a few seconds apart
    await ctx.app.inject({ method: 'POST', url: '/v1/admin/ai/check', headers });
    expect(await health()).toMatchObject({ ai: 'OK' });
  });

  it('does not ask the AI again for a check moments after the last one', async () => {
    const headers = await admin();
    await ctx.app.inject({ method: 'POST', url: '/v1/admin/ai/check', headers });
    await ctx.app.inject({ method: 'POST', url: '/v1/admin/ai/check', headers });
    expect(ai.checks).toBe(1);
  });

  it('only admins can see or trigger checks', async () => {
    const student = await signUp(ctx);
    const as = bearer(student.accessToken);
    expect((await ctx.app.inject({ method: 'GET', url: '/v1/admin/ai', headers: as })).statusCode).toBe(403);
    expect((await ctx.app.inject({ method: 'POST', url: '/v1/admin/ai/check', headers: as })).statusCode).toBe(403);
    expect(ai.checks).toBe(0);
  });

  it('says NOT_CONFIGURED when only practice questions are set up', async () => {
    await ctx.app.close();
    ctx = await createTestApp({ ai: new PracticeProvider() });
    expect(await health()).toMatchObject({ ai: 'NOT_CONFIGURED' });
  });
});
