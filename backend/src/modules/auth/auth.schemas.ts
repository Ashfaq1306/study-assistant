import { z } from 'zod';
import { parseIsoDate } from '../../lib/age.js';
import { normalizePhone } from '../../lib/phone.js';

/** Clients often send "" for an empty field; treat it as absent. */
const blankToUndefined = (v: unknown) => (typeof v === 'string' && v.trim() === '' ? undefined : v);

export const emailSchema = z
  .string()
  .trim()
  .toLowerCase()
  .max(254)
  .pipe(z.email('Enter a valid email address.'));

export const phoneSchema = z.string().transform((value, ctx) => {
  const phone = normalizePhone(value);
  if (!phone) {
    ctx.addIssue({ code: 'custom', message: 'Enter a valid mobile number, e.g. 01712345678.' });
    return z.NEVER;
  }
  return phone;
});

export const passwordSchema = z
  .string()
  .min(8, 'Use at least 8 characters.')
  .max(128, 'Use at most 128 characters.')
  .regex(/[A-Za-z]/, 'Include at least one letter.')
  .regex(/\d/, 'Include at least one number.');

const otpCodeSchema = z.string().trim().regex(/^\d{6}$/, 'Enter the 6-digit code.');

export const RegisterBody = z
  .object({
    role: z.enum(['STUDENT', 'PARENT']),
    name: z.string().trim().min(2, 'Enter your name.').max(60),
    email: z.preprocess(blankToUndefined, emailSchema.optional()),
    phone: z.preprocess(blankToUndefined, phoneSchema.optional()),
    password: passwordSchema,
    dateOfBirth: z.string().transform((value, ctx) => {
      const date = parseIsoDate(value);
      if (!date) {
        ctx.addIssue({ code: 'custom', message: 'Enter your date of birth.' });
        return z.NEVER;
      }
      return date;
    }),
    otpChannel: z.enum(['EMAIL', 'SMS']),
  })
  .superRefine((body, ctx) => {
    if (body.otpChannel === 'EMAIL' && !body.email) {
      ctx.addIssue({ code: 'custom', path: ['email'], message: 'Enter your email to get the code there.' });
    }
    if (body.otpChannel === 'SMS' && !body.phone) {
      ctx.addIssue({ code: 'custom', path: ['phone'], message: 'Enter your mobile number to get the code by SMS.' });
    }
  });
export type RegisterInput = z.infer<typeof RegisterBody>;

export const VerifyAccountBody = z.object({ userId: z.string().min(1), code: otpCodeSchema });

export const ResendVerificationBody = z.object({
  userId: z.string().min(1),
  channel: z.enum(['EMAIL', 'SMS']).optional(),
});

export const LoginBody = z.object({
  identifier: z.string().trim().min(1, 'Enter your email or mobile number.').max(254),
  password: z.string().min(1, 'Enter your password.').max(128),
});

export const ForgotPasswordBody = z.object({ identifier: z.string().trim().min(1).max(254) });

export const ResetPasswordBody = z.object({
  identifier: z.string().trim().min(1).max(254),
  code: otpCodeSchema,
  newPassword: passwordSchema,
});

export const RefreshBody = z.object({ refreshToken: z.string().min(20).max(200) });
