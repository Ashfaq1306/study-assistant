import type { PrismaClient, Role, User } from '@prisma/client';
import { PARENTAL_CONTROL_AGE, ageOn, toIsoDate } from '../../lib/age.js';
import { notFound } from '../../lib/errors.js';
import type { Clock } from '../../lib/clock.js';

export interface PublicUser {
  id: string;
  role: Role;
  name: string;
  email: string | null;
  phone: string | null;
  dateOfBirth: string;
  age: number;
  verified: boolean;
  /** Whether a code was received on each contact; only verified contacts can sign in. */
  emailVerified: boolean;
  phoneVerified: boolean;
  /** Students only. `required` means the app stays locked until a parent links. */
  parentalControl: { required: boolean; linkedParents: number } | null;
  /** Parents only. */
  linkedChildren: number | null;
}

export class UsersService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly clock: Clock,
  ) {}

  /** Students under 15 must have a parent linked before they can use study features. */
  requiresParentalControl(user: Pick<User, 'role' | 'dateOfBirth'>): boolean {
    return user.role === 'STUDENT' && ageOn(user.dateOfBirth, this.clock()) < PARENTAL_CONTROL_AGE;
  }

  async getProfile(userId: string): Promise<PublicUser> {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      include: { _count: { select: { parentLinks: true, childLinks: true } } },
    });
    if (!user) throw notFound('Account not found.');
    return this.toPublic(user, user._count.parentLinks, user._count.childLinks);
  }

  async updateName(userId: string, name: string): Promise<PublicUser> {
    await this.prisma.user.update({ where: { id: userId }, data: { name } });
    return this.getProfile(userId);
  }

  private toPublic(user: User, parentCount: number, childCount: number): PublicUser {
    return {
      id: user.id,
      role: user.role,
      name: user.name,
      email: user.email,
      phone: user.phone,
      dateOfBirth: toIsoDate(user.dateOfBirth),
      age: ageOn(user.dateOfBirth, this.clock()),
      verified: user.verifiedAt !== null,
      emailVerified: user.emailVerifiedAt !== null,
      phoneVerified: user.phoneVerifiedAt !== null,
      parentalControl:
        user.role === 'STUDENT'
          ? { required: this.requiresParentalControl(user), linkedParents: parentCount }
          : null,
      linkedChildren: user.role === 'PARENT' ? childCount : null,
    };
  }
}
