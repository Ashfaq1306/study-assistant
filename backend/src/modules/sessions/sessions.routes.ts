import type { PrismaClient } from '@prisma/client';
import type { FastifyPluginAsync } from 'fastify';
import { currentUser, requireAuth } from '../../plugins/auth-guard.js';
import { parse } from '../../lib/validate.js';
import { ListQuery, SessionParams, StartSessionBody, StatsQuery } from './sessions.schemas.js';
import type { SessionsService } from './sessions.service.js';

export const sessionsRoutes =
  (prisma: PrismaClient, sessions: SessionsService): FastifyPluginAsync =>
  async (app) => {
    app.addHook('preHandler', requireAuth(prisma, ['STUDENT']));

    app.post('/', async (request, reply) => {
      const body = parse(StartSessionBody, request.body);
      return reply.code(201).send(await sessions.start(currentUser(request), body));
    });

    app.get('/active', async (request) => ({ session: await sessions.active(currentUser(request).id) }));

    app.get('/', async (request) => {
      const { limit } = parse(ListQuery, request.query);
      return { sessions: await sessions.list(currentUser(request).id, limit) };
    });

    app.get('/stats', async (request) => {
      const { utcOffsetMinutes } = parse(StatsQuery, request.query);
      return sessions.stats(currentUser(request).id, utcOffsetMinutes);
    });

    app.get('/:id', async (request) => {
      const { id } = parse(SessionParams, request.params);
      return sessions.get(currentUser(request).id, id);
    });

    app.post('/:id/finish', async (request) => {
      const { id } = parse(SessionParams, request.params);
      return sessions.finish(currentUser(request), id);
    });
  };
