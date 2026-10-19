import { Prisma, type Exam, type PrismaClient, type User } from '@prisma/client';
import type { FastifyBaseLogger } from 'fastify';
import { randomInt } from 'node:crypto';
import { randomToken } from '../../lib/crypto.js';
import { ageOn } from '../../lib/age.js';
import { AppError, notFound } from '../../lib/errors.js';
import type { Clock } from '../../lib/clock.js';
import {
  AiUnavailableError,
  type AiProvider,
  type ExamSpec,
  type GeneratedQuestion,
  type ShortAnswerGrade,
} from '../ai/ai.types.js';
import { PracticeProvider } from '../ai/practice.provider.js';
import type { ConfigService } from '../config/config.service.js';
import type { NotificationsService } from '../notifications/notifications.service.js';
import type { QuestionType } from '../sessions/sessions.schemas.js';
import type { SessionsService } from '../sessions/sessions.service.js';

/** Late submissions within this window still count (slow networks). */
export const SUBMIT_GRACE_MS = 60_000;
const MIN_EXAM_MS = 5 * 60_000;
const PER_QUESTION_MS = 90_000;

export interface StoredQuestion {
  id: string;
  type: QuestionType;
  prompt: string;
  options: string[];
  answer: string;
  keyPoints: string[];
  explanation: string;
  marks: number;
}

export interface QuestionResult {
  id: string;
  given: string | null;
  correct: boolean;
  awarded: number;
  marks: number;
  correctAnswer: string;
  explanation: string;
  feedback: string;
}

export interface ExamView {
  id: string;
  sessionId: string | null;
  parentLockId: string | null;
  subject: string;
  topics: string;
  source: string;
  status: Exam['status'];
  totalMarks: number;
  passMarks: number;
  createdAt: string;
  expiresAt: string;
  questions: { id: string; type: QuestionType; prompt: string; options: string[]; marks: number }[];
  /** Present once submitted. */
  result: { score: number; passed: boolean; submittedAt: string; questions: QuestionResult[] } | null;
}

export interface ExamTarget {
  sessionId?: string;
  parentLockId?: string;
  /** A parent's own questions, used instead of generated ones. */
  fixedQuestions?: GeneratedQuestion[];
  subject: string;
  topics: string;
  difficulty: ExamSpec['difficulty'];
  questionCount: number;
  totalMarks: number;
  passMarks: number;
  types: QuestionType[];
}

const parseQuestions = (exam: Exam) => JSON.parse(exam.questions) as StoredQuestion[];

/** Splits total marks over the questions as evenly as possible (first ones get the remainder). */
export function distributeMarks(total: number, count: number): number[] {
  const base = Math.floor(total / count);
  const remainder = total - base * count;
  return Array.from({ length: count }, (_, i) => base + (i < remainder ? 1 : 0));
}

/** Fisher–Yates shuffle with a crypto RNG. */
function shuffled<T>(list: readonly T[]): T[] {
  const out = [...list];
  for (let i = out.length - 1; i > 0; i--) {
    const j = randomInt(i + 1);
    [out[i], out[j]] = [out[j]!, out[i]!];
  }
  return out;
}

/** Shuffles a parent's questions and their options, so a retry is not the same paper. */
export function shuffleFixed(questions: GeneratedQuestion[]): GeneratedQuestion[] {
  return shuffled(questions).map((q) => {
    if (q.type !== 'MCQ') return q;
    const order = shuffled([0, 1, 2, 3]);
    return { ...q, options: order.map((i) => q.options[i]!), answer: String(order.indexOf(Number(q.answer))) };
  });
}

/** Drops malformed questions so a bad AI answer can never produce an ungradable exam. */
export function isValidQuestion(q: GeneratedQuestion, types: QuestionType[]): boolean {
  if (!types.includes(q.type)) return false;
  if (q.type === 'MCQ') {
    const index = Number(q.answer);
    return q.options.length === 4 && new Set(q.options).size === 4 && Number.isInteger(index) && index >= 0 && index < 4;
  }
  if (q.type === 'TRUE_FALSE') return q.answer === 'true' || q.answer === 'false';
  return q.answer.trim().length > 0;
}

export class ExamsService {
  private readonly practice = new PracticeProvider();

  constructor(
    private readonly prisma: PrismaClient,
    private readonly ai: AiProvider,
    private readonly config: ConfigService,
    private readonly sessions: SessionsService,
    private readonly notifications: NotificationsService,
    private readonly clock: Clock,
    private readonly log: FastifyBaseLogger,
  ) {}

  /** The exam that unlocks a study session: resumes a running one or builds a new one. */
  async startForSession(student: User, sessionId: string): Promise<ExamView> {
    const session = await this.sessions.findActive(student.id);
    if (!session || session.id !== sessionId) {
      const existing = await this.prisma.studySession.findUnique({ where: { id: sessionId } });
      if (!existing || existing.studentId !== student.id) throw notFound('Session not found.');
      throw new AppError(409, 'ALREADY_PASSED', 'This session is already finished.');
    }
    if (session.status === 'STUDYING') {
      throw new AppError(409, 'EXAM_NOT_READY', 'Finish studying first, then take your exam.');
    }

    return this.start(student, {
      sessionId: session.id,
      subject: session.subject,
      topics: session.topics,
      difficulty: session.difficulty,
      questionCount: session.questionCount,
      totalMarks: session.totalMarks,
      passMarks: session.passMarks,
      types: JSON.parse(session.questionTypes) as QuestionType[],
    });
  }

  /** The exam that lifts a parent's lock. */
  async startForLock(student: User, lockId: string): Promise<ExamView> {
    const lock = await this.prisma.parentLock.findUnique({ where: { id: lockId }, include: { questionSet: true } });
    if (!lock || lock.studentId !== student.id) throw notFound('Lock not found.');
    if (lock.status !== 'ACTIVE') throw new AppError(409, 'ALREADY_PASSED', 'This lock has already been lifted.');

    const fixed = lock.questionSet ? (JSON.parse(lock.questionSet.questions) as GeneratedQuestion[]) : undefined;
    return this.start(student, {
      parentLockId: lock.id,
      subject: lock.subject,
      topics: lock.topics,
      difficulty: lock.difficulty,
      questionCount: fixed ? fixed.length : lock.questionCount,
      totalMarks: lock.totalMarks,
      passMarks: lock.passMarks,
      types: fixed ? [...new Set(fixed.map((q) => q.type))] : (JSON.parse(lock.questionTypes) as QuestionType[]),
      fixedQuestions: fixed,
    });
  }

  /** Shared by study sessions and parent locks. */
  async start(student: User, target: ExamTarget): Promise<ExamView> {
    const now = this.clock();
    const scope = { sessionId: target.sessionId ?? null, parentLockId: target.parentLockId ?? null };
    const activeKey = `${student.id}:${target.sessionId ?? (target.parentLockId ? `lock:${target.parentLockId}` : '-')}`;

    const running = await this.prisma.exam.findFirst({
      where: { studentId: student.id, ...scope, status: 'ACTIVE' },
      orderBy: { createdAt: 'desc' },
    });
    if (running && running.expiresAt.getTime() + SUBMIT_GRACE_MS > now.getTime()) return this.view(running);
    if (running) await this.expire(running.id);

    const settings = await this.config.get();
    const last = await this.prisma.exam.findFirst({
      where: { studentId: student.id, ...scope, status: { in: ['SUBMITTED', 'EXPIRED'] } },
      orderBy: { createdAt: 'desc' },
    });
    if (last && !last.passed) {
      const endedAt = last.submittedAt ?? last.expiresAt;
      const retryAt = new Date(endedAt.getTime() + settings.examRetryCooldownSeconds * 1000);
      if (retryAt > now) {
        const seconds = Math.ceil((retryAt.getTime() - now.getTime()) / 1000);
        throw new AppError(429, 'EXAM_COOLDOWN', `Take a short break and revise. You can try again in ${seconds}s.`, {
          retryAt: retryAt.toISOString(),
        });
      }
    }

    const { questions, source } = target.fixedQuestions
      ? { questions: shuffleFixed(target.fixedQuestions), source: 'PARENT' }
      : await this.generate(student, target, settings.aiEnabled);
    const marks = distributeMarks(target.totalMarks, questions.length);
    const stored: StoredQuestion[] = questions.map((q, i) => ({
      id: randomToken(6),
      type: q.type,
      prompt: q.prompt,
      options: q.type === 'MCQ' ? q.options : q.type === 'TRUE_FALSE' ? ['True', 'False'] : [],
      answer: q.answer,
      keyPoints: q.keyPoints,
      explanation: q.explanation,
      marks: marks[i]!,
    }));

    let exam: Exam;
    try {
      exam = await this.prisma.exam.create({
        data: {
          activeKey,
          studentId: student.id,
        sessionId: target.sessionId ?? null,
        parentLockId: target.parentLockId ?? null,
        subject: target.subject,
        topics: target.topics,
        difficulty: target.difficulty,
        totalMarks: target.totalMarks,
        passMarks: target.passMarks,
        questions: JSON.stringify(stored),
        source,
        createdAt: now,
        expiresAt: new Date(now.getTime() + Math.max(MIN_EXAM_MS, questions.length * PER_QUESTION_MS)),
        },
      });
    } catch (err) {
      // Another request (a retry after a slow network) created the exam first: use that one.
      if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
        const existing = await this.prisma.exam.findUnique({ where: { activeKey } });
        if (existing) return this.view(existing);
      }
      throw err;
    }
    if (source === 'AI') await this.prisma.aiUsage.create({ data: { userId: student.id, kind: 'EXAM', createdAt: now } });
    return this.view(exam);
  }

  async submit(student: User, examId: string, answers: Record<string, string>): Promise<ExamView> {
    const exam = await this.owned(student.id, examId);
    if (exam.status === 'SUBMITTED') return this.view(exam);
    if (exam.status === 'EXPIRED') throw expired();

    const now = this.clock();
    if (now.getTime() > exam.expiresAt.getTime() + SUBMIT_GRACE_MS) {
      await this.expire(exam.id);
      throw expired();
    }

    // Grade first: if grading fails, the exam is still open and can be handed in again.
    const questions = parseQuestions(exam);
    const shortGrades = await this.gradeShort(exam, questions, answers);
    const results: QuestionResult[] = questions.map((q) => {
      const given = answers[q.id]?.trim() ?? null;
      let fraction: number;
      let feedback: string;
      if (q.type === 'SHORT') {
        const grade = shortGrades.get(q.id);
        fraction = grade?.score ?? 0;
        feedback = grade?.feedback ?? '';
      } else {
        fraction = given !== null && given === q.answer ? 1 : 0;
        feedback = fraction === 1 ? 'Correct!' : 'Not quite.';
      }
      const awarded = Math.round(q.marks * fraction * 100) / 100;
      return {
        id: q.id,
        given,
        correct: fraction === 1,
        awarded,
        marks: q.marks,
        correctAnswer: q.type === 'MCQ' ? (q.options[Number(q.answer)] ?? q.answer) : q.type === 'TRUE_FALSE' ? (q.answer === 'true' ? 'True' : 'False') : q.answer,
        explanation: q.explanation,
        feedback,
      };
    });

    const score = Math.round(results.reduce((sum, r) => sum + r.awarded, 0) * 100) / 100;
    const passed = score >= exam.passMarks;

    // One write wins, even if the student tapped twice: the result and the unlock land together.
    // Passing is the only way a session or a parent's lock ends: this is what unlocks the apps.
    const outcome = await this.prisma.$transaction(async (tx) => {
      const { count } = await tx.exam.updateMany({
        where: { id: exam.id, status: 'ACTIVE' },
        data: {
          status: 'SUBMITTED',
          activeKey: null,
          submittedAt: now,
          answers: JSON.stringify(answers),
          results: JSON.stringify(results),
          score,
          passed,
        },
      });
      if (count === 0) return { won: false, liftedLock: null };
      if (!passed) return { won: true, liftedLock: null };
      if (exam.sessionId) {
        await tx.studySession.updateMany({
          where: { id: exam.sessionId, status: 'EXAM_PENDING' },
          data: { status: 'PASSED', completedAt: now },
        });
      }
      if (exam.parentLockId) {
        const lifted = await tx.parentLock.updateMany({
          where: { id: exam.parentLockId, status: 'ACTIVE' },
          data: { status: 'PASSED', endedAt: now },
        });
        if (lifted.count > 0) {
          const lock = await tx.parentLock.findUnique({ where: { id: exam.parentLockId } });
          return { won: true, liftedLock: lock?.title ?? null };
        }
      }
      return { won: true, liftedLock: null };
    });
    const graded = await this.owned(student.id, examId);
    if (outcome.won) await this.tellParents(student, graded, outcome.liftedLock);
    return this.view(graded);
  }

  async get(studentId: string, examId: string): Promise<ExamView> {
    return this.view(await this.owned(studentId, examId));
  }

  async list(studentId: string, limit: number): Promise<ExamView[]> {
    const exams = await this.prisma.exam.findMany({
      where: { studentId, status: { not: 'ACTIVE' } },
      orderBy: { createdAt: 'desc' },
      take: limit,
    });
    return exams.map((e) => this.view(e));
  }

  /** True while the student has an exam open (the study helper pauses then). */
  async hasRunningExam(studentId: string): Promise<boolean> {
    const now = this.clock();
    const running = await this.prisma.exam.count({
      where: { studentId, status: 'ACTIVE', expiresAt: { gt: new Date(now.getTime() - SUBMIT_GRACE_MS) } },
    });
    return running > 0;
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  private async tellParents(student: User, exam: Exam, liftedLock: string | null): Promise<void> {
    const score = `${formatScore(exam.score ?? 0)}/${exam.totalMarks}`;
    const data = { examId: exam.id };
    try {
      if (liftedLock) {
        await this.notifications.notifyParents(
          student.id,
          'LOCK_PASSED',
          `${student.name} unlocked "${liftedLock}"`,
          `Passed the ${exam.subject} exam with ${score}. The apps from your lock are open again.`,
          data,
        );
      } else if (exam.passed) {
        await this.notifications.notifyParents(
          student.id,
          'EXAM_PASSED',
          `${student.name} passed an exam`,
          `${exam.subject}: ${score} (pass mark ${exam.passMarks}).`,
          data,
        );
      } else {
        await this.notifications.notifyParents(
          student.id,
          'EXAM_FAILED',
          `${student.name} didn't pass yet`,
          `${exam.subject}: ${score}, needed ${exam.passMarks}. The apps stay locked until a retry is passed.`,
          data,
        );
      }
    } catch (err) {
      // An alert failing must never undo a graded exam.
      this.log.warn({ err }, 'could not notify parents');
    }
  }

  private async generate(
    student: User,
    target: ExamTarget,
    aiEnabled: boolean,
  ): Promise<{ questions: GeneratedQuestion[]; source: string }> {
    const spec: ExamSpec = {
      subject: target.subject,
      topics: target.topics,
      difficulty: target.difficulty,
      count: target.questionCount,
      types: target.types,
      age: ageOn(student.dateOfBirth, this.clock()),
    };
    const provider = aiEnabled ? this.ai : this.practice;
    let questions: GeneratedQuestion[] = [];
    let source: string = provider.source;
    try {
      questions = (await provider.generateExam(spec)).filter((q) => isValidQuestion(q, spec.types));
    } catch (err) {
      // Never leave a student locked because the AI is down: use practice questions.
      this.log.warn({ err }, 'exam generation failed; using practice questions');
      source = 'PRACTICE';
    }
    if (questions.length < spec.count) {
      const missing = spec.count - questions.length;
      const extra = await this.practice.generateExam({ ...spec, count: missing });
      questions = [...questions, ...extra];
      if (questions.length === extra.length) source = 'PRACTICE';
    }
    return { questions: questions.slice(0, spec.count), source };
  }

  private async gradeShort(
    exam: Exam,
    questions: StoredQuestion[],
    answers: Record<string, string>,
  ): Promise<Map<string, ShortAnswerGrade>> {
    const items = questions
      .filter((q) => q.type === 'SHORT')
      .map((q) => ({
        id: q.id,
        question: q.prompt,
        modelAnswer: q.answer,
        keyPoints: q.keyPoints,
        studentAnswer: (answers[q.id] ?? '').slice(0, 500),
      }));
    if (items.length === 0) return new Map();

    // Empty answers are simply wrong; only real attempts go to the grader.
    const attempted = items.filter((i) => i.studentAnswer.trim().length > 0);
    const byId = new Map<string, ShortAnswerGrade>();
    if (exam.source === 'AI' && attempted.length > 0) {
      try {
        for (const g of await this.ai.gradeShortAnswers(attempted)) {
          if (attempted.some((a) => a.id === g.id)) byId.set(g.id, g);
        }
        await this.prisma.aiUsage.create({ data: { userId: exam.studentId, kind: 'GRADE', createdAt: this.clock() } });
      } catch (err) {
        if (!(err instanceof AiUnavailableError)) throw err;
        this.log.warn({ err }, 'AI grading failed; using keyword grading');
      }
    }
    // Anything the AI did not grade gets keyword grading rather than a zero.
    const ungraded = attempted.filter((a) => !byId.has(a.id));
    for (const g of await this.practice.gradeShortAnswers(ungraded)) byId.set(g.id, g);

    for (const item of items) {
      if (!byId.has(item.id)) byId.set(item.id, { id: item.id, score: 0, feedback: `The answer is: ${item.modelAnswer}` });
    }
    return byId;
  }

  private async owned(studentId: string, examId: string): Promise<Exam> {
    const exam = await this.prisma.exam.findUnique({ where: { id: examId } });
    if (!exam || exam.studentId !== studentId) throw notFound('Exam not found.');
    return exam;
  }

  private async expire(examId: string): Promise<void> {
    await this.prisma.exam.updateMany({
      where: { id: examId, status: 'ACTIVE' },
      data: { status: 'EXPIRED', passed: false, activeKey: null },
    });
  }

  view(exam: Exam): ExamView {
    const questions = parseQuestions(exam);
    // A parent's questions come back on every retry: don't hand out their answers before a pass.
    const hideAnswers = exam.source === 'PARENT' && !exam.passed;
    return {
      id: exam.id,
      sessionId: exam.sessionId,
      parentLockId: exam.parentLockId,
      subject: exam.subject,
      topics: exam.topics,
      source: exam.source,
      status: exam.status,
      totalMarks: exam.totalMarks,
      passMarks: exam.passMarks,
      createdAt: exam.createdAt.toISOString(),
      expiresAt: exam.expiresAt.toISOString(),
      questions: questions.map((q) => ({ id: q.id, type: q.type, prompt: q.prompt, options: q.options, marks: q.marks })),
      result:
        exam.status === 'SUBMITTED' && exam.results
          ? {
              score: exam.score ?? 0,
              passed: exam.passed ?? false,
              submittedAt: (exam.submittedAt ?? exam.createdAt).toISOString(),
              questions: (JSON.parse(exam.results) as QuestionResult[]).map((r) =>
                hideAnswers
                  ? { ...r, correctAnswer: '', explanation: '', feedback: r.correct ? r.feedback : 'Not quite.' }
                  : r,
              ),
            }
          : null,
    };
  }
}

const expired = () => new AppError(409, 'EXAM_EXPIRED', 'Time ran out for this exam. Start a new one when you are ready.');

const formatScore = (n: number) => (Number.isInteger(n) ? String(n) : n.toFixed(1));
