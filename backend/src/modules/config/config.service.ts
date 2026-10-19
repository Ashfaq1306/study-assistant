import type { PrismaClient } from '@prisma/client';
import { z } from 'zod';
import type { Clock } from '../../lib/clock.js';
import { AppError } from '../../lib/errors.js';

/** The pass mark can be raised by an admin, never lowered below this. */
export const PASS_PERCENT_FLOOR = 50;

const DEFAULT_SUBJECTS = [
  'Mathematics',
  'Science',
  'English',
  'Bangla',
  'Physics',
  'Chemistry',
  'Biology',
  'ICT',
  'History',
  'Geography',
  'General Knowledge',
];

/**
 * Every setting an admin can change, with its default and its bounds. Values
 * that fail validation fall back to the default, so a bad edit cannot break
 * the app.
 */
export const SettingsSchema = z.object({
  subjects: z.array(z.string().trim().min(1).max(40)).min(1).max(50).default(DEFAULT_SUBJECTS),
  minPassPercent: z.number().int().min(PASS_PERCENT_FLOOR).max(100).default(PASS_PERCENT_FLOOR),
  minStudyMinutes: z.number().int().min(1).max(60).default(5),
  maxStudyMinutes: z.number().int().min(10).max(600).default(240),
  /** Share of the planned time after which "finish early" unlocks the exam. */
  earlyFinishPercent: z.number().int().min(0).max(100).default(50),
  maxQuestions: z.number().int().min(3).max(50).default(30),
  /** 0 = a failed student can try again straight away (with fresh questions). */
  examRetryCooldownSeconds: z.number().int().min(0).max(3600).default(0),
  tutorDailyLimit: z.number().int().min(0).max(1000).default(60),
  aiEnabled: z.boolean().default(true),
  /** Shown as a banner in the app when set. */
  announcement: z.string().trim().max(280).nullable().default(null),
});

export type Settings = z.infer<typeof SettingsSchema>;
export type SettingKey = keyof Settings;

const CACHE_MS = 15_000;

export class ConfigService {
  private cache?: { at: number; value: Settings };

  constructor(
    private readonly prisma: PrismaClient,
    private readonly clock: Clock,
  ) {}

  async get(): Promise<Settings> {
    const now = this.clock().getTime();
    if (this.cache && now - this.cache.at < CACHE_MS) return this.cache.value;

    const rows = await this.prisma.appSetting.findMany();
    const raw: Record<string, unknown> = {};
    for (const row of rows) {
      try {
        raw[row.key] = JSON.parse(row.value);
      } catch {
        // Ignore a corrupt row; the default applies.
      }
    }
    const value = SettingsSchema.parse(this.dropInvalid(raw));
    // A crossed pair would make every session impossible: fall back to defaults.
    if (value.minStudyMinutes > value.maxStudyMinutes) {
      const defaults = SettingsSchema.parse({});
      value.minStudyMinutes = defaults.minStudyMinutes;
      value.maxStudyMinutes = defaults.maxStudyMinutes;
    }
    this.cache = { at: now, value };
    return value;
  }

  /** Validates and stores a partial update. Returns the full new settings. */
  async update(patch: Partial<Settings>): Promise<Settings> {
    const valid = SettingsSchema.partial().parse(patch);
    const current = await this.get();
    const min = valid.minStudyMinutes ?? current.minStudyMinutes;
    const max = valid.maxStudyMinutes ?? current.maxStudyMinutes;
    if (min > max) {
      throw new AppError(400, 'VALIDATION_FAILED', 'Minimum study time must not exceed the maximum.', {
        fields: { minStudyMinutes: ['Must be at most the maximum study time.'] },
      });
    }
    await this.prisma.$transaction(
      Object.entries(valid).map(([key, value]) =>
        this.prisma.appSetting.upsert({
          where: { key },
          create: { key, value: JSON.stringify(value) },
          update: { value: JSON.stringify(value) },
        }),
      ),
    );
    this.cache = undefined;
    return this.get();
  }

  /** Keeps only the keys whose stored value is still valid on its own. */
  private dropInvalid(raw: Record<string, unknown>): Record<string, unknown> {
    const shape = SettingsSchema.shape;
    const out: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(raw)) {
      const field = shape[key as SettingKey];
      if (field && field.safeParse(value).success) out[key] = value;
    }
    return out;
  }
}
