import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import {
  bearer,
  createTestApp,
  DOB,
  prisma,
  resetDatabase,
  signUp,
  type TestContext,
} from './helpers.js';

let ctx: TestContext;

beforeEach(async () => {
  await resetDatabase();
  ctx = await createTestApp();
});

afterAll(async () => {
  await prisma.$disconnect();
});

const post = (url: string, payload: object, headers?: Record<string, string>) =>
  ctx.app.inject({ method: 'POST', url, payload, headers });

const studentBody = (overrides: Record<string, unknown> = {}) => ({
  role: 'STUDENT',
  name: 'Nadia',
  email: 'nadia@example.com',
  password: 'study1234',
  dateOfBirth: DOB.student12,
  otpChannel: 'EMAIL',
  ...overrides,
});

describe('registration', () => {
  it('creates an unverified account and emails a code', async () => {
    const res = await post('/v1/auth/register', studentBody());
    expect(res.statusCode).toBe(201);
    const body = res.json();
    expect(body.verification).toMatchObject({ channel: 'EMAIL', destination: 'na•••@example.com' });
    expect(ctx.notifier.sent).toHaveLength(1);
    expect(ctx.notifier.sent[0]).toMatchObject({ channel: 'EMAIL', to: 'nadia@example.com' });

    const user = await prisma.user.findUniqueOrThrow({ where: { id: body.userId } });
    expect(user.verifiedAt).toBeNull();
    expect(user.passwordHash).not.toContain('study1234');
  });

  it('sends the code by SMS and normalises a Bangladeshi number', async () => {
    const res = await post(
      '/v1/auth/register',
      studentBody({ email: '', phone: '01712345678', otpChannel: 'SMS' }),
    );
    expect(res.statusCode).toBe(201);
    expect(ctx.notifier.sent[0]).toMatchObject({ channel: 'SMS', to: '+8801712345678' });
    expect(res.json().verification.destination).toBe('+880•••••••678');
  });

  it('reports field errors', async () => {
    const res = await post(
      '/v1/auth/register',
      studentBody({ email: 'nope', password: 'short', dateOfBirth: '2013-02-30', otpChannel: 'SMS' }),
    );
    expect(res.statusCode).toBe(400);
    const { error } = res.json();
    expect(error.code).toBe('VALIDATION_FAILED');
    expect(Object.keys(error.details.fields)).toEqual(
      expect.arrayContaining(['email', 'password', 'dateOfBirth']),
    );
  });

  it('requires a phone number when the code goes by SMS', async () => {
    const res = await post('/v1/auth/register', studentBody({ otpChannel: 'SMS' }));
    expect(res.statusCode).toBe(400);
    expect(res.json().error.details.fields.phone).toBeDefined();
  });

  it('rejects parents younger than 18', async () => {
    const res = await post('/v1/auth/register', studentBody({ role: 'PARENT', dateOfBirth: DOB.student16 }));
    expect(res.statusCode).toBe(400);
    expect(res.json().error.details.fields.dateOfBirth[0]).toMatch(/18/);
  });

  it('refuses an email that belongs to a verified account', async () => {
    const existing = await signUp(ctx);
    const res = await post('/v1/auth/register', studentBody({ email: existing.email }));
    expect(res.statusCode).toBe(409);
    expect(res.json().error.code).toBe('EMAIL_TAKEN');
  });

  it('lets someone sign up again over an abandoned, unverified signup', async () => {
    expect((await post('/v1/auth/register', studentBody())).statusCode).toBe(201);
    const tooSoon = await post('/v1/auth/register', studentBody({ name: 'Nadia R' }));
    expect(tooSoon.json().error.code).toBe('OTP_RESEND_TOO_SOON');
    ctx.clock.advance(61_000);
    expect((await post('/v1/auth/register', studentBody({ name: 'Nadia R' }))).statusCode).toBe(201);
    expect(await prisma.user.count()).toBe(1);
  });

  it('does not keep a code that could not be delivered', async () => {
    ctx.notifier.failNext = true;
    const res = await post('/v1/auth/register', studentBody());
    expect(res.statusCode).toBe(502);
    expect(res.json().error.code).toBe('OTP_DELIVERY_FAILED');
    expect(await prisma.otpCode.count()).toBe(0);
  });
});

describe('account verification', () => {
  const register = async () => (await post('/v1/auth/register', studentBody())).json<{ userId: string }>().userId;

  it('opens the account with the right code and signs in', async () => {
    const userId = await register();
    const res = await post('/v1/auth/verify', { userId, code: ctx.notifier.lastCode() });
    expect(res.statusCode).toBe(200);
    const { user, tokens } = res.json();
    expect(user).toMatchObject({ verified: true, age: 12, parentalControl: { required: true, linkedParents: 0 } });
    expect(tokens.accessToken).toBeTypeOf('string');
    expect(tokens.refreshToken).toBeTypeOf('string');
  });

  it('counts wrong codes and locks after five', async () => {
    const userId = await register();
    const code = ctx.notifier.lastCode();
    const wrong = code === '000000' ? '111111' : '000000';

    const first = await post('/v1/auth/verify', { userId, code: wrong });
    expect(first.statusCode).toBe(400);
    expect(first.json().error).toMatchObject({ code: 'OTP_INVALID', details: { attemptsLeft: 4 } });

    for (let i = 0; i < 4; i++) await post('/v1/auth/verify', { userId, code: wrong });
    const locked = await post('/v1/auth/verify', { userId, code });
    expect(locked.statusCode).toBe(429);
    expect(locked.json().error.code).toBe('OTP_TOO_MANY_ATTEMPTS');
  });

  it('expires codes after 10 minutes', async () => {
    const userId = await register();
    const code = ctx.notifier.lastCode();
    ctx.clock.advance(10 * 60_000 + 1);
    const res = await post('/v1/auth/verify', { userId, code });
    expect(res.json().error.code).toBe('OTP_EXPIRED');
  });

  it('enforces a resend cooldown and invalidates the old code', async () => {
    const userId = await register();
    const oldCode = ctx.notifier.lastCode();

    const tooSoon = await post('/v1/auth/verify/resend', { userId });
    expect(tooSoon.statusCode).toBe(429);
    expect(tooSoon.json().error.code).toBe('OTP_RESEND_TOO_SOON');

    ctx.clock.advance(61_000);
    expect((await post('/v1/auth/verify/resend', { userId })).statusCode).toBe(200);
    const newCode = ctx.notifier.lastCode();

    if (oldCode !== newCode) {
      expect((await post('/v1/auth/verify', { userId, code: oldCode })).json().error.code).toBe('OTP_INVALID');
    }
    expect((await post('/v1/auth/verify', { userId, code: newCode })).statusCode).toBe(200);
  });

  it('can switch the code to SMS when the account has a phone', async () => {
    const userId = (
      await post('/v1/auth/register', studentBody({ phone: '01812345678' }))
    ).json<{ userId: string }>().userId;
    ctx.clock.advance(61_000);
    const res = await post('/v1/auth/verify/resend', { userId, channel: 'SMS' });
    expect(res.statusCode).toBe(200);
    expect(ctx.notifier.sent.at(-1)).toMatchObject({ channel: 'SMS', to: '+8801812345678' });
  });
});

describe('login', () => {
  it('signs in with a verified email in any case', async () => {
    await post('/v1/auth/register', studentBody());
    const userId = (await prisma.user.findFirstOrThrow()).id;
    await post('/v1/auth/verify', { userId, code: ctx.notifier.lastCode() });
    const res = await post('/v1/auth/login', { identifier: 'NADIA@example.com', password: 'study1234' });
    expect(res.statusCode).toBe(200);
  });

  it('signs in with a verified phone number written any way', async () => {
    await post('/v1/auth/register', studentBody({ email: '', phone: '01712345678', otpChannel: 'SMS' }));
    const userId = (await prisma.user.findFirstOrThrow()).id;
    await post('/v1/auth/verify', { userId, code: ctx.notifier.lastCode() });

    for (const identifier of ['01712345678', '০১৭১২৩৪৫৬৭৮', '+8801712345678', '8801712345678']) {
      const res = await post('/v1/auth/login', { identifier, password: 'study1234' });
      expect(res.statusCode, identifier).toBe(200);
    }
  });

  it('gives the same error for a wrong password and an unknown account', async () => {
    const account = await signUp(ctx);
    const wrongPassword = await post('/v1/auth/login', { identifier: account.email, password: 'nope1234' });
    const unknown = await post('/v1/auth/login', { identifier: 'ghost@example.com', password: 'nope1234' });
    expect(wrongPassword.statusCode).toBe(401);
    expect(unknown.statusCode).toBe(401);
    expect(wrongPassword.json()).toEqual(unknown.json());
  });

  it('asks an unverified account for its code', async () => {
    await post('/v1/auth/register', studentBody());
    ctx.clock.advance(61_000);
    const res = await post('/v1/auth/login', { identifier: 'nadia@example.com', password: 'study1234' });
    expect(res.statusCode).toBe(403);
    const { error } = res.json();
    expect(error.code).toBe('ACCOUNT_NOT_VERIFIED');
    expect(error.details.userId).toBeTypeOf('string');
    expect(ctx.notifier.sent).toHaveLength(2);
  });

  it('blocks disabled accounts, including their existing tokens', async () => {
    const account = await signUp(ctx);
    await prisma.user.update({ where: { id: account.userId }, data: { disabledAt: new Date() } });
    const login = await post('/v1/auth/login', { identifier: account.email, password: account.password });
    expect(login.json().error.code).toBe('ACCOUNT_DISABLED');
    const me = await ctx.app.inject({ method: 'GET', url: '/v1/me', headers: bearer(account.accessToken) });
    expect(me.statusCode).toBe(401);
  });
});

describe('sessions', () => {
  it('rotates refresh tokens and revokes the family when an old one is reused', async () => {
    const account = await signUp(ctx);
    const first = await post('/v1/auth/refresh', { refreshToken: account.refreshToken });
    expect(first.statusCode).toBe(200);
    const rotated = first.json().tokens.refreshToken as string;
    expect(rotated).not.toBe(account.refreshToken);

    const reuse = await post('/v1/auth/refresh', { refreshToken: account.refreshToken });
    expect(reuse.statusCode).toBe(401);
    // The thief's reuse also ends the legitimate session.
    expect((await post('/v1/auth/refresh', { refreshToken: rotated })).statusCode).toBe(401);
  });

  it('logs out', async () => {
    const account = await signUp(ctx);
    expect((await post('/v1/auth/logout', { refreshToken: account.refreshToken })).statusCode).toBe(204);
    expect((await post('/v1/auth/refresh', { refreshToken: account.refreshToken })).statusCode).toBe(401);
  });

  it('expires refresh tokens after 30 days', async () => {
    const account = await signUp(ctx);
    ctx.clock.advance(30 * 24 * 3_600_000 + 1);
    expect((await post('/v1/auth/refresh', { refreshToken: account.refreshToken })).statusCode).toBe(401);
  });
});

describe('password reset', () => {
  it('does not reveal whether an account exists', async () => {
    const res = await post('/v1/auth/password/forgot', { identifier: 'ghost@example.com' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ sent: true });
    expect(ctx.notifier.sent).toHaveLength(0);
  });

  it('resets the password with the code and signs other devices out', async () => {
    const account = await signUp(ctx);
    ctx.clock.advance(61_000);
    await post('/v1/auth/password/forgot', { identifier: account.email });
    const code = ctx.notifier.lastCode();

    const reset = await post('/v1/auth/password/reset', {
      identifier: account.email,
      code,
      newPassword: 'brandnew99',
    });
    expect(reset.statusCode).toBe(200);
    expect((await post('/v1/auth/refresh', { refreshToken: account.refreshToken })).statusCode).toBe(401);
    expect((await post('/v1/auth/login', { identifier: account.email, password: 'brandnew99' })).statusCode).toBe(200);
    expect((await post('/v1/auth/login', { identifier: account.email, password: account.password })).statusCode).toBe(401);
  });
});

describe('profile', () => {
  it('requires a valid access token', async () => {
    expect((await ctx.app.inject({ method: 'GET', url: '/v1/me' })).statusCode).toBe(401);
    expect((await ctx.app.inject({ method: 'GET', url: '/v1/me', headers: bearer('junk') })).statusCode).toBe(401);
  });

  it('returns and updates the profile', async () => {
    const account = await signUp(ctx, { role: 'PARENT', dateOfBirth: DOB.parent });
    const me = await ctx.app.inject({ method: 'GET', url: '/v1/me', headers: bearer(account.accessToken) });
    expect(me.json()).toMatchObject({ role: 'PARENT', parentalControl: null, linkedChildren: 0 });

    const patched = await ctx.app.inject({
      method: 'PATCH',
      url: '/v1/me',
      headers: bearer(account.accessToken),
      payload: { name: '  Ammu  ' },
    });
    expect(patched.json().name).toBe('Ammu');
  });
});

describe('rate limiting', () => {
  it('limits sensitive endpoints per IP', async () => {
    const limited = await createTestApp({ rateLimit: true });
    const statuses: number[] = [];
    for (let i = 0; i < 11; i++) {
      const res = await limited.app.inject({
        method: 'POST',
        url: '/v1/auth/login',
        payload: { identifier: 'ghost@example.com', password: 'x' },
      });
      statuses.push(res.statusCode);
    }
    expect(statuses.slice(0, 10).every((s) => s === 401)).toBe(true);
    expect(statuses[10]).toBe(429);
  });
});

describe('errors', () => {
  it('answers unknown routes and malformed JSON in the standard shape', async () => {
    const missing = await ctx.app.inject({ method: 'GET', url: '/v1/nope' });
    expect(missing.statusCode).toBe(404);
    expect(missing.json().error.code).toBe('NOT_FOUND');

    const malformed = await ctx.app.inject({
      method: 'POST',
      url: '/v1/auth/login',
      headers: { 'content-type': 'application/json' },
      payload: '{nope',
    });
    expect(malformed.statusCode).toBe(400);
    expect(malformed.json().error.code).toBe('BAD_REQUEST');
  });
});

describe('abuse protection', () => {
  it('allows at most five guesses even when they arrive in parallel', async () => {
    const userId = (await post('/v1/auth/register', studentBody())).json<{ userId: string }>().userId;
    const code = ctx.notifier.lastCode();
    const wrong = code === '000000' ? '111111' : '000000';

    const burst = await Promise.all(
      Array.from({ length: 12 }, () => post('/v1/auth/verify', { userId, code: wrong })),
    );
    const guessesChecked = burst.filter((r) => r.json().error.code === 'OTP_INVALID').length;
    expect(guessesChecked).toBeLessThanOrEqual(5);
    expect((await post('/v1/auth/verify', { userId, code })).statusCode).toBe(429);
  });

  it('keeps per-destination code limits when a signup is re-created', async () => {
    for (let i = 0; i < 5; i++) {
      expect((await post('/v1/auth/register', studentBody())).statusCode).toBe(201);
      ctx.clock.advance(61_000);
    }
    const sixth = await post('/v1/auth/register', studentBody());
    expect(sixth.statusCode).toBe(429);
    expect(sixth.json().error.code).toBe('OTP_LIMIT_REACHED');
  });

  it('does not leak provider errors to the client', async () => {
    ctx.notifier.failNext = true;
    const res = await post('/v1/auth/register', studentBody());
    expect(res.json().error.details).toBeUndefined();
  });

  it('ignores X-Forwarded-For unless a proxy is configured', async () => {
    const limited = await createTestApp({ rateLimit: true });
    const statuses: number[] = [];
    for (let i = 0; i < 11; i++) {
      const res = await limited.app.inject({
        method: 'POST',
        url: '/v1/auth/login',
        headers: { 'x-forwarded-for': `203.0.113.${i}` },
        payload: { identifier: 'ghost@example.com', password: 'x' },
      });
      statuses.push(res.statusCode);
    }
    expect(statuses[10]).toBe(429);
  });
});

describe('secondary contacts', () => {
  const signUpWithBoth = async () => {
    const userId = (
      await post('/v1/auth/register', studentBody({ phone: '01912345678', dateOfBirth: DOB.student16 }))
    ).json<{ userId: string }>().userId;
    const verify = await post('/v1/auth/verify', { userId, code: ctx.notifier.lastCode() });
    return { userId, user: verify.json().user };
  };

  it('only marks the contact that received the code as verified', async () => {
    const { user } = await signUpWithBoth();
    expect(user).toMatchObject({ emailVerified: true, phoneVerified: false });
  });

  it('cannot sign in or reset the password through an unverified number', async () => {
    await signUpWithBoth();
    const login = await post('/v1/auth/login', { identifier: '01912345678', password: 'study1234' });
    expect(login.statusCode).toBe(401);

    ctx.clock.advance(61_000);
    const sentBefore = ctx.notifier.sent.length;
    await post('/v1/auth/password/forgot', { identifier: '01912345678' });
    expect(ctx.notifier.sent).toHaveLength(sentBefore);
  });

  it('releases an unverified number to the person who really owns it', async () => {
    const { userId } = await signUpWithBoth();
    ctx.clock.advance(61_000);
    const owner = await post(
      '/v1/auth/register',
      studentBody({ role: 'PARENT', email: 'ammu@example.com', phone: '01912345678', dateOfBirth: DOB.parent }),
    );
    expect(owner.statusCode).toBe(201);
    expect((await prisma.user.findUniqueOrThrow({ where: { id: userId } })).phone).toBeNull();
  });
});
