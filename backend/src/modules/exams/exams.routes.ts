import type { PrismaClient } from '@prisma/client';
import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { currentUser, requireAuth } from '../../plugins/auth-guard.js';
import { parse } from '../../lib/validate.js';
import { TutorBody, type TutorService } from '../tutor/tutor.service.js';
import type { ExamsService } from './exams.service.js';

const IdParams = z.object({ id: z.string().min(1) });
const SubmitBody = z.object({
  /** questionId -> answer: MCQ option index ("0"–"3"), "true"/"false", or text. */
  answers: z.record(z.string().max(40), z.string().max(1000)),
});
const ListQuery = z.object({ limit: z.coerce.number().int().min(1).max(100).default(20) });

/** /v1: exams that unlock study sessions, and the AI study helper. */
export const examsRoutes =
  (prisma: PrismaClient, exams: ExamsService, tutor: TutorService): FastifyPluginAsync =>
  async (app) => {
    app.addHook('preHandler', requireAuth(prisma, ['STUDENT']));

    // AI calls cost money: a tighter limit, per account (a school network shares one IP).
    const aiLimit = {
      rateLimit: {
        max: 20,
        timeWindow: '1 minute',
        keyGenerator: (request: FastifyRequest) => {
          const token = request.headers.authorization?.replace(/^Bearer /i, '');
          const sub = token ? (app.jwt.decode<{ sub?: string }>(token)?.sub ?? null) : null;
          return sub ? `user:${sub}` : request.ip;
        },
      },
    };

    app.post('/sessions/:id/exam', { config: aiLimit }, async (request) => {
      const { id } = parse(IdParams, request.params);
      return exams.startForSession(currentUser(request), id);
    });

    app.post('/exams/:id/submit', { config: aiLimit }, async (request) => {
      const { id } = parse(IdParams, request.params);
      const { answers } = parse(SubmitBody, request.body);
      return exams.submit(currentUser(request), id, answers);
    });

    app.get('/exams/:id', async (request) => {
      const { id } = parse(IdParams, request.params);
      return exams.get(currentUser(request).id, id);
    });

    app.get('/exams', async (request) => {
      const { limit } = parse(ListQuery, request.query);
      return { exams: await exams.list(currentUser(request).id, limit) };
    });

    app.post('/tutor', { config: aiLimit }, async (request) => {
      const body = parse(TutorBody, request.body);
      return tutor.reply(currentUser(request), body);
    });
  };
