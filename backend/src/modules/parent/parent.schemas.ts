import { z } from 'zod';
import { ExamSettingsSchema, packageName, QUESTION_TYPES } from '../sessions/sessions.schemas.js';

export const ChildParams = z.object({ childId: z.string().min(1) });
export const IdParams = z.object({ id: z.string().min(1) });

export const OffsetQuery = z.object({
  /** The parent's phone offset from UTC, so "today" matches their calendar. */
  utcOffsetMinutes: z.coerce.number().int().min(-720).max(840).default(0),
});

export const CreateLockBody = z.object({
  title: z.string().trim().min(1, 'Give the lock a name.').max(60),
  subject: z.string().trim().min(1, 'Pick a subject.').max(60),
  topics: z.string().trim().min(2, 'Write what the exam should cover.').max(500),
  /** Package names, or ["*"] for the whole phone. */
  lockedApps: z
    .array(packageName)
    .min(1, 'Pick at least one app to lock.')
    .max(300)
    .transform((apps) => [...new Set(apps)]),
  strict: z.boolean().default(false),
  /** Use one of the parent's question sets instead of AI-written questions. */
  questionSetId: z.string().min(1).optional(),
  exam: ExamSettingsSchema,
});
export type CreateLockInput = z.infer<typeof CreateLockBody>;

const ParentQuestion = z
  .object({
    type: z.enum(QUESTION_TYPES),
    prompt: z.string().trim().min(3, 'Write the question.').max(500),
    options: z.array(z.string().trim().min(1, 'Fill in every choice.').max(200)).max(4).default([]),
    /** MCQ: index "0"–"3"; TRUE_FALSE: "true"/"false"; SHORT: the model answer. */
    answer: z.string().trim().min(1, 'Give the right answer.').max(300),
    /** SHORT: words a right answer must include. */
    keyPoints: z.array(z.string().trim().min(1).max(60)).max(6).default([]),
    explanation: z.string().trim().max(500).default(''),
  })
  .superRefine((q, ctx) => {
    if (q.type === 'MCQ') {
      const index = Number(q.answer);
      if (q.options.length !== 4 || new Set(q.options.map((o) => o.toLowerCase())).size !== 4) {
        ctx.addIssue({ code: 'custom', path: ['options'], message: 'Give four different choices.' });
      }
      if (!Number.isInteger(index) || index < 0 || index > 3) {
        ctx.addIssue({ code: 'custom', path: ['answer'], message: 'Mark which choice is right.' });
      }
    } else if (q.type === 'TRUE_FALSE' && q.answer !== 'true' && q.answer !== 'false') {
      ctx.addIssue({ code: 'custom', path: ['answer'], message: 'Choose true or false.' });
    }
  })
  .transform((q) => ({ ...q, options: q.type === 'MCQ' ? q.options : [] }));

export const QuestionSetBody = z.object({
  title: z.string().trim().min(1, 'Name the question set.').max(60),
  subject: z.string().trim().min(1, 'Pick a subject.').max(60),
  questions: z.array(ParentQuestion).min(3, 'Add at least 3 questions.').max(50),
});
export type QuestionSetInput = z.infer<typeof QuestionSetBody>;
