import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import type { AiProvider, ExamSpec, GeneratedQuestion } from '../src/modules/ai/ai.types.js';
import { bearer, createTestApp, DOB, prisma, resetDatabase, signUp, type SignedInAccount, type TestContext } from './helpers.js';

/** Remembers what it was asked, so we can see the photos reach the exam writer. */
class RecordingAi implements AiProvider {
  readonly source = 'AI' as const;
  lastSpec: ExamSpec | null = null;
  generateExam(spec: ExamSpec): Promise<GeneratedQuestion[]> {
    this.lastSpec = spec;
    return Promise.resolve(
      Array.from({ length: spec.count }, (_, i) => ({
        type: 'MCQ' as const,
        prompt: `From the page: Q${i}?`,
        options: ['A', 'B', 'C', 'D'],
        answer: '0',
        keyPoints: [],
        explanation: '',
      })),
    );
  }
  gradeShortAnswers() {
    return Promise.resolve([]);
  }
  tutor() {
    return Promise.resolve('Hi');
  }
}

// A tiny but real-looking JPEG header and body.
const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(300, 7)]).toString('base64');
const NOT_AN_IMAGE = Buffer.alloc(300, 65).toString('base64');

let ctx: TestContext;
let ai: RecordingAi;
let student: SignedInAccount;
const MIN = 60_000;

const as = (account: SignedInAccount) => ({
  get: (url: string) => ctx.app.inject({ method: 'GET', url, headers: bearer(account.accessToken) }),
  post: (url: string, payload: object = {}) =>
    ctx.app.inject({ method: 'POST', url, payload, headers: bearer(account.accessToken) }),
  delete: (url: string) => ctx.app.inject({ method: 'DELETE', url, headers: bearer(account.accessToken) }),
});

const startSession = async (over: Record<string, unknown> = {}) => {
  const res = await as(student).post('/v1/sessions', {
    subject: 'Science',
    topics: 'The water cycle',
    notes: 'Read pages 12-14, then draw the cycle.',
    plannedMinutes: 10,
    lockedApps: [],
    exam: { questionCount: 3, totalMarks: 6, passMarks: 3, questionTypes: ['MCQ'] },
    ...over,
  });
  expect(res.statusCode).toBe(201);
  return res.json<{ id: string; notes: string; photoIds: string[]; exam: { difficulty: string } }>();
};

beforeEach(async () => {
  await resetDatabase();
  ai = new RecordingAi();
  ctx = await createTestApp({ ai });
  student = await signUp(ctx, { dateOfBirth: DOB.student16 });
});

afterAll(async () => {
  await prisma.$disconnect();
});

describe('study photos and notes', () => {
  it('keeps the plan, defaults to easy questions, and sends notes and photos to the exam writer', async () => {
    const session = await startSession();
    expect(session).toMatchObject({ notes: 'Read pages 12-14, then draw the cycle.', photoIds: [] });
    expect(session.exam.difficulty).toBe('EASY');

    const added = await as(student).post(`/v1/sessions/${session.id}/photos`, { mime: 'image/jpeg', data: JPEG });
    expect(added.statusCode).toBe(201);
    expect((await as(student).get('/v1/sessions/active')).json().session.photoIds).toEqual([added.json().id]);

    const image = await as(student).get(`/v1/photos/${added.json().id}`);
    expect(image.headers['content-type']).toBe('image/jpeg');
    expect(image.rawPayload.subarray(0, 3)).toEqual(Buffer.from([0xff, 0xd8, 0xff]));

    ctx.clock.advance(11 * MIN);
    await as(student).post(`/v1/sessions/${session.id}/exam`);
    expect(ai.lastSpec).toMatchObject({ notes: 'Read pages 12-14, then draw the cycle.', difficulty: 'EASY' });
    expect(ai.lastSpec!.images).toEqual([{ mediaType: 'image/jpeg', data: JPEG }]);
  });

  it('refuses files that are not the image they claim, and more than 4 photos', async () => {
    const { id } = await startSession();
    const bad = await as(student).post(`/v1/sessions/${id}/photos`, { mime: 'image/jpeg', data: NOT_AN_IMAGE });
    expect(bad.json().error.code).toBe('BAD_PHOTO');

    for (let i = 0; i < 4; i++) {
      expect((await as(student).post(`/v1/sessions/${id}/photos`, { mime: 'image/jpeg', data: JPEG })).statusCode).toBe(201);
    }
    const fifth = await as(student).post(`/v1/sessions/${id}/photos`, { mime: 'image/jpeg', data: JPEG });
    expect(fifth.json().error.code).toBe('TOO_MANY_PHOTOS');
  });

  it('a photo can be removed while studying, but not added once the exam is due', async () => {
    const { id } = await startSession();
    const photo = (await as(student).post(`/v1/sessions/${id}/photos`, { mime: 'image/jpeg', data: JPEG })).json();
    expect((await as(student).delete(`/v1/sessions/${id}/photos/${photo.id}`)).json().photoIds).toEqual([]);

    ctx.clock.advance(11 * MIN);
    await as(student).get('/v1/sessions/active'); // the timer runs out
    const late = await as(student).post(`/v1/sessions/${id}/photos`, { mime: 'image/jpeg', data: JPEG });
    expect(late.json().error.code).toBe('SESSION_NOT_STUDYING');
  });

  it('linked parents can see the photos; nobody else can', async () => {
    const { id } = await startSession();
    const photo = (await as(student).post(`/v1/sessions/${id}/photos`, { mime: 'image/jpeg', data: JPEG })).json();

    const parent = await signUp(ctx, { role: 'PARENT', dateOfBirth: DOB.parent });
    expect((await as(parent).get(`/v1/photos/${photo.id}`)).statusCode).toBe(404);

    const { code } = (await as(student).post('/v1/family/pairing-code')).json();
    await as(parent).post('/v1/family/links', { code });
    expect((await as(parent).get(`/v1/photos/${photo.id}`)).statusCode).toBe(200);
    const child = (await as(parent).get(`/v1/parent/children/${student.userId}`)).json();
    expect(child.activeSession.photoIds).toEqual([photo.id]);

    const stranger = await signUp(ctx, { dateOfBirth: DOB.student16 });
    expect((await as(stranger).get(`/v1/photos/${photo.id}`)).statusCode).toBe(404);
    expect((await as(stranger).post(`/v1/sessions/${id}/photos`, { mime: 'image/jpeg', data: JPEG })).statusCode).toBe(404);
  });
});
