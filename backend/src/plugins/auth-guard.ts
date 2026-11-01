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
    // "Last active" for the admin panel, written at most every 2 minutes and never awaited.
    if (!user.lastActiveAt || Date.now() - user.lastActiveAt.getTime() > 2 * 60_000) {
      prisma.user.update({ where: { id: user.id }, data: { lastActiveAt: new Date() } }).catch(() => undefined);
    }
    request.authUser = user;
  };
}

export function currentUser(request: FastifyRequest): User {
  if (!request.authUser) throw unauthorized();
  return request.authUser;
}
