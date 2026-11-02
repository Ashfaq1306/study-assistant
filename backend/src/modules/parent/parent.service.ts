import type { Exam, ParentLock, PrismaClient, QuestionSet, User } from '@prisma/client';
import { ageOn } from '../../lib/age.js';
import { AppError, notFound } from '../../lib/errors.js';
import type { Clock } from '../../lib/clock.js';
import type { ConfigService } from '../config/config.service.js';
import { toView as deviceView, type DeviceView } from '../devices/devices.service.js';
import type { ScreenTimeDay, UsageService } from '../devices/usage.service.js';
import type { NotificationsService } from '../notifications/notifications.service.js';
import type { QuestionType } from '../sessions/sessions.schemas.js';
import { assertExamAllowed, type SessionsService, type SessionView, type StudyStats } from '../sessions/sessions.service.js';
import type { CreateLockInput, QuestionSetInput } from './parent.schemas.js';

const MINUTE = 60_000;
const DAY = 24 * 60 * MINUTE;
/** A phone that has not checked in for this long may be off, offline or tampered with. */
const STALE_AFTER_MS = 30 * MINUTE;
/** Keeps a phone from being locked under a pile of parent locks. */
const MAX_ACTIVE_LOCKS = 5;

export interface LockView {
  id: string;
  title: string;
  subject: string;
  topics: string;
  lockedApps: string[];
  strict: boolean;
  questionSetId: string | null;
  exam: { questionCount: number; totalMarks: number; passMarks: number; questionTypes: QuestionType[]; difficulty: string };
  status: ParentLock['status'];
  createdAt: string;
  endedAt: string | null;
}

export interface ExamSummary {
  id: string;
  subject: string;
  topics: string;
  source: string;
  score: number | null;
  totalMarks: number;
  passMarks: number;
  passed: boolean;
  status: Exam['status'];
  createdAt: string;
}

export type ProtectionStatus = 'ON' | 'OFF' | 'SHORTCUT_ON' | 'STALE' | 'NO_PHONE';

export interface ChildSummary {
  id: string;
  name: string;
  age: number;
  todayStudyMinutes: number;
  todayScreenMinutes: number;
  streakDays: number;
  activeSession: SessionView | null;
  activeLocks: LockView[];
  lastExam: ExamSummary | null;
  protection: { status: ProtectionStatus; lastSeenAt: string | null };
}

export interface ChildDetail extends ChildSummary {
  stats: StudyStats;
  screenTime: ScreenTimeDay[];
  recentExams: ExamSummary[];
  recentSessions: SessionView[];
  recentLocks: LockView[];
  devices: DeviceView[];
  /** Apps on the child's phones, for the lock picker. */
  installedApps: { package: string; label: string }[];
}

export interface QuestionSetView {
  id: string;
  title: string;
  subject: string;
  questions: QuestionSetInput['questions'];
  usedByActiveLocks: number;
  updatedAt: string;
}

/** What a linked parent can see and do for each child. */
export class ParentService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly sessions: SessionsService,
    private readonly usage: UsageService,
    private readonly config: ConfigService,
    private readonly notifications: NotificationsService,
    private readonly clock: Clock,
  ) {}

  async children(parent: User, utcOffsetMinutes: number): Promise<ChildSummary[]> {
    const links = await this.prisma.familyLink.findMany({
      where: { parentId: parent.id, student: { disabledAt: null } },
      include: { student: true },
      orderBy: { createdAt: 'asc' },
    });
    return Promise.all(links.map((l) => this.summary(l.student, utcOffsetMinutes)));
  }

  async child(parent: User, childId: string, utcOffsetMinutes: number): Promise<ChildDetail> {
    const child = await this.linkedChild(parent, childId);
    const days = this.lastDays(7, utcOffsetMinutes);
    const [summary, stats, screenTime, exams, sessions, locks, devices] = await Promise.all([
      this.summary(child, utcOffsetMinutes),
      this.sessions.stats(child.id, utcOffsetMinutes),
      this.usage.forStudent(child.id, days),
      this.prisma.exam.findMany({ where: { studentId: child.id }, orderBy: { createdAt: 'desc' }, take: 10 }),
      this.sessions.list(child.id, 10),
      this.prisma.parentLock.findMany({
        where: { studentId: child.id, parentId: parent.id },
        orderBy: { createdAt: 'desc' },
        take: 10,
      }),
      this.prisma.device.findMany({ where: { studentId: child.id, revokedAt: null }, orderBy: { lastSeenAt: 'desc' } }),
    ]);

    const installed = new Map<string, string>();
    for (const d of devices) {
      for (const app of JSON.parse(d.installedApps) as { package: string; label: string }[]) {
        installed.set(app.package, app.label);
      }
    }
    return {
      ...summary,
      stats,
      screenTime,
      recentExams: exams.map(examSummary),
      recentSessions: sessions,
      recentLocks: locks.map(lockView),
      devices: devices.map(deviceView),
      installedApps: [...installed]
        .map(([pkg, label]) => ({ package: pkg, label }))
        .sort((a, b) => a.label.localeCompare(b.label)),
    };
  }

  async createLock(parent: User, childId: string, input: CreateLockInput): Promise<LockView> {
    const child = await this.linkedChild(parent, childId);
    const settings = await this.config.get();

    let questionCount = input.exam.questionCount;
    let questionTypes: QuestionType[] = input.exam.questionTypes;
    if (input.questionSetId) {
      const set = await this.ownedSet(parent, input.questionSetId);
      const questions = JSON.parse(set.questions) as QuestionSetInput['questions'];
      questionCount = questions.length;
      questionTypes = [...new Set(questions.map((q) => q.type))];
      if (input.exam.totalMarks < questionCount) {
        throw new AppError(400, 'VALIDATION_FAILED', 'Give each question at least 1 mark.', {
          fields: { 'exam.totalMarks': [`At least ${questionCount} marks for ${questionCount} questions.`] },
        });
      }
    }
    // Same floor as a student's own exam: at least 50% (or the admin's higher minimum).
    assertExamAllowed({ ...input.exam, questionCount: Math.min(questionCount, settings.maxQuestions) }, settings);

    const active = await this.prisma.parentLock.count({ where: { studentId: child.id, status: 'ACTIVE' } });
    if (active >= MAX_ACTIVE_LOCKS) {
      throw new AppError(409, 'TOO_MANY_LOCKS', `A phone can have at most ${MAX_ACTIVE_LOCKS} locks at a time.`);
    }

    const lock = await this.prisma.parentLock.create({
      data: {
        parentId: parent.id,
        studentId: child.id,
        title: input.title,
        subject: input.subject,
        topics: input.topics,
        lockedApps: JSON.stringify(input.lockedApps.includes('*') ? ['*'] : input.lockedApps),
        // Younger children always get strict mode, as with their own sessions.
        strict: input.strict || ageOn(child.dateOfBirth, this.clock()) < 15,
        questionSetId: input.questionSetId ?? null,
        questionCount,
        totalMarks: input.exam.totalMarks,
        passMarks: input.exam.passMarks,
        questionTypes: JSON.stringify(questionTypes),
        difficulty: input.exam.difficulty,
        createdAt: this.clock(),
      },
    });
    await this.notifications.notify(
      [child.id],
      'PARENT_LOCK',
      `${parent.name} added a lock: ${lock.title}`,
      `Pass a ${lock.subject} exam (${lock.passMarks}/${lock.totalMarks}) to unlock. You've got this!`,
      { lockId: lock.id },
    );
    return lockView(lock);
  }

  /** The parent who set a lock can lift it. */
  async cancelLock(parent: User, lockId: string): Promise<LockView> {
    const lock = await this.prisma.parentLock.findUnique({ where: { id: lockId } });
    if (!lock || lock.parentId !== parent.id) throw notFound('Lock not found.');
    if (lock.status !== 'ACTIVE') return lockView(lock);
    await this.prisma.parentLock.updateMany({
      where: { id: lock.id, status: 'ACTIVE' },
      data: { status: 'CANCELLED', endedAt: this.clock() },
    });
    return lockView((await this.prisma.parentLock.findUnique({ where: { id: lock.id } }))!);
  }

  // ── question sets ──────────────────────────────────────────────────────────

  async questionSets(parent: User): Promise<QuestionSetView[]> {
    const sets = await this.prisma.questionSet.findMany({
      where: { parentId: parent.id },
      orderBy: { updatedAt: 'desc' },
      include: { _count: { select: { locks: { where: { status: 'ACTIVE' } } } } },
    });
    return sets.map((s) => setView(s, s._count.locks));
  }

  async createQuestionSet(parent: User, input: QuestionSetInput): Promise<QuestionSetView> {
    const count = await this.prisma.questionSet.count({ where: { parentId: parent.id } });
    if (count >= 100) throw new AppError(409, 'TOO_MANY_SETS', 'You can keep up to 100 question sets.');
    const set = await this.prisma.questionSet.create({
      data: { parentId: parent.id, title: input.title, subject: input.subject, questions: JSON.stringify(input.questions) },
    });
    return setView(set, 0);
  }

  /** Not while an active lock uses it: the child's exam must not change under them. */
  async updateQuestionSet(parent: User, id: string, input: QuestionSetInput): Promise<QuestionSetView> {
    await this.ownedSet(parent, id);
    await this.assertSetUnused(id);
    const set = await this.prisma.questionSet.update({
      where: { id },
      data: { title: input.title, subject: input.subject, questions: JSON.stringify(input.questions) },
    });
    return setView(set, 0);
  }

  async deleteQuestionSet(parent: User, id: string): Promise<void> {
    await this.ownedSet(parent, id);
    await this.assertSetUnused(id);
    await this.prisma.questionSet.delete({ where: { id } });
  }

  // ── students ───────────────────────────────────────────────────────────────

  /** A student's own active parent locks. */
  async locksFor(studentId: string): Promise<LockView[]> {
    const locks = await this.prisma.parentLock.findMany({
      where: { studentId, status: 'ACTIVE' },
      orderBy: { createdAt: 'asc' },
    });
    return locks.map(lockView);
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  private async summary(child: User, utcOffsetMinutes: number): Promise<ChildSummary> {
    const now = this.clock();
    const [today] = this.lastDays(1, utcOffsetMinutes);
    const [stats, active, locks, lastExam, devices, screen] = await Promise.all([
      this.sessions.stats(child.id, utcOffsetMinutes),
      this.sessions.active(child.id),
      this.prisma.parentLock.findMany({ where: { studentId: child.id, status: 'ACTIVE' }, orderBy: { createdAt: 'asc' } }),
      this.prisma.exam.findFirst({ where: { studentId: child.id, status: { not: 'ACTIVE' } }, orderBy: { createdAt: 'desc' } }),
      this.prisma.device.findMany({ where: { studentId: child.id, revokedAt: null }, orderBy: { lastSeenAt: 'desc' } }),
      this.usage.forStudent(child.id, [today!]),
    ]);

    let status: ProtectionStatus = 'NO_PHONE';
    const phone = devices[0];
    if (phone) {
      if (now.getTime() - phone.lastSeenAt.getTime() > STALE_AFTER_MS) status = 'STALE';
      else if (!phone.protectionOn) status = 'OFF';
      else if (phone.shortcutOn) status = 'SHORTCUT_ON';
      else status = 'ON';
    }

    return {
      id: child.id,
      name: child.name,
      age: ageOn(child.dateOfBirth, now),
      todayStudyMinutes: stats.todayMinutes,
      todayScreenMinutes: screen[0]?.totalMinutes ?? 0,
      streakDays: stats.streakDays,
      activeSession: active,
      activeLocks: locks.map(lockView),
      lastExam: lastExam ? examSummary(lastExam) : null,
      protection: { status, lastSeenAt: phone?.lastSeenAt.toISOString() ?? null },
    };
  }

  /** Local calendar days, newest first. */
  private lastDays(count: number, utcOffsetMinutes: number): string[] {
    const local = this.clock().getTime() + utcOffsetMinutes * MINUTE;
    return Array.from({ length: count }, (_, i) => new Date(local - i * DAY).toISOString().slice(0, 10));
  }

  private async linkedChild(parent: User, childId: string): Promise<User> {
    const link = await this.prisma.familyLink.findUnique({
      where: { parentId_studentId: { parentId: parent.id, studentId: childId } },
      include: { student: true },
    });
    if (!link || link.student.disabledAt) throw notFound('Child not found.');
    return link.student;
  }

  private async ownedSet(parent: User, id: string): Promise<QuestionSet> {
    const set = await this.prisma.questionSet.findUnique({ where: { id } });
    if (!set || set.parentId !== parent.id) throw notFound('Question set not found.');
    return set;
  }

  private async assertSetUnused(id: string): Promise<void> {
    const active = await this.prisma.parentLock.count({ where: { questionSetId: id, status: 'ACTIVE' } });
    if (active > 0) {
      throw new AppError(409, 'SET_IN_USE', 'An active lock uses these questions. Lift the lock first.');
    }
  }
}

export function lockView(l: ParentLock): LockView {
  return {
    id: l.id,
    title: l.title,
    subject: l.subject,
    topics: l.topics,
    lockedApps: JSON.parse(l.lockedApps) as string[],
    strict: l.strict,
    questionSetId: l.questionSetId,
    exam: {
      questionCount: l.questionCount,
      totalMarks: l.totalMarks,
      passMarks: l.passMarks,
      questionTypes: JSON.parse(l.questionTypes) as QuestionType[],
      difficulty: l.difficulty,
    },
    status: l.status,
    createdAt: l.createdAt.toISOString(),
    endedAt: l.endedAt?.toISOString() ?? null,
  };
}

function examSummary(e: Exam): ExamSummary {
  return {
    id: e.id,
    subject: e.subject,
    topics: e.topics,
    source: e.source,
    score: e.score,
    totalMarks: e.totalMarks,
    passMarks: e.passMarks,
    passed: e.passed ?? false,
    status: e.status,
    createdAt: e.createdAt.toISOString(),
  };
}

function setView(s: QuestionSet, usedByActiveLocks: number): QuestionSetView {
  return {
    id: s.id,
    title: s.title,
    subject: s.subject,
    questions: JSON.parse(s.questions) as QuestionSetInput['questions'],
    usedByActiveLocks,
    updatedAt: s.updatedAt.toISOString(),
  };
}
