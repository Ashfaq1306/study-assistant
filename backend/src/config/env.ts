import { z } from 'zod';

/** Treats empty strings (e.g. `SMTP_HOST=` in .env) as "not set". */
const optional = z
  .string()
  .trim()
  .optional()
  .transform((v) => (v ? v : undefined));

const EnvSchema = z
  .object({
    // Safe by default: a deploy that forgets NODE_ENV must not print OTPs to the log.
    NODE_ENV: z.enum(['development', 'test', 'production']).default('production'),
    PORT: z.coerce.number().int().min(1).max(65535).default(8080),
    HOST: z.string().default('0.0.0.0'),
    /**
     * Which X-Forwarded-For hops to trust for the client IP (rate limits use it).
     * false (default) = connect directly; a number = proxies in front; or a
     * comma-separated list of proxy IPs/CIDRs. Never use true behind the internet.
     */
    TRUST_PROXY: z
      .string()
      .default('false')
      .transform((v): boolean | number | string => {
        const value = v.trim();
        if (value === '' || value === 'false') return false;
        if (/^\d+$/.test(value)) return Number(value);
        return value;
      }),
    LOG_LEVEL: z
      .enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent'])
      .default('info'),
    DATABASE_URL: z.string().min(1),
    JWT_SECRET: z.string().min(32, 'JWT_SECRET must be at least 32 characters'),
    OTP_SECRET: z.string().min(32, 'OTP_SECRET must be at least 32 characters'),
    /**
     * Return one-time codes in API responses so the app can be tested without
     * email or SMS. Local development only: refused in production.
     */
    EXPOSE_DEV_CODES: z
      .enum(['true', 'false'])
      .default('false')
      .transform((v) => v === 'true'),
    CORS_ORIGINS: z
      .string()
      .default('')
      .transform((s) =>
        s
          .split(',')
          .map((o) => o.trim())
          .filter(Boolean),
      ),
    EMAIL_PROVIDER: z.enum(['console', 'smtp']).default('console'),
    SMTP_HOST: optional,
    SMTP_PORT: z.coerce.number().int().default(587),
    SMTP_USER: optional,
    SMTP_PASS: optional,
    SMTP_FROM: z.string().default('Study Assistant <no-reply@example.com>'),
    SMS_PROVIDER: z.enum(['console', 'twilio']).default('console'),
    /** Claude API key for AI exams and the study helper. Unset = built-in practice questions. */
    /** auto: Claude if ANTHROPIC_API_KEY is set, else Gemini if GEMINI_API_KEY is set, else practice questions. */
    AI_PROVIDER: z.enum(['auto', 'anthropic', 'gemini']).default('auto'),
    ANTHROPIC_API_KEY: optional,
    GEMINI_API_KEY: optional,
    GEMINI_MODEL: z.string().default('gemini-3.5-flash'),
    /** Tried in order when the main model is overloaded or retired. */
    GEMINI_FALLBACK_MODELS: z
      .string()
      .default('gemini-3.5-flash-lite,gemini-flash-lite-latest')
      .transform((v) => v.split(',').map((m) => m.trim()).filter(Boolean)),
    AI_MODEL: z.string().default('claude-opus-5-5'),
    AI_EXAM_EFFORT: z.enum(['low', 'medium', 'high', 'xhigh', 'max']).default('medium'),
    AI_TUTOR_EFFORT: z.enum(['low', 'medium', 'high', 'xhigh', 'max']).default('low'),
    TWILIO_ACCOUNT_SID: optional,
    TWILIO_AUTH_TOKEN: optional,
    TWILIO_FROM: optional,
  })
  .superRefine((env, ctx) => {
    if (
      env.NODE_ENV === 'production' &&
      (env.EMAIL_PROVIDER === 'console' || env.SMS_PROVIDER === 'console')
    ) {
      ctx.addIssue({
        code: 'custom',
        message: 'console OTP providers are not allowed in production',
        path: ['EMAIL_PROVIDER'],
      });
    }
    if (env.NODE_ENV === 'production' && env.EXPOSE_DEV_CODES) {
      ctx.addIssue({ code: 'custom', message: 'EXPOSE_DEV_CODES is not allowed in production', path: ['EXPOSE_DEV_CODES'] });
    }
    if (env.EMAIL_PROVIDER === 'smtp' && !env.SMTP_HOST) {
      ctx.addIssue({ code: 'custom', message: 'SMTP_HOST is required', path: ['SMTP_HOST'] });
    }
    if (
      env.SMS_PROVIDER === 'twilio' &&
      !(env.TWILIO_ACCOUNT_SID && env.TWILIO_AUTH_TOKEN && env.TWILIO_FROM)
    ) {
      ctx.addIssue({
        code: 'custom',
        message: 'TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN and TWILIO_FROM are required',
        path: ['SMS_PROVIDER'],
      });
    }
  });

export type Env = z.infer<typeof EnvSchema>;

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const result = EnvSchema.safeParse(source);
  if (!result.success) {
    throw new Error(`Invalid environment:\n${z.prettifyError(result.error)}`);
  }
  return result.data;
}
