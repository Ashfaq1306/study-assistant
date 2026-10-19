import type { OtpChannel, OtpPurpose, PrismaClient, User } from '@prisma/client';
import type { FastifyBaseLogger } from 'fastify';
import { AppError } from '../../lib/errors.js';
import { generateOtp, hmac, safeEqual } from '../../lib/crypto.js';
import { maskEmail, maskPhone } from '../../lib/phone.js';
import type { Notifier, OutboundMessage } from '../notify/notifier.js';
import type { Clock } from '../../lib/clock.js';

export const OTP_TTL_MS = 10 * 60_000;
export const OTP_RESEND_COOLDOWN_MS = 60_000;
export const OTP_MAX_ATTEMPTS = 5;
/** Codes per destination (email address or phone number) per hour, across all accounts. */
export const OTP_MAX_PER_HOUR = 5;

export interface OtpIssued {
  channel: OtpChannel;
  destination: string;
  expiresAt: string;
  resendAvailableAt: string;
  /** Development only: the code itself, so testing needs no email or SMS. */
  devCode?: string;
}

type Recipient = Pick<User, 'id' | 'name' | 'email' | 'phone'>;

export class OtpService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly notifier: Notifier,
    private readonly secret: string,
    private readonly clock: Clock,
    private readonly log: FastifyBaseLogger,
    /** Never true in production: see buildApp. */
    private readonly exposeDevCodes = false,
  ) {}

  /** Sends a fresh code, invalidating any earlier unused code for the same purpose. */
  async issue(user: Recipient, purpose: OtpPurpose, channel: OtpChannel): Promise<OtpIssued> {
    const to = channel === 'EMAIL' ? user.email : user.phone;
    if (!to) {
      throw new AppError(
        400,
        'OTP_CHANNEL_UNAVAILABLE',
        `This account has no ${channel === 'EMAIL' ? 'email' : 'phone number'}.`,
      );
    }

    const now = this.clock();
    const destinationHash = await this.assertCanSend(to);

    const code = generateOtp();
    const expiresAt = new Date(now.getTime() + OTP_TTL_MS);
    const [, created, send] = await this.prisma.$transaction([
      this.prisma.otpCode.updateMany({
        where: { userId: user.id, purpose, consumedAt: null },
        data: { consumedAt: now },
      }),
      this.prisma.otpCode.create({
        data: {
          userId: user.id,
          purpose,
          channel,
          codeHash: this.hash(user.id, purpose, code),
          expiresAt,
          createdAt: now,
        },
      }),
      this.prisma.otpSend.create({ data: { destinationHash, createdAt: now } }),
    ]);

    try {
      await this.notifier.send(buildMessage(channel, to, user.name, code, purpose));
    } catch (err) {
      // Nothing was delivered, so it should not count against the limits.
      await this.prisma.$transaction([
        this.prisma.otpCode.delete({ where: { id: created.id } }),
        this.prisma.otpSend.delete({ where: { id: send.id } }),
      ]);
      this.log.error({ err, channel }, 'OTP delivery failed');
      throw new AppError(502, 'OTP_DELIVERY_FAILED', 'We could not send your code. Please try again.');
    }

    return {
      channel,
      destination: channel === 'EMAIL' ? maskEmail(to) : maskPhone(to),
      expiresAt: expiresAt.toISOString(),
      resendAvailableAt: new Date(now.getTime() + OTP_RESEND_COOLDOWN_MS).toISOString(),
      ...(this.exposeDevCodes ? { devCode: code } : {}),
    };
  }

  /**
   * Throws if another code may not be sent to this email or phone yet.
   * Limits are per destination, so nobody can flood one phone or inbox by
   * creating, abandoning and re-creating signups. Returns the destination key.
   */
  async assertCanSend(to: string): Promise<string> {
    const now = this.clock();
    const destinationHash = hmac(this.secret, `destination:${to}`);
    const recent = await this.prisma.otpSend.findMany({
      where: { destinationHash, createdAt: { gte: new Date(now.getTime() - 3_600_000) } },
      orderBy: { createdAt: 'desc' },
      select: { createdAt: true },
    });
    const last = recent[0];
    if (last && now.getTime() - last.createdAt.getTime() < OTP_RESEND_COOLDOWN_MS) {
      const retryAt = new Date(last.createdAt.getTime() + OTP_RESEND_COOLDOWN_MS);
      throw new AppError(429, 'OTP_RESEND_TOO_SOON', 'Please wait a moment before asking for another code.', {
        resendAvailableAt: retryAt.toISOString(),
      });
    }
    if (recent.length >= OTP_MAX_PER_HOUR) {
      throw new AppError(429, 'OTP_LIMIT_REACHED', 'Too many codes requested. Please try again in an hour.');
    }

    return destinationHash;
  }

  /**
   * Consumes the latest code if it matches and returns the channel it was
   * sent on, which proves the user controls that email or phone.
   */
  async verify(userId: string, purpose: OtpPurpose, code: string): Promise<OtpChannel> {
    const now = this.clock();
    const otp = await this.prisma.otpCode.findFirst({
      where: { userId, purpose, consumedAt: null },
      orderBy: { createdAt: 'desc' },
    });
    if (!otp || otp.expiresAt <= now) {
      throw new AppError(400, 'OTP_EXPIRED', 'This code has expired. Please ask for a new one.');
    }

    // Claim an attempt atomically *before* comparing, so a burst of parallel
    // guesses cannot get more than OTP_MAX_ATTEMPTS tries.
    const claimed = await this.prisma.otpCode.updateMany({
      where: { id: otp.id, consumedAt: null, attempts: { lt: OTP_MAX_ATTEMPTS } },
      data: { attempts: { increment: 1 } },
    });
    if (claimed.count === 0) {
      throw new AppError(429, 'OTP_TOO_MANY_ATTEMPTS', 'Too many wrong codes. Please ask for a new one.');
    }

    if (!safeEqual(otp.codeHash, this.hash(userId, purpose, code))) {
      const current = await this.prisma.otpCode.findUnique({ where: { id: otp.id }, select: { attempts: true } });
      throw new AppError(400, 'OTP_INVALID', 'That code is not right.', {
        attemptsLeft: Math.max(0, OTP_MAX_ATTEMPTS - (current?.attempts ?? OTP_MAX_ATTEMPTS)),
      });
    }

    // Conditional update so two concurrent requests cannot both use one code.
    const { count } = await this.prisma.otpCode.updateMany({
      where: { id: otp.id, consumedAt: null },
      data: { consumedAt: now },
    });
    if (count === 0) {
      throw new AppError(400, 'OTP_EXPIRED', 'This code has already been used. Please ask for a new one.');
    }
    return otp.channel;
  }

  private hash(userId: string, purpose: OtpPurpose, code: string): string {
    return hmac(this.secret, `${userId}:${purpose}:${code}`);
  }
}

function buildMessage(
  channel: OtpChannel,
  to: string,
  name: string,
  code: string,
  purpose: OtpPurpose,
): OutboundMessage {
  const action = purpose === 'VERIFY_ACCOUNT' ? 'open your account' : 'reset your password';
  const minutes = OTP_TTL_MS / 60_000;
  const text = `${code} is your Study Assistant code to ${action}. It expires in ${minutes} minutes. Never share it with anyone.`;
  if (channel === 'SMS') return { channel, to, text };
  return {
    channel,
    to,
    subject: `${code} is your Study Assistant code`,
    text: `Hi ${name},\n\n${text}\n\nIf you did not ask for this, you can ignore this email.`,
    html: `<div style="font-family:system-ui,sans-serif;max-width:420px;margin:auto;padding:24px">
<h2 style="color:#6c5ce7;margin:0 0 12px">Study Assistant</h2>
<p>Hi ${escapeHtml(name)},</p>
<p>Use this code to ${action}:</p>
<p style="font-size:32px;letter-spacing:8px;font-weight:800;margin:16px 0">${code}</p>
<p style="color:#666">It expires in ${minutes} minutes. Never share it with anyone.</p>
</div>`,
  };
}

const escapeHtml = (s: string): string => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
