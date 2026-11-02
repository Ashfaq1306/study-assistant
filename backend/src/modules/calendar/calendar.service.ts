import type { CalendarEvent, PrismaClient, User } from '@prisma/client';
import { AppError, notFound } from '../../lib/errors.js';
import type { Clock } from '../../lib/clock.js';
import { looksLike } from '../photos/photos.service.js';
import { AiUnavailableError, type AiProvider, type ExtractedEvent } from '../ai/ai.types.js';
import type { ConfigService } from '../config/config.service.js';
import {
  DEFAULT_REMINDERS,
  MAX_IMPORT_BYTES,
  type CalendarKindName,
  type EventInput,
  type ImportInput,
} from './calendar.schemas.js';

/** Plenty for a full year of classes, exams and holidays. */
const MAX_EVENTS = 2000;
const MINUTE = 60_000;

export interface EventView {
  id: string;
  kind: CalendarKindName;
  title: string;
  subject: string;
  location: string;
  notes: string;
  startsAt: string;
  endsAt: string | null;
  allDay: boolean;
  weekly: boolean;
  repeatUntil: string | null;
  reminders: number[];
  source: string;
}

/** A proposed event read from an academic calendar, not saved yet. */
export type DraftEvent = Omit<EventView, 'id' | 'notes' | 'repeatUntil' | 'source'>;

export class CalendarService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly ai: AiProvider,
    private readonly config: ConfigService,
    private readonly clock: Clock,
  ) {}

  async list(userId: string): Promise<EventView[]> {
    const events = await this.prisma.calendarEvent.findMany({
      where: { userId },
      orderBy: { startsAt: 'asc' },
      take: MAX_EVENTS,
    });
    return events.map(view);
  }

  async create(user: User, input: EventInput, source = 'MANUAL'): Promise<EventView> {
    await this.assertRoom(user.id, 1);
    return view(await this.prisma.calendarEvent.create({ data: { userId: user.id, ...data(input), source } }));
  }

  async createMany(user: User, inputs: EventInput[]): Promise<EventView[]> {
    await this.assertRoom(user.id, inputs.length);
    // One transaction: an import lands whole or not at all.
    const created = await this.prisma.$transaction(
      inputs.map((input) => this.prisma.calendarEvent.create({ data: { userId: user.id, ...data(input), source: 'IMPORT' } })),
    );
    return created.map(view);
  }

  async update(user: User, id: string, input: EventInput): Promise<EventView> {
    await this.owned(user.id, id);
    return view(await this.prisma.calendarEvent.update({ where: { id }, data: data(input) }));
  }

  async remove(user: User, id: string): Promise<void> {
    const { count } = await this.prisma.calendarEvent.deleteMany({ where: { id, userId: user.id } });
    if (count === 0) throw notFound('Event not found.');
  }

  /** Reads an academic calendar or timetable with the AI. Nothing is saved: the student reviews first. */
  async import(user: User, input: ImportInput): Promise<DraftEvent[]> {
    const settings = await this.config.get();
    if (!settings.aiEnabled || this.ai.source !== 'AI') {
      throw new AppError(503, 'AI_OFF', 'Reading calendars needs the AI, which is switched off right now.');
    }
    let file: { mediaType: 'application/pdf' | 'image/jpeg' | 'image/png' | 'image/webp'; data: string } | undefined;
    if (input.file) {
      const bytes = Buffer.from(input.file.data, 'base64');
      const ok = bytes.length <= MAX_IMPORT_BYTES && (input.file.mime === 'application/pdf' ? isPdf(bytes) : looksLike(input.file.mime, bytes));
      if (!ok) throw new AppError(400, 'BAD_FILE', 'That file could not be read. Try a PDF or a clear photo.');
      file = { mediaType: input.file.mime, data: input.file.data };
    }

    const now = this.clock();
    const today = localDate(now, input.utcOffsetMinutes);
    let found: ExtractedEvent[];
    try {
      found = await this.ai.extractCalendar({ text: input.text, file, today });
    } catch (err) {
      if (err instanceof AiUnavailableError) throw new AppError(503, 'AI_UNAVAILABLE', err.message);
      throw err;
    }
    await this.prisma.aiUsage.create({ data: { userId: user.id, kind: 'CALENDAR', createdAt: now } });

    const drafts = found.flatMap((e) => toDraft(e, input.utcOffsetMinutes) ?? []).slice(0, 300);
    if (drafts.length === 0) {
      throw new AppError(422, 'NOTHING_FOUND', "No dates were found. Try a clearer photo, or paste the calendar's text.");
    }
    return drafts.sort((a, b) => a.startsAt.localeCompare(b.startsAt));
  }

  private async owned(userId: string, id: string): Promise<CalendarEvent> {
    const event = await this.prisma.calendarEvent.findUnique({ where: { id } });
    if (!event || event.userId !== userId) throw notFound('Event not found.');
    return event;
  }

  private async assertRoom(userId: string, adding: number): Promise<void> {
    const count = await this.prisma.calendarEvent.count({ where: { userId } });
    if (count + adding > MAX_EVENTS) {
      throw new AppError(409, 'CALENDAR_FULL', `Your calendar can hold ${MAX_EVENTS} items. Remove some old ones first.`);
    }
  }
}

function data(input: EventInput) {
  return {
    kind: input.kind,
    title: input.title,
    subject: input.subject,
    location: input.location,
    notes: input.notes,
    startsAt: input.startsAt,
    endsAt: input.endsAt ?? null,
    allDay: input.allDay,
    weekly: input.weekly,
    repeatUntil: input.repeatUntil ?? null,
    reminders: JSON.stringify(input.reminders),
  };
}

function view(e: CalendarEvent): EventView {
  return {
    id: e.id,
    kind: e.kind,
    title: e.title,
    subject: e.subject,
    location: e.location,
    notes: e.notes,
    startsAt: e.startsAt.toISOString(),
    endsAt: e.endsAt?.toISOString() ?? null,
    allDay: e.allDay,
    weekly: e.weekly,
    repeatUntil: e.repeatUntil?.toISOString() ?? null,
    reminders: JSON.parse(e.reminders) as number[],
    source: e.source,
  };
}

const isPdf = (bytes: Buffer) => bytes.subarray(0, 5).toString('latin1') === '%PDF-';

/** YYYY-MM-DD on the student's calendar. */
export function localDate(at: Date, utcOffsetMinutes: number): string {
  return new Date(at.getTime() + utcOffsetMinutes * MINUTE).toISOString().slice(0, 10);
}

/** A local date and time (as written in the calendar) to the real instant. */
export function localToInstant(date: string, time: string, utcOffsetMinutes: number): Date | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
  const hhmm = /^([01]?\d|2[0-3]):([0-5]\d)$/.exec(time);
  const [h, m] = hhmm ? [Number(hhmm[1]), Number(hhmm[2])] : [0, 0];
  const [y, mo, d] = date.split('-').map(Number) as [number, number, number];
  const utc = Date.UTC(y, mo - 1, d, h, m) - utcOffsetMinutes * MINUTE;
  const result = new Date(utc);
  // Reject impossible dates such as 2026-02-30 (Date would roll them over).
  return localDate(result, utcOffsetMinutes) === date ? result : null;
}

/** Turns what the AI read into an event the app can show and remind about. */
export function toDraft(e: ExtractedEvent, utcOffsetMinutes: number): DraftEvent | null {
  const title = e.title.trim().slice(0, 120);
  if (!title) return null;
  const allDay = !e.startTime;
  const startsAt = localToInstant(e.date, e.startTime, utcOffsetMinutes);
  if (!startsAt) return null;
  let endsAt: Date | null = null;
  if (e.endDate && e.endDate > e.date) {
    // Multi-day items (a holiday week) end at the end of their last day.
    endsAt = localToInstant(e.endDate, '23:59', utcOffsetMinutes);
  } else if (e.endTime) {
    endsAt = localToInstant(e.date, e.endTime, utcOffsetMinutes);
  }
  if (endsAt && endsAt < startsAt) endsAt = null;
  return {
    kind: e.kind,
    title,
    subject: e.subject.trim().slice(0, 80),
    location: e.location.trim().slice(0, 120),
    startsAt: startsAt.toISOString(),
    endsAt: endsAt?.toISOString() ?? null,
    allDay,
    weekly: e.kind === 'CLASS' && e.weekly,
    reminders: DEFAULT_REMINDERS[e.kind],
  };
}
