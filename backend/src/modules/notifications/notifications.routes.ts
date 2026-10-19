import type { PrismaClient } from '@prisma/client';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { currentUser, requireAuth } from '../../plugins/auth-guard.js';
import { parse } from '../../lib/validate.js';
import type { NotificationsService } from './notifications.service.js';

const ListQuery = z.object({ limit: z.coerce.number().int().min(1).max(100).default(30) });
const ReadBody = z.object({ ids: z.array(z.string().min(1)).max(100).optional() }).default({});

/** /v1/notifications: in-app alerts for any signed-in user. */
export const notificationsRoutes =
  (prisma: PrismaClient, notifications: NotificationsService): FastifyPluginAsync =>
  async (app) => {
    app.addHook('preHandler', requireAuth(prisma));

    app.get('/', async (request) => {
      const { limit } = parse(ListQuery, request.query);
      return notifications.list(currentUser(request).id, limit);
    });

    app.post('/read', async (request, reply) => {
      const { ids } = parse(ReadBody, request.body ?? {});
      await notifications.markRead(currentUser(request).id, ids);
      return reply.code(204).send();
    });
  };
