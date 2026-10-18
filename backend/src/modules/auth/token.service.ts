import type { PrismaClient, Role, User } from '@prisma/client';
import { randomToken, sha256 } from '../../lib/crypto.js';
import { AppError } from '../../lib/errors.js';
import type { Clock } from '../../lib/clock.js';

export const ACCESS_TOKEN_TTL_SECONDS = 15 * 60;
export const REFRESH_TOKEN_TTL_MS = 30 * 24 * 3_600_000;

export interface AccessClaims {
  sub: string;
  role: Role;
}

export type SignAccessToken = (claims: AccessClaims) => string;

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  /** Seconds until the access token expires. */
  expiresIn: number;
}

const invalidRefresh = () =>
  new AppError(401, 'INVALID_REFRESH_TOKEN', 'Your session has ended. Please sign in again.');

/**
 * Short-lived JWT access tokens plus opaque, rotating refresh tokens.
 * Only a SHA-256 of each refresh token is stored. Presenting a token that was
 * already rotated means it leaked, so the whole session family is revoked.
 */
export class TokenService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly sign: SignAccessToken,
    private readonly clock: Clock,
  ) {}

  async issue(user: Pick<User, 'id' | 'role'>, userAgent?: string, familyId?: string): Promise<AuthTokens> {
    const refreshToken = randomToken(48);
    await this.prisma.session.create({
      data: {
        userId: user.id,
        tokenHash: sha256(refreshToken),
        familyId: familyId ?? randomToken(16),
        expiresAt: new Date(this.clock().getTime() + REFRESH_TOKEN_TTL_MS),
        userAgent: userAgent?.slice(0, 255),
      },
    });
    return {
      accessToken: this.sign({ sub: user.id, role: user.role }),
      refreshToken,
      expiresIn: ACCESS_TOKEN_TTL_SECONDS,
    };
  }

  async rotate(refreshToken: string, userAgent?: string): Promise<{ user: User; tokens: AuthTokens }> {
    const now = this.clock();
    const session = await this.prisma.session.findUnique({
      where: { tokenHash: sha256(refreshToken) },
      include: { user: true },
    });
    if (!session) throw invalidRefresh();

    if (session.revokedAt || session.replacedAt) {
      await this.revokeFamily(session.familyId);
      throw invalidRefresh();
    }
    if (session.expiresAt <= now || session.user.disabledAt) throw invalidRefresh();

    const { count } = await this.prisma.session.updateMany({
      where: { id: session.id, replacedAt: null, revokedAt: null },
      data: { replacedAt: now },
    });
    if (count === 0) {
      // Lost a race with another refresh of the same token: treat as reuse.
      await this.revokeFamily(session.familyId);
      throw invalidRefresh();
    }

    const tokens = await this.issue(session.user, userAgent, session.familyId);
    return { user: session.user, tokens };
  }

  /** Signs out one device. Unknown tokens are ignored so logout always succeeds. */
  async revoke(refreshToken: string): Promise<void> {
    const session = await this.prisma.session.findUnique({
      where: { tokenHash: sha256(refreshToken) },
      select: { familyId: true },
    });
    if (session) await this.revokeFamily(session.familyId);
  }

  async revokeAllForUser(userId: string): Promise<void> {
    await this.prisma.session.updateMany({
      where: { userId, revokedAt: null },
      data: { revokedAt: this.clock() },
    });
  }

  private async revokeFamily(familyId: string): Promise<void> {
    await this.prisma.session.updateMany({
      where: { familyId, revokedAt: null },
      data: { revokedAt: this.clock() },
    });
  }
}
