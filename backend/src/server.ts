import { PrismaClient } from '@prisma/client';
import { buildApp } from './app.js';
import { loadEnv } from './config/env.js';

const env = loadEnv();
const prisma = new PrismaClient({ datasourceUrl: env.DATABASE_URL });

const app = await buildApp({
  env,
  prisma,
  logger:
    env.NODE_ENV === 'development'
      ? { level: env.LOG_LEVEL, transport: { target: 'pino-pretty', options: { translateTime: 'HH:MM:ss' } } }
      : undefined,
});

const shutdown = async (signal: string) => {
  app.log.info({ signal }, 'shutting down');
  await app.close();
  await prisma.$disconnect();
  process.exit(0);
};
process.once('SIGINT', () => void shutdown('SIGINT'));
process.once('SIGTERM', () => void shutdown('SIGTERM'));

try {
  await app.listen({ port: env.PORT, host: env.HOST });
} catch (err) {
  app.log.fatal({ err }, 'failed to start');
  await prisma.$disconnect();
  process.exit(1);
}
