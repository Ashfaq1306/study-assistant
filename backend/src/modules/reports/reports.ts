import type { PrismaClient } from '@prisma/client';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { notFound } from '../../lib/errors.js';
import { parse } from '../../lib/validate.js';
import { currentUser, requireAuth } from '../../plugins/auth-guard.js';

/**
 * Reports of AI answers and questions that are wrong or inappropriate. Google Play requires apps
 * with AI-generated content to let users report it; the Control Room lists the reports.
 */
const ReportBody = z.object({
  kind: z.enum(['TUTOR', 'EXAM', 'CALENDAR']),
  content: z.string().trim().min(1).max(4000),
  reason: z.string().trim().max(500).optional(),
  refId: z.string().max(64).optional(),
});

const ListQuery = z.object({
  status: z.enum(['open', 'resolved', 'all']).default('open'),
  page: z.coerce.number().int().min(1).max(10_000).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(50),
});

/** A user may send at most this many reports a day (spam guard). */
const DAILY_LIMIT = 30;

export const reportRoutes =
  (prisma: PrismaClient): FastifyPluginAsync =>
  async (app) => {
    app.addHook('preHandler', requireAuth(prisma));

    app.post('/', async (request, reply) => {
      const body = parse(ReportBody, request.body);
      const user = currentUser(request);
      const today = await prisma.contentReport.count({
        where: { userId: user.id, createdAt: { gte: new Date(Date.now() - 86_400_000) } },
      });
      if (today >= DAILY_LIMIT) return reply.code(202).send({ received: true });
      await prisma.contentReport.create({ data: { userId: user.id, ...body } });
      return reply.code(201).send({ received: true });
    });
  };

export const adminReportRoutes =
  (prisma: PrismaClient): FastifyPluginAsync =>
  async (app) => {
    app.addHook('preHandler', requireAuth(prisma, ['ADMIN']));

    app.get('/', async (request) => {
      const q = parse(ListQuery, request.query);
      const where = q.status === 'all' ? {} : { resolvedAt: q.status === 'open' ? null : { not: null } };
      const [total, reports] = await Promise.all([
        prisma.contentReport.count({ where }),
        prisma.contentReport.findMany({
          where,
          orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
          skip: (q.page - 1) * q.pageSize,
          take: q.pageSize,
          include: { user: { select: { id: true, name: true, role: true } } },
        }),
      ]);
      return { total, page: q.page, pageSize: q.pageSize, reports };
    });

    app.patch('/:id', async (request) => {
      const { id } = parse(z.object({ id: z.string().min(1).max(64) }), request.params);
      const { resolved } = parse(z.object({ resolved: z.boolean() }), request.body);
      const found = await prisma.contentReport.findUnique({ where: { id }, select: { id: true } });
      if (!found) throw notFound('That report does not exist.');
      return prisma.contentReport.update({ where: { id }, data: { resolvedAt: resolved ? new Date() : null } });
    });
  };
