import { Prisma, type OtpChannel, type PrismaClient, type User } from '@prisma/client';
import { MAX_AGE, MIN_PARENT_AGE, MIN_STUDENT_AGE, ageOn } from '../../lib/age.js';
import { hashPassword, verifyPassword } from '../../lib/crypto.js';
import { AppError } from '../../lib/errors.js';
import { normalizePhone } from '../../lib/phone.js';
import type { Clock } from '../../lib/clock.js';
import type { PublicUser, UsersService } from '../users/users.service.js';
import type { RegisterInput } from './auth.schemas.js';
import type { OtpIssued, OtpService } from './otp.service.js';
import type { AuthTokens, TokenService } from './token.service.js';

export interface SignedIn {
  user: PublicUser;
  tokens: AuthTokens;
}

const invalidCredentials = () => new AppError(401, 'INVALID_CREDENTIALS', 'Wrong email/mobile number or password.');

const fieldError = (status: number, code: string, field: string, message: string) =>
  new AppError(status, code, message, { fields: { [field]: [message] } });

/** Records that the user proved they control the contact the code went to. */
const contactVerified = (channel: OtpChannel, at: Date): Prisma.UserUpdateInput =>
  channel === 'EMAIL' ? { emailVerifiedAt: at } : { phoneVerifiedAt: at };

export class AuthService {
  /** Compared against when the account does not exist, so response time does not reveal it. */
  private readonly dummyHash = hashPassword('timing-equaliser-not-a-password');

  constructor(
    private readonly prisma: PrismaClient,
    private readonly otp: OtpService,
    private readonly tokens: TokenService,
    private readonly users: UsersService,
    private readonly clock: Clock,
  ) {}

  async register(input: RegisterInput): Promise<{ userId: string; verification: OtpIssued }> {
    const age = ageOn(input.dateOfBirth, this.clock());
    if (input.role === 'STUDENT' && (age < MIN_STUDENT_AGE || age > MAX_AGE)) {
      throw fieldError(
        400,
        'VALIDATION_FAILED',
        'dateOfBirth',
        `Students must be at least ${MIN_STUDENT_AGE} years old.`,
      );
    }
    if (input.role === 'PARENT' && (age < MIN_PARENT_AGE || age > MAX_AGE)) {
      throw fieldError(
        400,
        'VALIDATION_FAILED',
        'dateOfBirth',
        `Parents must be at least ${MIN_PARENT_AGE} years old.`,
      );
    }

    // Check everything that can refuse the request before changing anything,
    // so a refused signup leaves any earlier pending one untouched.
    const holders = await this.findClaims(input.email, input.phone);
    await this.otp.assertCanSend(input.otpChannel === 'EMAIL' ? input.email! : input.phone!);
    await this.releaseUnverifiedClaims(holders, input.email, input.phone);

    let user: User;
    try {
      user = await this.prisma.user.create({
        data: {
          role: input.role,
          name: input.name,
          email: input.email ?? null,
          phone: input.phone ?? null,
          passwordHash: await hashPassword(input.password),
          dateOfBirth: input.dateOfBirth,
          otpChannel: input.otpChannel,
        },
      });
    } catch (err) {
      // Another request registered the same email/phone between our check and insert.
      if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
        throw new AppError(409, 'ACCOUNT_EXISTS', 'An account with these details already exists.');
      }
      throw err;
    }

    const verification = await this.otp.issue(user, 'VERIFY_ACCOUNT', input.otpChannel);
    return { userId: user.id, verification };
  }

  async verifyAccount(userId: string, code: string, userAgent?: string): Promise<SignedIn> {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new AppError(400, 'OTP_EXPIRED', 'This code has expired. Please sign up again.');
    if (user.verifiedAt) {
      throw new AppError(409, 'ALREADY_VERIFIED', 'Your account is already open. Please sign in.');
    }

    const channel = await this.otp.verify(user.id, 'VERIFY_ACCOUNT', code);
    const now = this.clock();
    const verified = await this.prisma.user.update({
      where: { id: user.id },
      data: { verifiedAt: now, ...contactVerified(channel, now) },
    });
    return this.signIn(verified, userAgent);
  }

  async resendVerification(userId: string, channel?: OtpChannel): Promise<OtpIssued> {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user || user.verifiedAt) {
      throw new AppError(400, 'NOTHING_TO_VERIFY', 'This account does not need a code. Please sign in.');
    }
    const target = channel ?? user.otpChannel;
    const issued = await this.otp.issue(user, 'VERIFY_ACCOUNT', target);
    if (target !== user.otpChannel) {
      await this.prisma.user.update({ where: { id: user.id }, data: { otpChannel: target } });
    }
    return issued;
  }

  async login(identifier: string, password: string, userAgent?: string): Promise<SignedIn> {
    const user = await this.findByIdentifier(identifier, { allowPendingSignup: true });
    if (!user) {
      await verifyPassword(password, await this.dummyHash);
      throw invalidCredentials();
    }
    if (!(await verifyPassword(password, user.passwordHash))) throw invalidCredentials();
    if (user.disabledAt) {
      throw new AppError(403, 'ACCOUNT_DISABLED', 'This account has been disabled. Please contact support.');
    }

    if (!user.verifiedAt) {
      // The password is right, so send a code to finish opening the account.
      let verification: OtpIssued | undefined;
      try {
        verification = await this.otp.issue(user, 'VERIFY_ACCOUNT', user.otpChannel);
      } catch (err) {
        if (!(err instanceof AppError && err.statusCode === 429)) throw err;
      }
      throw new AppError(403, 'ACCOUNT_NOT_VERIFIED', 'Enter the code we sent you to open your account.', {
        userId: user.id,
        channel: user.otpChannel,
        verification,
      });
    }

    return this.signIn(user, userAgent);
  }

  /**
   * Always reports success, so this endpoint cannot be used to find out
   * which emails or numbers have accounts.
   */
  async forgotPassword(identifier: string): Promise<{ sent: true; devCode?: string }> {
    const user = await this.findByIdentifier(identifier);
    if (user?.verifiedAt && !user.disabledAt) {
      try {
        const issued = await this.otp.issue(user, 'RESET_PASSWORD', identifier.includes('@') ? 'EMAIL' : 'SMS');
        if (issued.devCode) return { sent: true, devCode: issued.devCode };
      } catch (err) {
        if (!(err instanceof AppError && err.statusCode === 429)) throw err;
      }
    }
    return { sent: true };
  }

  async resetPassword(identifier: string, code: string, newPassword: string, userAgent?: string): Promise<SignedIn> {
    const user = await this.findByIdentifier(identifier);
    if (!user?.verifiedAt || user.disabledAt) {
      throw new AppError(400, 'OTP_INVALID', 'That code is not right.');
    }
    await this.otp.verify(user.id, 'RESET_PASSWORD', code);
    const updated = await this.prisma.user.update({
      where: { id: user.id },
      data: { passwordHash: await hashPassword(newPassword) },
    });
    // A password reset signs every other device out.
    await this.tokens.revokeAllForUser(user.id);
    return this.signIn(updated, userAgent);
  }

  async refresh(refreshToken: string, userAgent?: string): Promise<SignedIn> {
    const { user, tokens } = await this.tokens.rotate(refreshToken, userAgent);
    return { user: await this.users.getProfile(user.id), tokens };
  }

  logout(refreshToken: string): Promise<void> {
    return this.tokens.revoke(refreshToken);
  }

  private async signIn(user: User, userAgent?: string): Promise<SignedIn> {
    const tokens = await this.tokens.issue(user, userAgent);
    return { user: await this.users.getProfile(user.id), tokens };
  }

  /**
   * Finds the account for an email or phone number, but only through a
   * contact the owner has proven they control. Otherwise a mistyped second
   * number could be used to reset someone else's password.
   *
   * `allowPendingSignup` also accepts the contact a not-yet-verified account
   * signed up with, so login can resume verification.
   */
  private async findByIdentifier(
    identifier: string,
    options: { allowPendingSignup?: boolean } = {},
  ): Promise<User | null> {
    const isEmail = identifier.includes('@');
    const phone = isEmail ? null : normalizePhone(identifier);
    const user = isEmail
      ? await this.prisma.user.findUnique({ where: { email: identifier.trim().toLowerCase() } })
      : phone
        ? await this.prisma.user.findUnique({ where: { phone } })
        : null;
    if (!user) return null;

    if (isEmail ? user.emailVerifiedAt : user.phoneVerifiedAt) return user;
    const isSignupContact = user.otpChannel === (isEmail ? 'EMAIL' : 'SMS');
    return options.allowPendingSignup && !user.verifiedAt && isSignupContact ? user : null;
  }

  /**
   * Only a *verified* contact is taken (findClaims throws for those). Unverified
   * ones are released so the real owner can sign up: abandoned signups are
   * deleted, and an unverified secondary contact is removed from the account
   * that typed it.
   *
   * Deleting a pending signup is safe: it holds no data, and the per-destination
   * OTP limits live in OtpSend, so they survive re-registration.
   */
  private async findClaims(email?: string, phone?: string): Promise<User[]> {
    const or: Prisma.UserWhereInput[] = [];
    if (email) or.push({ email });
    if (phone) or.push({ phone });
    if (or.length === 0) return [];

    const holders = await this.prisma.user.findMany({ where: { OR: or } });
    for (const holder of holders) {
      if (email && holder.email === email && holder.emailVerifiedAt) {
        throw fieldError(409, 'EMAIL_TAKEN', 'email', 'This email already has an account. Try signing in.');
      }
      if (phone && holder.phone === phone && holder.phoneVerifiedAt) {
        throw fieldError(409, 'PHONE_TAKEN', 'phone', 'This number already has an account. Try signing in.');
      }
    }
    return holders;
  }

  private async releaseUnverifiedClaims(holders: User[], email?: string, phone?: string): Promise<void> {
    for (const holder of holders) {
      if (!holder.verifiedAt) {
        await this.prisma.user.delete({ where: { id: holder.id } });
      } else {
        await this.prisma.user.update({
          where: { id: holder.id },
          data: {
            ...(email && holder.email === email ? { email: null } : {}),
            ...(phone && holder.phone === phone ? { phone: null } : {}),
          },
        });
      }
    }
  }
}
