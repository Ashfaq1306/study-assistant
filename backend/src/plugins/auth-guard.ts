import type { PrismaClient, Role, User } from '@prisma/client';
import type { FastifyRequest, preHandlerAsyncHookHandler } from 'fastify';
import { forbidden, unauthorized } from '../lib/errors.js';
import type { AccessClaims } from '../modules/auth/token.service.js';

declare module '@fastify/jwt' {
  interface FastifyJWT {
    payload: AccessClaims;
    user: AccessClaims;
  }
}

declare module 'fastify' {
  interface FastifyRequest {
    authUser?: User;
  }
}

/**
 * Verifies the bearer token and loads the account, so a disabled account is
 * locked out immediately rather than when its access token expires.
 */
export function requireAuth(prisma: PrismaClient, roles?: readonly Role[]): preHandlerAsyncHookHandler {
  return async (request) => {
    try {
      await request.jwtVerify();
    } catch {
      throw unauthorized();
    }
    const user = await prisma.user.findUnique({ where: { id: request.user.sub } });
    if (!user || user.disabledAt || !user.verifiedAt) throw unauthorized();
    if (roles && !roles.includes(user.role)) throw forbidden();
    touchLastActive(prisma, user);
    request.authUser = user;
  };
}

const ACTIVE_WRITE_GAP_MS = 2 * 60_000;
/** When this process last stamped each account, so a burst of parallel requests writes once. */
const lastStamped = new Map<string, number>();

/** "Last active" for the admin panel: at most one write per account every 2 minutes, never awaited. */
function touchLastActive(prisma: PrismaClient, user: User): void {
  const now = Date.now();
  const seen = Math.max(user.lastActiveAt?.getTime() ?? 0, lastStamped.get(user.id) ?? 0);
  if (now - seen < ACTIVE_WRITE_GAP_MS) return;
  if (lastStamped.size > 50_000) lastStamped.clear();
  lastStamped.set(user.id, now);
  prisma.user.update({ where: { id: user.id }, data: { lastActiveAt: new Date(now) } }).catch(() => undefined);
}

export function currentUser(request: FastifyRequest): User {
  if (!request.authUser) throw unauthorized();
  return request.authUser;
}
