import type { PrismaClient } from '@prisma/client';
import type { FastifyPluginAsync } from 'fastify';
import { currentUser, requireAuth } from '../../plugins/auth-guard.js';
import { parse } from '../../lib/validate.js';
import { BulkBody, EventBody, IdParams, IMPORT_BODY_LIMIT, ImportBody } from './calendar.schemas.js';
import type { CalendarService } from './calendar.service.js';

/** /v1/calendar: exams, classes, assignments, holidays, and importing an academic calendar. */
export const calendarRoutes =
  (prisma: PrismaClient, calendar: CalendarService): FastifyPluginAsync =>
  async (app) => {
    app.addHook('preHandler', requireAuth(prisma));

    app.get('/', async (request) => ({ events: await calendar.list(currentUser(request).id) }));

    app.post('/', async (request, reply) => {
      const body = parse(EventBody, request.body);
      return reply.code(201).send(await calendar.create(currentUser(request), body));
    });

    app.post('/bulk', async (request, reply) => {
      const { events } = parse(BulkBody, request.body);
      return reply.code(201).send({ events: await calendar.createMany(currentUser(request), events) });
    });

    app.put('/:id', async (request) => {
      const { id } = parse(IdParams, request.params);
      return calendar.update(currentUser(request), id, parse(EventBody, request.body));
    });

    app.delete('/:id', async (request, reply) => {
      const { id } = parse(IdParams, request.params);
      await calendar.remove(currentUser(request), id);
      return reply.code(204).send();
    });

    // Reading a calendar with AI costs money: a tight per-IP limit.
    app.post(
      '/import',
      { bodyLimit: IMPORT_BODY_LIMIT, config: { rateLimit: { max: 10, timeWindow: '1 minute' } } },
      async (request) => {
        const body = parse(ImportBody, request.body);
        return { events: await calendar.import(currentUser(request), body) };
      },
    );
  };
