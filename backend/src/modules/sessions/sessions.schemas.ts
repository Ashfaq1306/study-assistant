import { z } from 'zod';

export const QUESTION_TYPES = ['MCQ', 'TRUE_FALSE', 'SHORT'] as const;
export type QuestionType = (typeof QUESTION_TYPES)[number];

/** Android package names, e.g. com.facebook.katana. "*" means the whole phone. */
export const packageName = z
  .string()
  .trim()
  .max(255)
  .regex(/^(\*|[a-zA-Z][\w]*(\.[\w]+)+)$/, 'Not a valid app.');

/**
 * How an exam is built and marked. Shared by study sessions and parent locks.
 * The pass mark floor (at least 50% of total marks) is checked by the service,
 * because an admin can raise it.
 */
export const ExamSettingsSchema = z
  .object({
    questionCount: z.number().int().min(3, 'Ask for at least 3 questions.').max(50),
    totalMarks: z.number().int().min(3).max(500),
    passMarks: z.number().int().min(1),
    questionTypes: z
      .array(z.enum(QUESTION_TYPES))
      .min(1, 'Pick at least one question type.')
      .transform((types) => [...new Set(types)]),
    difficulty: z.enum(['EASY', 'MEDIUM', 'HARD']).default('EASY'),
  })
  .superRefine((exam, ctx) => {
    if (exam.passMarks > exam.totalMarks) {
      ctx.addIssue({ code: 'custom', path: ['passMarks'], message: 'The pass mark cannot be more than the total.' });
    }
    if (exam.totalMarks < exam.questionCount) {
      ctx.addIssue({ code: 'custom', path: ['totalMarks'], message: 'Give each question at least 1 mark.' });
    }
  });
export type ExamSettings = z.infer<typeof ExamSettingsSchema>;

export const StartSessionBody = z.object({
  subject: z.string().trim().min(1, 'Pick a subject.').max(60),
  topics: z.string().trim().min(2, 'Write what you will study.').max(500),
  /** The student's plan or notes, in their own words. */
  notes: z.string().trim().max(1000).default(''),
  plannedMinutes: z.number().int(),
  lockedApps: z.array(packageName).max(300).default([]).transform((apps) => [...new Set(apps)]),
  strict: z.boolean().default(true),
  exam: ExamSettingsSchema,
});
export type StartSessionInput = z.infer<typeof StartSessionBody>;

export const SessionParams = z.object({ id: z.string().min(1) });

export const StatsQuery = z.object({
  /** The phone's offset from UTC, so "today" matches the student's calendar. */
  utcOffsetMinutes: z.coerce.number().int().min(-720).max(840).default(0),
});

export const ListQuery = z.object({ limit: z.coerce.number().int().min(1).max(100).default(20) });
