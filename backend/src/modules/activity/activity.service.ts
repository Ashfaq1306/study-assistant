import type { PrismaClient } from '@prisma/client';
import type { FastifyBaseLogger, FastifyRequest } from 'fastify';
import type { Clock } from '../../lib/clock.js';

export type ActivityKind =
  | 'SIGNUP'
  | 'LOGIN'
  | 'LOGOUT'
  | 'PASSWORD_RESET'
  | 'ADMIN_DISABLED'
  | 'ADMIN_ENABLED'
  | 'ADMIN_SIGNED_OUT'
  | 'ADMIN_PASSWORD_RESET'
  | 'ADMIN_UNLOCKED'
  | 'ADMIN_SETTINGS';

export interface ActivityContext {
  ip?: string;
  userAgent?: string;
  actorId?: string;
  detail?: string;
}

/** Where a request came from, for the activity log. */
export const requestContext = (request: FastifyRequest): ActivityContext => ({
  ip: request.ip,
  userAgent: request.headers['user-agent']?.slice(0, 300),
});

/** How long a recorded activity time stays fresh before the next request updates it. */
const ACTIVE_WRITE_GAP_MS = 2 * 60 * 1000;

/**
 * The account activity log the admin panel reads. Recording never fails the
 * request it belongs to: a lost log line is better than a failed sign-in.
 */
export class ActivityService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly clock: Clock,
    private readonly log: FastifyBaseLogger,
  ) {}

  async record(userId: string, kind: ActivityKind, context: ActivityContext = {}): Promise<void> {
    try {
      await this.prisma.activityEvent.create({
        data: {
          userId,
          kind,
          actorId: context.actorId,
          ip: context.ip,
          userAgent: context.userAgent,
          detail: context.detail?.slice(0, 300),
          createdAt: this.clock(),
        },
      });
    } catch (err) {
      this.log.warn({ err, userId, kind }, 'could not record activity');
    }
  }

  /** Marks the account as active now, writing at most every couple of minutes. */
  async touch(userId: string, lastActiveAt: Date | null): Promise<void> {
    const now = this.clock();
    if (lastActiveAt && now.getTime() - lastActiveAt.getTime() < ACTIVE_WRITE_GAP_MS) return;
    try {
      await this.prisma.user.update({ where: { id: userId }, data: { lastActiveAt: now } });
    } catch {
      // Best effort only.
    }
  }
}
