import { PrismaClient } from '@prisma/client';
import type { FastifyInstance } from 'fastify';
import { buildApp } from '../src/app.js';
import { loadEnv } from '../src/config/env.js';
import type { Notifier, OutboundMessage } from '../src/modules/notify/notifier.js';

export const env = loadEnv({
  NODE_ENV: 'test',
  DATABASE_URL: process.env.DATABASE_URL ?? 'file:./test.db',
  JWT_SECRET: 'test-jwt-secret-that-is-at-least-32-characters',
  OTP_SECRET: 'test-otp-secret-that-is-at-least-32-characters',
});

export const prisma = new PrismaClient({ datasourceUrl: env.DATABASE_URL });

/** Records messages instead of sending them, so tests can read the OTP. */
export class FakeNotifier implements Notifier {
  readonly sent: OutboundMessage[] = [];
  failNext = false;

  send(message: OutboundMessage): Promise<void> {
    if (this.failNext) {
      this.failNext = false;
      return Promise.reject(new Error('provider down'));
    }
    this.sent.push(message);
    return Promise.resolve();
  }

  lastCode(): string {
    const text = this.sent.at(-1)?.text ?? '';
    const code = /\b(\d{6})\b/.exec(text)?.[1];
    if (!code) throw new Error('no OTP was sent');
    return code;
  }
}

export class TestClock {
  constructor(private now = new Date('2026-06-01T08:00:00.000Z')) {}
  readonly fn = () => new Date(this.now);
  advance(ms: number): void {
    this.now = new Date(this.now.getTime() + ms);
  }
}

export interface TestContext {
  app: FastifyInstance;
  notifier: FakeNotifier;
  clock: TestClock;
}

export async function resetDatabase(): Promise<void> {
  await prisma.$transaction([
    prisma.otpSend.deleteMany(),
    prisma.familyLink.deleteMany(),
    prisma.pairingCode.deleteMany(),
    prisma.session.deleteMany(),
    prisma.otpCode.deleteMany(),
    prisma.user.deleteMany(),
  ]);
}

export async function createTestApp(options: { rateLimit?: boolean } = {}): Promise<TestContext> {
  const notifier = new FakeNotifier();
  const clock = new TestClock();
  const app = await buildApp({
    env,
    prisma,
    notifier,
    clock: clock.fn,
    rateLimit: options.rateLimit ?? false,
    logger: false,
  });
  return { app, notifier, clock };
}

// Ages relative to the test clock (2026-06-01).
export const DOB = { student12: '2014-01-15', student16: '2010-01-15', parent: '1985-03-10' } as const;

let sequence = 0;

export interface SignedInAccount {
  userId: string;
  accessToken: string;
  refreshToken: string;
  email: string;
  password: string;
}

/** Registers and verifies an account through the public API. */
export async function signUp(
  ctx: TestContext,
  overrides: Partial<{ role: 'STUDENT' | 'PARENT'; dateOfBirth: string; name: string }> = {},
): Promise<SignedInAccount> {
  sequence += 1;
  const email = `user${sequence}@example.com`;
  const password = 'secret123';
  const register = await ctx.app.inject({
    method: 'POST',
    url: '/v1/auth/register',
    payload: {
      role: overrides.role ?? 'STUDENT',
      name: overrides.name ?? `User ${sequence}`,
      email,
      password,
      dateOfBirth: overrides.dateOfBirth ?? DOB.student16,
      otpChannel: 'EMAIL',
    },
  });
  if (register.statusCode !== 201) throw new Error(`register failed: ${register.body}`);
  const { userId } = register.json<{ userId: string }>();

  const verify = await ctx.app.inject({
    method: 'POST',
    url: '/v1/auth/verify',
    payload: { userId, code: ctx.notifier.lastCode() },
  });
  if (verify.statusCode !== 200) throw new Error(`verify failed: ${verify.body}`);
  const { tokens } = verify.json<{ tokens: { accessToken: string; refreshToken: string } }>();
  return { userId, email, password, ...tokens };
}

export const bearer = (token: string) => ({ authorization: `Bearer ${token}` });
