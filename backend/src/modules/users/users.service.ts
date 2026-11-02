import type { PrismaClient, Role, User } from '@prisma/client';
import { PARENTAL_CONTROL_AGE, ageOn, toIsoDate } from '../../lib/age.js';
import { verifyPassword } from '../../lib/crypto.js';
import { AppError, notFound } from '../../lib/errors.js';
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

  /**
   * Deletes the account and everything that belongs to it (study history, photos, exams,
   * calendar, devices, family links), after the password is confirmed. Google Play requires
   * this in the app.
   *
   * A student cannot delete the account while a lock is running: the phone would forget the
   * lock, which would be a way around the exam.
   */
  async deleteAccount(user: User, password: string): Promise<void> {
    if (!(await verifyPassword(password, user.passwordHash))) {
      throw new AppError(400, 'WRONG_PASSWORD', 'That password is not right.', {
        fields: { password: ['That password is not right.'] },
      });
    }
    if (user.role === 'ADMIN') {
      throw new AppError(409, 'ADMIN_ACCOUNT', 'Admin accounts are removed on the server.');
    }
    if (user.role === 'STUDENT') {
      const [running, parentLocks] = await Promise.all([
        this.prisma.studySession.count({ where: { studentId: user.id, status: { in: ['STUDYING', 'EXAM_PENDING'] } } }),
        this.prisma.parentLock.count({ where: { studentId: user.id, status: 'ACTIVE' } }),
      ]);
      if (running + parentLocks > 0) {
        throw new AppError(
          409,
          'LOCK_ACTIVE',
          'Your apps are locked right now. Pass your exam first, then you can delete your account.',
        );
      }
    }
    // Every related row is removed with the account (onDelete: Cascade in the schema).
    await this.prisma.user.delete({ where: { id: user.id } });
  }

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
