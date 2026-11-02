import { z } from 'zod';

export const CALENDAR_KINDS = ['EXAM', 'CLASS', 'ASSIGNMENT', 'HOLIDAY', 'EVENT'] as const;
export type CalendarKindName = (typeof CALENDAR_KINDS)[number];

/** Sensible reminders when the student doesn't choose (minutes before the start). */
export const DEFAULT_REMINDERS: Record<CalendarKindName, number[]> = {
  EXAM: [1440, 60],
  CLASS: [15],
  ASSIGNMENT: [1440],
  HOLIDAY: [],
  EVENT: [60],
};

const instant = z.iso.datetime({ offset: true, message: 'Use a full date and time.' }).transform((v) => new Date(v));

export const EventBody = z
  .object({
    kind: z.enum(CALENDAR_KINDS),
    title: z.string().trim().min(1, 'Give it a name.').max(120),
    subject: z.string().trim().max(80).default(''),
    location: z.string().trim().max(120).default(''),
    notes: z.string().trim().max(1000).default(''),
    startsAt: instant,
    endsAt: instant.nullish(),
    allDay: z.boolean().default(false),
    weekly: z.boolean().default(false),
    repeatUntil: instant.nullish(),
    /** Minutes before the start; up to 30 days ahead. */
    reminders: z
      .array(z.number().int().min(0).max(43_200))
      .max(5)
      .transform((r) => [...new Set(r)].sort((a, b) => b - a))
      .optional(),
  })
  .superRefine((e, ctx) => {
    if (e.endsAt && e.endsAt < e.startsAt) {
      ctx.addIssue({ code: 'custom', path: ['endsAt'], message: 'The end must be after the start.' });
    }
    if (e.repeatUntil && e.repeatUntil < e.startsAt) {
      ctx.addIssue({ code: 'custom', path: ['repeatUntil'], message: 'Repeat until a later date.' });
    }
  })
  .transform((e) => ({ ...e, reminders: e.reminders ?? DEFAULT_REMINDERS[e.kind] }));
export type EventInput = z.infer<typeof EventBody>;

export const BulkBody = z.object({ events: z.array(EventBody).min(1).max(300) });

export const IdParams = z.object({ id: z.string().min(1) });

/** The PDF or photo of a calendar can be a few pages: up to 8 MB. */
export const MAX_IMPORT_BYTES = 8_000_000;
export const IMPORT_BODY_LIMIT = 11_000_000;

export const ImportBody = z
  .object({
    text: z.string().trim().max(20_000).optional(),
    file: z
      .object({
        mime: z.enum(['application/pdf', 'image/jpeg', 'image/png', 'image/webp']),
        data: z.string().min(100).max(Math.ceil((MAX_IMPORT_BYTES * 4) / 3) + 4),
      })
      .optional(),
    /** The phone's offset from UTC, so dates and times land on the right local moment. */
    utcOffsetMinutes: z.number().int().min(-720).max(840).default(0),
  })
  .refine((b) => (b.text?.length ?? 0) > 0 || b.file, 'Add a file or paste the calendar text.');
export type ImportInput = z.infer<typeof ImportBody>;
