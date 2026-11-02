import type { PrismaClient } from '@prisma/client';
import type { FastifyPluginAsync } from 'fastify';
import { currentUser, requireAuth } from '../../plugins/auth-guard.js';
import { parse } from '../../lib/validate.js';
import type { ExamsService } from '../exams/exams.service.js';
import { ChildParams, CreateLockBody, IdParams, OffsetQuery, QuestionSetBody } from './parent.schemas.js';
import type { ParentService } from './parent.service.js';

/** /v1/parent: a parent's view of their linked children, their locks and question sets. */
export const parentRoutes =
  (prisma: PrismaClient, parent: ParentService): FastifyPluginAsync =>
  async (app) => {
    app.addHook('preHandler', requireAuth(prisma, ['PARENT']));

    app.get('/children', async (request) => {
      const { utcOffsetMinutes } = parse(OffsetQuery, request.query);
      return { children: await parent.children(currentUser(request), utcOffsetMinutes) };
    });

    app.get('/children/:childId', async (request) => {
      const { childId } = parse(ChildParams, request.params);
      const { utcOffsetMinutes } = parse(OffsetQuery, request.query);
      return parent.child(currentUser(request), childId, utcOffsetMinutes);
    });

    app.post('/children/:childId/locks', async (request, reply) => {
      const { childId } = parse(ChildParams, request.params);
      const body = parse(CreateLockBody, request.body);
      return reply.code(201).send(await parent.createLock(currentUser(request), childId, body));
    });

    app.post('/locks/:id/cancel', async (request) => {
      const { id } = parse(IdParams, request.params);
      return parent.cancelLock(currentUser(request), id);
    });

    app.get('/question-sets', async (request) => ({ questionSets: await parent.questionSets(currentUser(request)) }));

    app.post('/question-sets', async (request, reply) => {
      const body = parse(QuestionSetBody, request.body);
      return reply.code(201).send(await parent.createQuestionSet(currentUser(request), body));
    });

    app.put('/question-sets/:id', async (request) => {
      const { id } = parse(IdParams, request.params);
      const body = parse(QuestionSetBody, request.body);
      return parent.updateQuestionSet(currentUser(request), id, body);
    });

    app.delete('/question-sets/:id', async (request, reply) => {
      const { id } = parse(IdParams, request.params);
      await parent.deleteQuestionSet(currentUser(request), id);
      return reply.code(204).send();
    });
  };

/** /v1/locks: a student's view of the locks their parents set, and the exam that lifts one. */
export const studentLockRoutes =
  (prisma: PrismaClient, parent: ParentService, exams: ExamsService): FastifyPluginAsync =>
  async (app) => {
    app.addHook('preHandler', requireAuth(prisma, ['STUDENT']));

    app.get('/', async (request) => ({ locks: await parent.locksFor(currentUser(request).id) }));

    app.post('/:id/exam', { config: { rateLimit: { max: 20, timeWindow: '1 minute' } } }, async (request) => {
      const { id } = parse(IdParams, request.params);
      return exams.startForLock(currentUser(request), id);
    });
  };
