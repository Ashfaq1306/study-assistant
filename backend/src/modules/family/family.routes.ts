import type { PrismaClient } from '@prisma/client';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { currentUser, requireAuth } from '../../plugins/auth-guard.js';
import { parse } from '../../lib/validate.js';
import type { FamilyService } from './family.service.js';

const LinkBody = z.object({ code: z.string().trim().min(1, 'Scan or type the code.').max(64) });
const LinkParams = z.object({ id: z.string().min(1) });

export const familyRoutes =
  (prisma: PrismaClient, family: FamilyService): FastifyPluginAsync =>
  async (app) => {
    app.post(
      '/pairing-code',
      { preHandler: requireAuth(prisma, ['STUDENT']) },
      async (request) => family.createPairingCode(currentUser(request)),
    );

    app.post(
      '/links',
      {
        preHandler: requireAuth(prisma, ['PARENT']),
        config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
      },
      async (request, reply) => {
        const { code } = parse(LinkBody, request.body);
        return reply.code(201).send(await family.linkParent(currentUser(request), code));
      },
    );

    app.get(
      '/links',
      { preHandler: requireAuth(prisma, ['STUDENT', 'PARENT']) },
      async (request) => ({ links: await family.listLinks(currentUser(request)) }),
    );

    app.delete(
      '/links/:id',
      { preHandler: requireAuth(prisma, ['STUDENT', 'PARENT']) },
      async (request, reply) => {
        const { id } = parse(LinkParams, request.params);
        await family.unlink(currentUser(request), id);
        return reply.code(204).send();
      },
    );
  };
