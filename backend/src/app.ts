import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import jwt from '@fastify/jwt';
import rateLimit from '@fastify/rate-limit';
import type { PrismaClient } from '@prisma/client';
import Fastify, { type FastifyInstance, type FastifyServerOptions } from 'fastify';
import type { Env } from './config/env.js';
import { systemClock, type Clock } from './lib/clock.js';
import { AppError } from './lib/errors.js';
import { authRoutes } from './modules/auth/auth.routes.js';
import { AuthService } from './modules/auth/auth.service.js';
import { OtpService } from './modules/auth/otp.service.js';
import { ACCESS_TOKEN_TTL_SECONDS, TokenService } from './modules/auth/token.service.js';
import { familyRoutes } from './modules/family/family.routes.js';
import { FamilyService } from './modules/family/family.service.js';
import { createNotifier, type Notifier } from './modules/notify/notifier.js';
import { usersRoutes } from './modules/users/users.routes.js';
import { UsersService } from './modules/users/users.service.js';

export interface AppOptions {
  env: Env;
  prisma: PrismaClient;
  /** Defaults to the providers configured in `env`. */
  notifier?: Notifier;
  clock?: Clock;
  rateLimit?: boolean;
  logger?: FastifyServerOptions['logger'];
}

export async function buildApp(options: AppOptions): Promise<FastifyInstance> {
  const { env, prisma, clock = systemClock } = options;
  const hops = env.TRUST_PROXY;
  // A hop count means: trust that many proxies in front of us, nearest first.
  const trustProxy = typeof hops === 'number' ? (_address: string, hop: number) => hop < hops : hops;
  const app = Fastify({
    logger: options.logger ?? { level: env.LOG_LEVEL, redact: ['req.headers.authorization'] },
    trustProxy,
    bodyLimit: 256 * 1024,
  });

  await app.register(helmet);
  await app.register(cors, { origin: env.CORS_ORIGINS.length > 0 ? env.CORS_ORIGINS : false });
  if (options.rateLimit !== false) {
    await app.register(rateLimit, {
      max: 300,
      timeWindow: '1 minute',
      errorResponseBuilder: (_request, context) =>
        new AppError(429, 'RATE_LIMITED', 'Too many requests. Please slow down and try again.', {
          retryAfterSeconds: Math.ceil(context.ttl / 1000),
        }),
    });
  }
  await app.register(jwt, {
    secret: env.JWT_SECRET,
    sign: { expiresIn: `${ACCESS_TOKEN_TTL_SECONDS}s` },
  });

  app.setErrorHandler((error, request, reply) => {
    if (error instanceof AppError) {
      return reply
        .code(error.statusCode)
        .send({ error: { code: error.code, message: error.message, details: error.details } });
    }
    const status = (error as { statusCode?: number }).statusCode;
    if (status && status >= 400 && status < 500) {
      // Framework-level client errors: malformed JSON, wrong content type, too large.
      return reply.code(status).send({ error: { code: 'BAD_REQUEST', message: 'The request was not valid.' } });
    }
    request.log.error({ err: error }, 'unhandled error');
    return reply
      .code(500)
      .send({ error: { code: 'INTERNAL', message: 'Something went wrong on our side. Please try again.' } });
  });

  app.setNotFoundHandler((_request, reply) =>
    reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Not found.' } }),
  );

  const notifier = options.notifier ?? createNotifier(env, app.log);
  const users = new UsersService(prisma, clock);
  const otp = new OtpService(prisma, notifier, env.OTP_SECRET, clock, app.log);
  const tokens = new TokenService(prisma, (claims) => app.jwt.sign(claims), clock);
  const auth = new AuthService(prisma, otp, tokens, users, clock);
  const family = new FamilyService(prisma, users, env.OTP_SECRET, clock);

  app.get('/health', () => ({ status: 'ok' }));
  await app.register(authRoutes(auth), { prefix: '/v1/auth' });
  await app.register(usersRoutes(prisma, users), { prefix: '/v1/me' });
  await app.register(familyRoutes(prisma, family), { prefix: '/v1/family' });

  return app;
}
