import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import type { AiProvider, CalendarSource, ExtractedEvent } from '../src/modules/ai/ai.types.js';
import { localToInstant, toDraft } from '../src/modules/calendar/calendar.service.js';
import { bearer, createTestApp, DOB, prisma, resetDatabase, signUp, type SignedInAccount, type TestContext } from './helpers.js';

/** Returns whatever the test sets, and remembers what it was asked. */
class CalendarAi implements AiProvider {
  readonly source = 'AI' as const;
  events: ExtractedEvent[] = [];
  last: CalendarSource | null = null;
  generateExam() {
    return Promise.resolve([]);
  }
  gradeShortAnswers() {
    return Promise.resolve([]);
  }
  tutor() {
    return Promise.resolve('');
  }
  extractCalendar(source: CalendarSource) {
    this.last = source;
    return Promise.resolve(this.events);
  }
}

const ev = (over: Partial<ExtractedEvent>): ExtractedEvent => ({
  kind: 'EXAM',
  title: 'Physics midterm',
  subject: 'Physics',
  date: '2026-07-10',
  endDate: '',
  startTime: '10:00',
  endTime: '12:00',
  weekly: false,
  location: 'Hall 2',
  ...over,
});

let ctx: TestContext;
let ai: CalendarAi;
let student: SignedInAccount;

const as = (account: SignedInAccount) => ({
  get: (url: string) => ctx.app.inject({ method: 'GET', url, headers: bearer(account.accessToken) }),
  post: (url: string, payload: object = {}) =>
    ctx.app.inject({ method: 'POST', url, payload, headers: bearer(account.accessToken) }),
  put: (url: string, payload: object) => ctx.app.inject({ method: 'PUT', url, payload, headers: bearer(account.accessToken) }),
  delete: (url: string) => ctx.app.inject({ method: 'DELETE', url, headers: bearer(account.accessToken) }),
});

beforeEach(async () => {
  await resetDatabase();
  ai = new CalendarAi();
  ctx = await createTestApp({ ai });
  student = await signUp(ctx, { dateOfBirth: DOB.student16 });
});

afterAll(async () => {
  await prisma.$disconnect();
});

describe('calendar', () => {
  it('adds exams and weekly classes with sensible default reminders', async () => {
    const exam = await as(student).post('/v1/calendar', {
      kind: 'EXAM',
      title: 'Chemistry final',
      startsAt: '2026-06-20T04:00:00.000Z',
      endsAt: '2026-06-20T07:00:00.000Z',
    });
    expect(exam.statusCode).toBe(201);
    expect(exam.json()).toMatchObject({ kind: 'EXAM', reminders: [1440, 60], weekly: false, source: 'MANUAL' });

    const cls = await as(student).post('/v1/calendar', {
      kind: 'CLASS',
      title: 'Maths',
      startsAt: '2026-06-02T02:00:00.000Z',
      weekly: true,
      reminders: [5, 15, 15],
    });
    expect(cls.json()).toMatchObject({ weekly: true, reminders: [15, 5] });

    const list = (await as(student).get('/v1/calendar')).json().events;
    expect(list.map((e: { title: string }) => e.title)).toEqual(['Maths', 'Chemistry final']);
  });

  it('validates, and keeps each calendar private', async () => {
    const bad = await as(student).post('/v1/calendar', {
      kind: 'EXAM',
      title: '',
      startsAt: '2026-06-20T04:00:00.000Z',
      endsAt: '2026-06-19T04:00:00.000Z',
    });
    expect(bad.statusCode).toBe(400);
    expect(Object.keys(bad.json().error.details.fields)).toEqual(expect.arrayContaining(['title', 'endsAt']));

    const mine = (await as(student).post('/v1/calendar', { kind: 'EVENT', title: 'Sports day', startsAt: '2026-06-20T04:00:00Z' })).json();
    const other = await signUp(ctx, { dateOfBirth: DOB.student16 });
    expect((await as(other).get('/v1/calendar')).json().events).toEqual([]);
    expect((await as(other).delete(`/v1/calendar/${mine.id}`)).statusCode).toBe(404);
    expect((await as(other).put(`/v1/calendar/${mine.id}`, { kind: 'EVENT', title: 'x', startsAt: '2026-06-20T04:00:00Z' })).statusCode).toBe(404);

    const edited = await as(student).put(`/v1/calendar/${mine.id}`, { kind: 'HOLIDAY', title: 'Sports day off', startsAt: '2026-06-20T00:00:00Z', allDay: true });
    expect(edited.json()).toMatchObject({ kind: 'HOLIDAY', allDay: true, reminders: [] });
    expect((await as(student).delete(`/v1/calendar/${mine.id}`)).statusCode).toBe(204);
  });

  it('saves a reviewed import in one go', async () => {
    const res = await as(student).post('/v1/calendar/bulk', {
      events: [
        { kind: 'HOLIDAY', title: 'Eid break', startsAt: '2026-06-25T00:00:00Z', allDay: true },
        { kind: 'EXAM', title: 'Biology test', startsAt: '2026-06-28T04:00:00Z' },
      ],
    });
    expect(res.statusCode).toBe(201);
    expect(res.json().events.every((e: { source: string }) => e.source === 'IMPORT')).toBe(true);
  });
});

describe('importing an academic calendar', () => {
  it('reads pasted text into reviewable events on the local calendar', async () => {
    ai.events = [
      ev({}),
      ev({ kind: 'HOLIDAY', title: 'ঈদের ছুটি', subject: '', date: '2026-06-25', endDate: '2026-06-30', startTime: '', endTime: '' }),
      ev({ kind: 'CLASS', title: 'Maths', date: '2026-06-02', startTime: '08:00', endTime: '08:45', weekly: true }),
      ev({ title: 'Broken', date: '2026-02-30' }),
    ];
    const res = await as(student).post('/v1/calendar/import', { text: 'Term 2 calendar …', utcOffsetMinutes: 360 });
    expect(res.statusCode).toBe(200);
    const events = res.json().events;
    expect(events).toHaveLength(3);
    // Sorted by start; local Dhaka times (UTC+6) become the right instants.
    expect(events[0]).toMatchObject({ kind: 'CLASS', weekly: true, startsAt: '2026-06-02T02:00:00.000Z', reminders: [15] });
    expect(events[1]).toMatchObject({ kind: 'HOLIDAY', title: 'ঈদের ছুটি', allDay: true, startsAt: '2026-06-24T18:00:00.000Z' });
    expect(events[1].endsAt).toBe('2026-06-30T17:59:00.000Z');
    expect(events[2]).toMatchObject({ kind: 'EXAM', startsAt: '2026-07-10T04:00:00.000Z', endsAt: '2026-07-10T06:00:00.000Z' });
    // Nothing is saved until the student confirms.
    expect((await as(student).get('/v1/calendar')).json().events).toEqual([]);
    expect(ai.last?.today).toBe('2026-06-01');
    expect(await prisma.aiUsage.count({ where: { kind: 'CALENDAR' } })).toBe(1);
  });

  it('refuses files that are not what they claim, and says when nothing was found', async () => {
    const fake = await as(student).post('/v1/calendar/import', {
      file: { mime: 'application/pdf', data: Buffer.alloc(200, 65).toString('base64') },
    });
    expect(fake.json().error.code).toBe('BAD_FILE');

    const pdf = Buffer.concat([Buffer.from('%PDF-1.7\n'), Buffer.alloc(200, 32)]).toString('base64');
    const empty = await as(student).post('/v1/calendar/import', { file: { mime: 'application/pdf', data: pdf } });
    expect(empty.json().error.code).toBe('NOTHING_FOUND');
    expect(ai.last?.file?.mediaType).toBe('application/pdf');

    expect((await as(student).post('/v1/calendar/import', {})).statusCode).toBe(400);
  });

  it('says so when the AI is off', async () => {
    await prisma.appSetting.create({ data: { key: 'aiEnabled', value: 'false' } });
    expect((await as(student).post('/v1/calendar/import', { text: 'x' })).json().error.code).toBe('AI_OFF');
  });
});

describe('date helpers', () => {
  it('converts local dates and times, and rejects impossible dates', () => {
    expect(localToInstant('2026-01-31', '23:30', 360)?.toISOString()).toBe('2026-01-31T17:30:00.000Z');
    expect(localToInstant('2026-02-30', '', 0)).toBeNull();
    expect(localToInstant('31/01/2026', '', 0)).toBeNull();
    expect(toDraft(ev({ title: '   ' }), 0)).toBeNull();
    expect(toDraft(ev({ endTime: '09:00' }), 0)?.endsAt).toBeNull();
  });
});
