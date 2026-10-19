import { Prisma, type PrismaClient, type StudySession, type User } from '@prisma/client';
import { AppError, notFound } from '../../lib/errors.js';
import type { Clock } from '../../lib/clock.js';
import { PASS_PERCENT_FLOOR, type ConfigService, type Settings } from '../config/config.service.js';
import type { NotificationsService } from '../notifications/notifications.service.js';
import type { UsersService } from '../users/users.service.js';
import type { ExamSettings, QuestionType, StartSessionInput } from './sessions.schemas.js';

const MINUTE = 60_000;
const DAY = 24 * 60 * MINUTE;
const ACTIVE: StudySession['status'][] = ['STUDYING', 'EXAM_PENDING'];

export interface SessionView {
  id: string;
  subject: string;
  topics: string;
  notes: string;
  /** Photos of the study material; fetch each from /v1/photos/:id. */
  photoIds: string[];
  plannedMinutes: number;
  status: StudySession['status'];
  lockedApps: string[];
  strict: boolean;
  exam: ExamSettings;
  startedAt: string;
  /** When the timer finishes. */
  endsAt: string;
  /** From when the student may stop early and take the exam. */
  canFinishAt: string;
  studyEndedAt: string | null;
  completedAt: string | null;
  studiedMinutes: number;
}

export interface StudyStats {
  todayMinutes: number;
  streakDays: number;
  week: { day: string; minutes: number }[];
  totalMinutes: number;
  sessionsCompleted: number;
}

/** Throws unless the pass mark meets the floor and the size is within limits. */
export function assertExamAllowed(exam: ExamSettings, settings: Settings): void {
  // Belt and braces: the floor holds even if a setting slipped past validation.
  const percent = Math.max(PASS_PERCENT_FLOOR, settings.minPassPercent);
  const minPass = Math.ceil((exam.totalMarks * percent) / 100);
  if (exam.passMarks < minPass) {
    throw new AppError(400, 'VALIDATION_FAILED', `The pass mark must be at least ${percent}%.`, {
      fields: { 'exam.passMarks': [`Choose at least ${minPass} of ${exam.totalMarks} marks.`] },
    });
  }
  if (exam.questionCount > settings.maxQuestions) {
    throw new AppError(400, 'VALIDATION_FAILED', `Ask for at most ${settings.maxQuestions} questions.`, {
      fields: { 'exam.questionCount': [`At most ${settings.maxQuestions} questions.`] },
    });
  }
}

export class SessionsService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly config: ConfigService,
    private readonly users: UsersService,
    private readonly notifications: NotificationsService,
    private readonly clock: Clock,
  ) {}

  /** Students under 15 can only study once a parent is linked. */
  async assertStudyAllowed(student: User): Promise<void> {
    if (!this.users.requiresParentalControl(student)) return;
    const parents = await this.prisma.familyLink.count({ where: { studentId: student.id } });
    if (parents === 0) {
      throw new AppError(403, 'PARENT_REQUIRED', 'Link a parent before you start studying.');
    }
  }

  async start(student: User, input: StartSessionInput): Promise<SessionView> {
    await this.assertStudyAllowed(student);
    const settings = await this.config.get();
    if (input.plannedMinutes < settings.minStudyMinutes || input.plannedMinutes > settings.maxStudyMinutes) {
      throw new AppError(
        400,
        'VALIDATION_FAILED',
        `Study for ${settings.minStudyMinutes} to ${settings.maxStudyMinutes} minutes.`,
        { fields: { plannedMinutes: [`Pick ${settings.minStudyMinutes}–${settings.maxStudyMinutes} minutes.`] } },
      );
    }
    assertExamAllowed(input.exam, settings);

    // Younger students always get strict mode, so the lock cannot be undone in Settings.
    const young = this.users.requiresParentalControl(student);
    const strict = input.strict || young;
    if (young && input.lockedApps.length > 0) await this.assertProtected(student.id);
    try {
      const session = await this.prisma.$transaction(
        async (tx) => {
          const running = await tx.studySession.count({ where: { studentId: student.id, status: { in: ACTIVE } } });
          if (running > 0) throw sessionActive();
          return tx.studySession.create({
            data: {
              studentId: student.id,
              subject: input.subject,
              topics: input.topics,
              notes: input.notes,
              plannedMinutes: input.plannedMinutes,
              lockedApps: JSON.stringify(input.lockedApps),
              strict,
              questionCount: input.exam.questionCount,
              totalMarks: input.exam.totalMarks,
              passMarks: input.exam.passMarks,
              questionTypes: JSON.stringify(input.exam.questionTypes),
              difficulty: input.exam.difficulty,
              earlyFinishPercent: settings.earlyFinishPercent,
              startedAt: this.clock(),
            },
          });
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      );
      await this.notifications
        .notifyParents(
          student.id,
          'SESSION_STARTED',
          `${student.name} started studying`,
          `${session.subject}: ${session.topics} for ${session.plannedMinutes} min.`,
          { sessionId: session.id },
        )
        .catch(() => undefined);
      return this.view(session);
    } catch (err) {
      if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2034') throw sessionActive();
      throw err;
    }
  }

  /** The running session, moved to EXAM_PENDING if its timer has finished. */
  /**
   * A younger student's phone must be enforcing locks before a locked session
   * starts: App lock on, recently seen, and no accessibility shortcut.
   */
  private async assertProtected(studentId: string): Promise<void> {
    const since = new Date(this.clock().getTime() - 10 * MINUTE);
    const ready = await this.prisma.device.count({
      where: { studentId, revokedAt: null, protectionOn: true, shortcutOn: false, lastSeenAt: { gte: since } },
    });
    if (ready === 0) {
      throw new AppError(409, 'PROTECTION_REQUIRED', 'Turn on App lock on this phone first, then start your session.');
    }
  }

  async active(studentId: string): Promise<SessionView | null> {
    const session = await this.findActive(studentId);
    return session ? this.view(session) : null;
  }

  async findActive(studentId: string): Promise<StudySession | null> {
    const session = await this.prisma.studySession.findFirst({
      where: { studentId, status: { in: ACTIVE } },
      orderBy: { startedAt: 'desc' },
    });
    return session ? this.settle(session) : null;
  }

  /** Stop studying early (after the allowed share of the timer) to take the exam. */
  async finish(student: User, sessionId: string): Promise<SessionView> {
    const session = await this.owned(student.id, sessionId);
    const settled = await this.settle(session);
    if (settled.status !== 'STUDYING') return this.view(settled);

    const now = this.clock();
    const canFinishAt = this.canFinishAt(settled);
    if (now < canFinishAt) {
      const minutes = Math.ceil((canFinishAt.getTime() - now.getTime()) / MINUTE);
      throw new AppError(409, 'TOO_EARLY', `Keep going! You can finish in ${minutes} min.`, {
        canFinishAt: canFinishAt.toISOString(),
      });
    }
    // Guarded on STUDYING so a slow request can never re-lock a session that moved on.
    await this.prisma.studySession.updateMany({
      where: { id: settled.id, status: 'STUDYING' },
      data: { status: 'EXAM_PENDING', studyEndedAt: now },
    });
    return this.view(await this.prisma.studySession.findUniqueOrThrow({ where: { id: settled.id } }));
  }

  async list(studentId: string, limit: number): Promise<SessionView[]> {
    const sessions = await this.prisma.studySession.findMany({
      where: { studentId },
      orderBy: { startedAt: 'desc' },
      take: limit,
    });
    const settled = await Promise.all(sessions.map((s) => this.settle(s)));
    return settled.map((s) => this.view(s));
  }

  async get(studentId: string, sessionId: string): Promise<SessionView> {
    return this.view(await this.settle(await this.owned(studentId, sessionId)));
  }

  async stats(studentId: string, utcOffsetMinutes: number): Promise<StudyStats> {
    const now = this.clock();
    const since = new Date(now.getTime() - 60 * DAY);
    const sessions = await this.prisma.studySession.findMany({
      where: { studentId, status: { not: 'CANCELLED' }, startedAt: { gte: since } },
      select: { startedAt: true, plannedMinutes: true, studyEndedAt: true, status: true },
    });
    const sessionsCompleted = await this.prisma.studySession.count({ where: { studentId, status: 'PASSED' } });

    const offset = utcOffsetMinutes * MINUTE;
    const localDay = (date: Date) => new Date(date.getTime() + offset).toISOString().slice(0, 10);
    const perDay = new Map<string, number>();
    let totalMinutes = 0;
    for (const s of sessions) {
      const minutes = this.studiedMinutes(s, now);
      totalMinutes += minutes;
      perDay.set(localDay(s.startedAt), (perDay.get(localDay(s.startedAt)) ?? 0) + minutes);
    }

    const week = Array.from({ length: 7 }, (_, i) => {
      const day = localDay(new Date(now.getTime() - (6 - i) * DAY));
      return { day, minutes: perDay.get(day) ?? 0 };
    });

    // Today without study yet does not break a streak that ran until yesterday.
    let streakDays = 0;
    for (let i = (perDay.get(localDay(now)) ?? 0) > 0 ? 0 : 1; ; i++) {
      if ((perDay.get(localDay(new Date(now.getTime() - i * DAY))) ?? 0) <= 0) break;
      streakDays++;
    }

    return { todayMinutes: perDay.get(localDay(now)) ?? 0, streakDays, week, totalMinutes, sessionsCompleted };
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  private async owned(studentId: string, sessionId: string): Promise<StudySession> {
    const session = await this.prisma.studySession.findUnique({ where: { id: sessionId } });
    if (!session || session.studentId !== studentId) throw notFound('Session not found.');
    return session;
  }

  /** Persists the move to EXAM_PENDING once the timer has run out. */
  private async settle(session: StudySession): Promise<StudySession> {
    if (session.status !== 'STUDYING' || this.clock() < this.endsAt(session)) return session;
    const { count } = await this.prisma.studySession.updateMany({
      where: { id: session.id, status: 'STUDYING' },
      data: { status: 'EXAM_PENDING', studyEndedAt: this.endsAt(session) },
    });
    return count > 0
      ? { ...session, status: 'EXAM_PENDING', studyEndedAt: this.endsAt(session) }
      : this.prisma.studySession.findUniqueOrThrow({ where: { id: session.id } });
  }

  private endsAt(s: Pick<StudySession, 'startedAt' | 'plannedMinutes'>): Date {
    return new Date(s.startedAt.getTime() + s.plannedMinutes * MINUTE);
  }

  private canFinishAt(s: Pick<StudySession, 'startedAt' | 'plannedMinutes' | 'earlyFinishPercent'>): Date {
    return new Date(s.startedAt.getTime() + Math.round((s.plannedMinutes * MINUTE * s.earlyFinishPercent) / 100));
  }

  private studiedMinutes(
    s: Pick<StudySession, 'startedAt' | 'plannedMinutes' | 'studyEndedAt' | 'status'>,
    now: Date,
  ): number {
    if (s.status === 'CANCELLED') return 0;
    const end = Math.min((s.studyEndedAt ?? now).getTime(), this.endsAt(s).getTime());
    return Math.max(0, Math.floor((end - s.startedAt.getTime()) / MINUTE));
  }

  view(s: StudySession): SessionView {
    return {
      id: s.id,
      subject: s.subject,
      topics: s.topics,
      notes: s.notes,
      photoIds: JSON.parse(s.photoIds) as string[],
      plannedMinutes: s.plannedMinutes,
      status: s.status,
      lockedApps: JSON.parse(s.lockedApps) as string[],
      strict: s.strict,
      exam: {
        questionCount: s.questionCount,
        totalMarks: s.totalMarks,
        passMarks: s.passMarks,
        questionTypes: JSON.parse(s.questionTypes) as QuestionType[],
        difficulty: s.difficulty,
      },
      startedAt: s.startedAt.toISOString(),
      endsAt: this.endsAt(s).toISOString(),
      canFinishAt: this.canFinishAt(s).toISOString(),
      studyEndedAt: s.studyEndedAt?.toISOString() ?? null,
      completedAt: s.completedAt?.toISOString() ?? null,
      studiedMinutes: this.studiedMinutes(s, this.clock()),
    };
  }
}

const sessionActive = () =>
  new AppError(409, 'SESSION_ACTIVE', 'You already have a study session running. Finish it first.');
