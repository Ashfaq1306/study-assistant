import type { AiStatusService } from '../ai/ai.status.js';
import type { PrismaClient } from '@prisma/client';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { parse } from '../../lib/validate.js';
import { currentUser, requireAuth } from '../../plugins/auth-guard.js';
import { requestContext } from '../activity/activity.service.js';
import { SettingsSchema, type Settings } from '../config/config.service.js';
import type { AdminService } from './admin.service.js';

const ListQuery = z.object({
  q: z.string().trim().max(100).optional(),
  role: z.enum(['STUDENT', 'PARENT', 'ADMIN']).optional(),
  status: z.enum(['active', 'disabled', 'unverified']).optional(),
  presence: z.enum(['online', 'signedIn', 'signedOut']).optional(),
  page: z.coerce.number().int().min(1).max(10_000).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(25),
});

const ActivityQuery = z.object({
  userId: z.string().min(1).max(64).optional(),
  kind: z.string().regex(/^[A-Z_]{3,40}$/).optional(),
  page: z.coerce.number().int().min(1).max(10_000).default(1),
  pageSize: z.coerce.number().int().min(1).max(200).default(50),
});

const StudyQuery = z.object({ days: z.coerce.number().int().min(0).max(3650).default(7) });
const IdParams = z.object({ id: z.string().min(1).max(64) });
const DisableBody = z.object({ disabled: z.boolean() });
const UnlockBody = z.object({ reason: z.string().trim().max(200).optional() });
/** Unknown keys are refused, so a typo can't silently do nothing. */
const SettingsPatch = SettingsSchema.partial().strict();

/** The web admin panel's API. Every route needs an ADMIN account. */
export const adminRoutes =
  (prisma: PrismaClient, admin: AdminService, aiStatus: AiStatusService): FastifyPluginAsync =>
  async (app) => {
    app.addHook('preHandler', requireAuth(prisma, ['ADMIN']));

    app.get('/stats', () => admin.stats());

    app.get('/users', (request) => admin.listUsers(parse(ListQuery, request.query)));

    app.get('/users/:id', (request) => admin.getUser(parse(IdParams, request.params).id));

    app.patch('/users/:id', async (request) => {
      const { id } = parse(IdParams, request.params);
      const { disabled } = parse(DisableBody, request.body);
      return admin.setDisabled(currentUser(request).id, id, disabled, requestContext(request));
    });

    app.post('/users/:id/sign-out', async (request) => {
      const { id } = parse(IdParams, request.params);
      return admin.signOutEverywhere(currentUser(request).id, id, requestContext(request));
    });

    app.post('/users/:id/reset-password', async (request) => {
      const { id } = parse(IdParams, request.params);
      return admin.resetPassword(currentUser(request).id, id, requestContext(request));
    });

    app.post('/users/:id/unlock', async (request) => {
      const { id } = parse(IdParams, request.params);
      const { reason } = parse(UnlockBody, request.body ?? {});
      const actor = currentUser(request);
      request.log.warn({ adminId: actor.id, userId: id }, 'admin unlocked a phone without an exam');
      return admin.unlockPhone(actor.id, id, reason, requestContext(request));
    });

    app.get('/study', (request) => admin.study(parse(StudyQuery, request.query).days));

    app.get('/activity', (request) => admin.activityLog(parse(ActivityQuery, request.query)));

    // Whether the AI key works: the last check, or a fresh one on demand ("Check now").
    app.get('/ai', () => aiStatus.current);
    app.post('/ai/check', () => aiStatus.refresh());

    app.get('/settings', () => admin.settings());

    app.patch('/settings', async (request) => {
      // Validated here (unknown keys refused); the service then stores only the keys that were sent.
      parse(SettingsPatch, request.body);
      return admin.updateSettings(currentUser(request).id, request.body as Partial<Settings>, requestContext(request));
    });

    /** Tokens for the admin panel opened inside the app (its own session; see AdminService.panelSession). */
    app.post('/panel-session', async (request) => ({
      tokens: await admin.panelSession(currentUser(request).id, request.headers['user-agent']),
    }));
  };
