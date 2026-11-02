import type { Prisma, PrismaClient, Role, StudySession } from '@prisma/client';
import type { Clock } from '../../lib/clock.js';
import { hashPassword, readablePassword } from '../../lib/crypto.js';
import { AppError, notFound } from '../../lib/errors.js';
import type { ActivityContext, ActivityService } from '../activity/activity.service.js';
import type { AuthTokens, TokenService } from '../auth/token.service.js';
import type { ConfigService, Settings } from '../config/config.service.js';
import type { NotificationsService } from '../notifications/notifications.service.js';
import type { SessionsService } from '../sessions/sessions.service.js';

const MINUTE = 60_000;
const DAY_MS = 24 * 60 * MINUTE;
/** Days shown in the activity chart. */
export const ACTIVITY_DAYS = 14;
/** Seen this recently = online. */
const ONLINE_MS = 5 * MINUTE;
/** A phone that synced this recently is online (the lock service syncs about every minute). */
const PHONE_ONLINE_MS = 3 * MINUTE;

export type Presence = 'online' | 'signedIn' | 'signedOut';

export interface UserListQuery {
  q?: string;
  role?: Role;
  status?: 'active' | 'disabled' | 'unverified';
  presence?: Presence;
  page: number;
  pageSize: number;
}

export interface ActivityQuery {
  userId?: string;
  kind?: string;
  page: number;
  pageSize: number;
}

const listSelect = {
  id: true,
  role: true,
  name: true,
  email: true,
  phone: true,
  dateOfBirth: true,
  verifiedAt: true,
  disabledAt: true,
  lastActiveAt: true,
  createdAt: true,
  _count: { select: { studySessions: true, exams: true, parentLinks: true, childLinks: true } },
} satisfies Prisma.UserSelect;

const studySelect = {
  studentId: true,
  subject: true,
  startedAt: true,
  plannedMinutes: true,
  studyEndedAt: true,
  status: true,
  adminUnlockedAt: true,
} satisfies Prisma.StudySessionSelect;

type StudyRow = Prisma.StudySessionGetPayload<{ select: typeof studySelect }>;

/** UTC calendar day, e.g. 2026-11-01. */
const dayKey = (date: Date) => date.toISOString().slice(0, 10);

/** Everything the web admin panel reads and changes. Every caller is an ADMIN (checked in the routes). */
export class AdminService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly config: ConfigService,
    private readonly sessions: SessionsService,
    private readonly notifications: NotificationsService,
    private readonly activity: ActivityService,
    private readonly tokens: TokenService,
    private readonly clock: Clock,
  ) {}

  // ── overview ───────────────────────────────────────────────────────────────

  async stats() {
    const now = this.clock();
    const weekAgo = new Date(now.getTime() - 7 * DAY_MS);
    const dayAgo = new Date(now.getTime() - DAY_MS);
    const todayStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
    const firstDay = new Date(todayStart.getTime() - (ACTIVITY_DAYS - 1) * DAY_MS);
    const p = this.prisma;

    const [
      byRole,
      verified,
      disabled,
      newUsers,
      online,
      signedIn,
      sessions,
      activeSessions,
      sessionsWeek,
      examsDone,
      examsPassed,
      examsWeek,
      devices,
      protectedDevices,
      devicesSeen,
      aiToday,
      links,
      recentUsers,
      recentSessions,
      recentExams,
    ] = await Promise.all([
      p.user.groupBy({ by: ['role'], _count: { _all: true } }),
      p.user.count({ where: { verifiedAt: { not: null } } }),
      p.user.count({ where: { disabledAt: { not: null } } }),
      p.user.count({ where: { createdAt: { gte: weekAgo } } }),
      p.user.count({ where: { lastActiveAt: { gte: new Date(now.getTime() - ONLINE_MS) } } }),
      p.session.groupBy({ by: ['userId'], where: this.liveSessionWhere(now) }).then((rows) => rows.length),
      p.studySession.count(),
      p.studySession.count({ where: { status: { in: ['STUDYING', 'EXAM_PENDING'] } } }),
      p.studySession.count({ where: { startedAt: { gte: weekAgo } } }),
      p.exam.count({ where: { submittedAt: { not: null } } }),
      p.exam.count({ where: { passed: true } }),
      p.exam.count({ where: { submittedAt: { gte: weekAgo } } }),
      p.device.count({ where: { revokedAt: null } }),
      p.device.count({ where: { revokedAt: null, protectionOn: true } }),
      p.device.count({ where: { revokedAt: null, lastSeenAt: { gte: dayAgo } } }),
      p.aiUsage.count({ where: { createdAt: { gte: dayAgo } } }),
      p.familyLink.count(),
      p.user.findMany({ where: { createdAt: { gte: firstDay } }, select: { createdAt: true } }),
      p.studySession.findMany({ where: { startedAt: { gte: firstDay } }, select: studySelect }),
      p.exam.findMany({ where: { submittedAt: { gte: firstDay } }, select: { submittedAt: true, passed: true } }),
    ]);

    const days = new Map<string, { date: string; signups: number; sessions: number; studyMinutes: number; exams: number; passed: number }>();
    for (let i = 0; i < ACTIVITY_DAYS; i++) {
      const date = dayKey(new Date(firstDay.getTime() + i * DAY_MS));
      days.set(date, { date, signups: 0, sessions: 0, studyMinutes: 0, exams: 0, passed: 0 });
    }
    for (const u of recentUsers) {
      const d = days.get(dayKey(u.createdAt));
      if (d) d.signups++;
    }
    let studyToday = 0;
    for (const s of recentSessions) {
      const minutes = this.sessions.studiedMinutes(s, now);
      if (s.startedAt >= todayStart) studyToday += minutes;
      const d = days.get(dayKey(s.startedAt));
      if (d) {
        d.sessions++;
        d.studyMinutes += minutes;
      }
    }
    for (const e of recentExams) {
      const d = e.submittedAt && days.get(dayKey(e.submittedAt));
      if (d) {
        d.exams++;
        if (e.passed) d.passed++;
      }
    }

    const roleCount = (role: Role) => byRole.find((r) => r.role === role)?._count._all ?? 0;
    return {
      generatedAt: now.toISOString(),
      users: {
        total: byRole.reduce((sum, r) => sum + r._count._all, 0),
        students: roleCount('STUDENT'),
        parents: roleCount('PARENT'),
        admins: roleCount('ADMIN'),
        verified,
        disabled,
        newThisWeek: newUsers,
        familyLinks: links,
        online,
        signedIn,
      },
      sessions: { total: sessions, active: activeSessions, thisWeek: sessionsWeek, minutesToday: studyToday },
      exams: {
        submitted: examsDone,
        passed: examsPassed,
        passRate: examsDone === 0 ? null : Math.round((examsPassed / examsDone) * 100),
        thisWeek: examsWeek,
      },
      devices: { registered: devices, protectionOn: protectedDevices, seenToday: devicesSeen },
      ai: { requestsToday: aiToday },
      activity: [...days.values()],
      live: await this.live(now),
    };
  }

  /** What is happening right now: who is studying, which phones are online or locked, the latest events. */
  private async live(now: Date) {
    const phoneSince = new Date(now.getTime() - PHONE_ONLINE_MS);
    const [running, parentLocked, phonesOnline, recent] = await Promise.all([
      this.prisma.studySession.findMany({
        where: { status: { in: ['STUDYING', 'EXAM_PENDING'] } },
        orderBy: { startedAt: 'desc' },
        take: 50,
        include: { student: { select: { id: true, name: true } } },
      }),
      this.prisma.parentLock.findMany({
        where: { status: 'ACTIVE' },
        select: { studentId: true },
        distinct: ['studentId'],
      }),
      this.prisma.device.count({ where: { revokedAt: null, lastSeenAt: { gte: phoneSince } } }),
      this.prisma.activityEvent.findMany({
        orderBy: { createdAt: 'desc' },
        take: 8,
        select: { id: true, kind: true, detail: true, userAgent: true, createdAt: true, user: { select: { id: true, name: true } }, actor: { select: { name: true } } },
      }),
    ]);
    const lockedStudents = new Set([...running.map((s) => s.studentId), ...parentLocked.map((l) => l.studentId)]);
    return {
      studying: running.map((s) => ({
        sessionId: s.id,
        student: s.student,
        subject: s.subject,
        topics: s.topics,
        status: s.status,
        startedAt: s.startedAt,
        plannedMinutes: s.plannedMinutes,
        studiedMinutes: this.sessions.studiedMinutes(s, now),
      })),
      lockedPhones: lockedStudents.size,
      phonesOnline,
      recent: recent.map((e) => ({ ...e, actor: e.actor?.name ?? null })),
    };
  }

  // ── accounts ───────────────────────────────────────────────────────────────

  async listUsers(query: UserListQuery) {
    const now = this.clock();
    const where: Prisma.UserWhereInput = {};
    if (query.role) where.role = query.role;
    if (query.status === 'disabled') where.disabledAt = { not: null };
    if (query.status === 'active') Object.assign(where, { disabledAt: null, verifiedAt: { not: null } });
    if (query.status === 'unverified') where.verifiedAt = null;
    const onlineSince = new Date(now.getTime() - ONLINE_MS);
    if (query.presence === 'online') where.lastActiveAt = { gte: onlineSince };
    if (query.presence === 'signedIn') where.sessions = { some: this.liveSessionWhere(now) };
    if (query.presence === 'signedOut') where.sessions = { none: this.liveSessionWhere(now) };
    const q = query.q?.trim();
    if (q) {
      // Postgres compares case-sensitively (SQLite does not): also try the usual spellings of a name.
      const title = q.toLowerCase().replace(/(^|\s)\p{L}/gu, (c) => c.toUpperCase());
      const names = [...new Set([q, q.toLowerCase(), q.toUpperCase(), title])];
      where.OR = [
        ...names.map((n) => ({ name: { contains: n } })),
        { email: { contains: q.toLowerCase() } },
        { phone: { contains: q } },
      ];
    }

    const [total, users] = await Promise.all([
      this.prisma.user.count({ where }),
      this.prisma.user.findMany({
        where,
        select: listSelect,
        orderBy: [{ lastActiveAt: { sort: 'desc', nulls: 'last' } }, { createdAt: 'desc' }],
        skip: (query.page - 1) * query.pageSize,
        take: query.pageSize,
      }),
    ]);

    const ids = users.map((u) => u.id);
    const [live, studies, phones] = await Promise.all([
      this.prisma.session.groupBy({ by: ['userId'], where: { userId: { in: ids }, ...this.liveSessionWhere(now) }, _count: { _all: true } }),
      this.prisma.studySession.findMany({ where: { studentId: { in: ids } }, select: studySelect }),
      this.prisma.device.groupBy({ by: ['studentId'], where: { studentId: { in: ids }, revokedAt: null }, _max: { lastSeenAt: true } }),
    ]);
    const liveBy = new Map(live.map((l) => [l.userId, l._count._all]));
    const phoneBy = new Map(phones.map((p) => [p.studentId, p._max.lastSeenAt]));
    const minutesBy = new Map<string, number>();
    for (const s of studies) minutesBy.set(s.studentId, (minutesBy.get(s.studentId) ?? 0) + this.sessions.studiedMinutes(s, now));

    return {
      total,
      page: query.page,
      pageSize: query.pageSize,
      users: users.map((u) => ({
        ...this.toListUser(u),
        presence: this.presence(u.lastActiveAt, liveBy.get(u.id) ?? 0, now),
        signedInDevices: liveBy.get(u.id) ?? 0,
        studyMinutes: minutesBy.get(u.id) ?? 0,
        /** Last sync from the student's phone (it syncs about every minute, even with the app closed). */
        phoneSeenAt: phoneBy.get(u.id) ?? null,
      })),
    };
  }

  async getUser(id: string) {
    const now = this.clock();
    const user = await this.prisma.user.findUnique({
      where: { id },
      select: {
        ...listSelect,
        otpChannel: true,
        emailVerifiedAt: true,
        phoneVerifiedAt: true,
        parentLinks: { select: { createdAt: true, parent: { select: { id: true, name: true, email: true, phone: true } } } },
        childLinks: { select: { createdAt: true, student: { select: { id: true, name: true, email: true, phone: true } } } },
        devices: {
          where: { revokedAt: null },
          select: { id: true, name: true, platform: true, appVersion: true, protectionOn: true, usageAccess: true, shortcutOn: true, lastSeenAt: true },
          orderBy: { lastSeenAt: 'desc' },
        },
        sessions: {
          where: this.liveSessionWhere(now),
          select: { id: true, userAgent: true, createdAt: true, expiresAt: true },
          orderBy: { createdAt: 'desc' },
        },
        studySessions: { orderBy: { startedAt: 'desc' } },
        exams: {
          select: { id: true, subject: true, source: true, status: true, score: true, totalMarks: true, passMarks: true, passed: true, submittedAt: true, createdAt: true },
          orderBy: { createdAt: 'desc' },
          take: 20,
        },
        locksOn: {
          where: { status: 'ACTIVE' },
          select: { id: true, title: true, lockedApps: true, createdAt: true, parent: { select: { name: true } } },
        },
        activity: {
          orderBy: { createdAt: 'desc' },
          take: 60,
          select: { id: true, kind: true, ip: true, userAgent: true, detail: true, createdAt: true, actor: { select: { name: true } } },
        },
      },
    });
    if (!user) throw notFound('That account does not exist.');
    const { parentLinks, childLinks, devices, sessions, studySessions, exams, locksOn, activity, ...rest } = user;

    const activeSession = studySessions.find((s) => s.status === 'STUDYING' || s.status === 'EXAM_PENDING');
    return {
      ...this.toListUser(rest),
      presence: this.presence(user.lastActiveAt, sessions.length, now),
      lastActiveAt: user.lastActiveAt,
      otpChannel: user.otpChannel,
      emailVerifiedAt: user.emailVerifiedAt,
      phoneVerifiedAt: user.phoneVerifiedAt,
      signedInDevices: sessions.map((s) => ({ id: s.id, userAgent: s.userAgent, signedInAt: s.createdAt })),
      parents: parentLinks.map((l) => ({ ...l.parent, linkedAt: l.createdAt })),
      children: childLinks.map((l) => ({ ...l.student, linkedAt: l.createdAt })),
      devices,
      study: this.studySummary(studySessions, now),
      sessions: studySessions.slice(0, 30).map((s) => ({
        id: s.id,
        subject: s.subject,
        topics: s.topics,
        plannedMinutes: s.plannedMinutes,
        studiedMinutes: this.sessions.studiedMinutes(s, now),
        status: s.status,
        adminUnlocked: s.adminUnlockedAt !== null,
        startedAt: s.startedAt,
      })),
      exams,
      lock: {
        locked: activeSession !== undefined || locksOn.length > 0,
        session: activeSession ? { id: activeSession.id, subject: activeSession.subject, status: activeSession.status, startedAt: activeSession.startedAt } : null,
        parentLocks: locksOn.map((l) => ({ id: l.id, title: l.title, by: l.parent.name, since: l.createdAt })),
      },
      activity: activity.map((a) => ({ ...a, actor: a.actor?.name ?? null })),
    };
  }

  /**
   * Disabling signs the account out everywhere at once (every refresh token is
   * revoked, and `requireAuth` refuses the account on its next request).
   */
  async setDisabled(adminId: string, id: string, disabled: boolean, context: ActivityContext) {
    if (id === adminId) throw new AppError(409, 'CANNOT_DISABLE_SELF', 'You cannot disable your own account.');
    const user = await this.manageable(id);

    const now = this.clock();
    await this.prisma.$transaction([
      this.prisma.user.update({ where: { id }, data: { disabledAt: disabled ? (user.disabledAt ?? now) : null } }),
      ...(disabled ? [this.revokeAll(id, now)] : []),
    ]);
    await this.activity.record(id, disabled ? 'ADMIN_DISABLED' : 'ADMIN_ENABLED', { ...context, actorId: adminId });
    return this.getUser(id);
  }

  /** Ends every session of the account: each phone or browser must sign in again. */
  async signOutEverywhere(adminId: string, id: string, context: ActivityContext) {
    await this.manageable(id);
    const { count } = await this.revokeAll(id, this.clock());
    await this.activity.record(id, 'ADMIN_SIGNED_OUT', { ...context, actorId: adminId, detail: `${count} session(s) ended` });
    return this.getUser(id);
  }

  /** Sets a new random password, shown to the admin once, and signs the account out everywhere. */
  async resetPassword(adminId: string, id: string, context: ActivityContext): Promise<{ password: string }> {
    await this.manageable(id);
    const password = readablePassword();
    await this.prisma.$transaction([
      this.prisma.user.update({ where: { id }, data: { passwordHash: await hashPassword(password) } }),
      this.revokeAll(id, this.clock()),
    ]);
    await this.activity.record(id, 'ADMIN_PASSWORD_RESET', { ...context, actorId: adminId });
    return { password };
  }

  /**
   * Owner's override: ends every lock on the student's phone without an exam (the
   * running study session and any parent locks). The time already studied still
   * counts. The student and their parents are told, and the action is logged.
   * Phones pick the change up on their next sync (about a minute).
   */
  async unlockPhone(adminId: string, id: string, reason: string | undefined, context: ActivityContext) {
    const user = await this.prisma.user.findUnique({ where: { id }, select: { id: true, role: true, name: true } });
    if (!user) throw notFound('That account does not exist.');
    if (user.role !== 'STUDENT') throw new AppError(409, 'NOT_A_STUDENT', 'Only a student’s phone can be locked.');

    const now = this.clock();
    const active = await this.prisma.studySession.findMany({
      where: { studentId: id, status: { in: ['STUDYING', 'EXAM_PENDING'] } },
      select: { id: true, startedAt: true, plannedMinutes: true, studyEndedAt: true },
    });
    const results = await this.prisma.$transaction([
      ...active.map((s) =>
        this.prisma.studySession.update({
          where: { id: s.id },
          data: {
            status: 'CANCELLED',
            adminUnlockedAt: now,
            completedAt: now,
            studyEndedAt: s.studyEndedAt ?? new Date(Math.min(now.getTime(), s.startedAt.getTime() + s.plannedMinutes * MINUTE)),
          },
        }),
      ),
      // A running exam for these locks can no longer unlock anything.
      this.prisma.exam.updateMany({ where: { studentId: id, status: 'ACTIVE' }, data: { status: 'EXPIRED', activeKey: null } }),
      this.prisma.parentLock.updateMany({ where: { studentId: id, status: 'ACTIVE' }, data: { status: 'CANCELLED', endedAt: now } }),
    ]);
    const parentLocks = results.at(-1) as Prisma.BatchPayload;

    const ended = active.length + parentLocks.count;
    const detail = [`${ended} lock(s) ended`, reason?.trim()].filter(Boolean).join(': ');
    await this.activity.record(id, 'ADMIN_UNLOCKED', { ...context, actorId: adminId, detail });
    if (ended > 0) {
      await this.notifications.notify([id], 'ADMIN_UNLOCK', 'Your phone is unlocked', 'Support unlocked your apps.');
      await this.notifications.notifyParents(
        id,
        'ADMIN_UNLOCK',
        `${user.name}'s phone was unlocked`,
        'Support unlocked the apps without an exam.',
      );
    }
    return { endedSessions: active.length, endedParentLocks: parentLocks.count, user: await this.getUser(id) };
  }

  // ── study time ─────────────────────────────────────────────────────────────

  /** Who studied how long, and what, in the last [days] days (0 = all time). */
  async study(days: number) {
    const now = this.clock();
    const since = days > 0 ? new Date(now.getTime() - days * DAY_MS) : undefined;
    const [students, rows] = await Promise.all([
      this.prisma.user.findMany({
        where: { role: 'STUDENT' },
        select: { id: true, name: true, email: true, phone: true, lastActiveAt: true, disabledAt: true },
      }),
      this.prisma.studySession.findMany({ where: since ? { startedAt: { gte: since } } : {}, select: studySelect }),
    ]);

    const byStudent = new Map<string, StudyRow[]>();
    for (const r of rows) byStudent.set(r.studentId, [...(byStudent.get(r.studentId) ?? []), r]);
    const subjects = new Map<string, { subject: string; minutes: number; sessions: number; students: Set<string> }>();
    for (const r of rows) {
      const s = subjects.get(r.subject) ?? { subject: r.subject, minutes: 0, sessions: 0, students: new Set<string>() };
      s.minutes += this.sessions.studiedMinutes(r, now);
      s.sessions++;
      s.students.add(r.studentId);
      subjects.set(r.subject, s);
    }

    const table = students
      .map((st) => {
        const summary = this.studySummary(byStudent.get(st.id) ?? [], now);
        return {
          id: st.id,
          name: st.name,
          contact: st.email ?? st.phone,
          disabled: st.disabledAt !== null,
          minutes: summary.totalMinutes,
          sessions: summary.sessions,
          lastStudiedAt: summary.lastStudiedAt,
          subjects: summary.bySubject,
        };
      })
      .sort((a, b) => b.minutes - a.minutes || a.name.localeCompare(b.name));

    return {
      days,
      totalMinutes: table.reduce((sum, s) => sum + s.minutes, 0),
      students: table,
      subjects: [...subjects.values()]
        .map((s) => ({ subject: s.subject, minutes: s.minutes, sessions: s.sessions, students: s.students.size }))
        .sort((a, b) => b.minutes - a.minutes),
    };
  }

  // ── activity log ───────────────────────────────────────────────────────────

  async activityLog(query: ActivityQuery) {
    const where: Prisma.ActivityEventWhereInput = {};
    if (query.userId) where.userId = query.userId;
    if (query.kind) where.kind = query.kind;
    const [total, events] = await Promise.all([
      this.prisma.activityEvent.count({ where }),
      this.prisma.activityEvent.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (query.page - 1) * query.pageSize,
        take: query.pageSize,
        select: {
          id: true,
          kind: true,
          ip: true,
          userAgent: true,
          detail: true,
          createdAt: true,
          user: { select: { id: true, name: true, role: true } },
          actor: { select: { name: true } },
        },
      }),
    ]);
    return {
      total,
      page: query.page,
      pageSize: query.pageSize,
      events: events.map((e) => ({ ...e, actor: e.actor?.name ?? null })),
    };
  }

  // ── settings ───────────────────────────────────────────────────────────────

  settings(): Promise<Settings> {
    return this.config.get();
  }

  async updateSettings(adminId: string, patch: Partial<Settings>, context: ActivityContext): Promise<Settings> {
    const next = await this.config.update(patch);
    await this.activity.record(adminId, 'ADMIN_SETTINGS', { ...context, actorId: adminId, detail: Object.keys(patch).join(', ') });
    return next;
  }

  /**
   * A separate sign-in for the admin panel opened from the app, so the panel and
   * the app never share (and rotate) one refresh token.
   */
  panelSession(adminId: string, userAgent?: string): Promise<AuthTokens> {
    return this.tokens.issue({ id: adminId, role: 'ADMIN' }, userAgent ? `${userAgent} (admin panel)` : 'admin panel');
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  private liveSessionWhere(now: Date): Prisma.SessionWhereInput {
    return { revokedAt: null, replacedAt: null, expiresAt: { gt: now } };
  }

  private revokeAll(userId: string, now: Date) {
    return this.prisma.session.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: now } });
  }

  private presence(lastActiveAt: Date | null, liveSessions: number, now: Date): Presence {
    if (lastActiveAt && now.getTime() - lastActiveAt.getTime() < ONLINE_MS && liveSessions > 0) return 'online';
    return liveSessions > 0 ? 'signedIn' : 'signedOut';
  }

  /** Admin accounts are managed from the server, never from the panel. */
  private async manageable(id: string) {
    const user = await this.prisma.user.findUnique({ where: { id }, select: { id: true, role: true, disabledAt: true } });
    if (!user) throw notFound('That account does not exist.');
    if (user.role === 'ADMIN') throw new AppError(409, 'CANNOT_MANAGE_ADMIN', 'Admin accounts are managed from the server.');
    return user;
  }

  private studySummary(rows: Pick<StudySession, 'subject' | 'startedAt' | 'plannedMinutes' | 'studyEndedAt' | 'status' | 'adminUnlockedAt'>[], now: Date) {
    const todayStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
    const weekAgo = new Date(now.getTime() - 7 * DAY_MS);
    const bySubject = new Map<string, { subject: string; minutes: number; sessions: number }>();
    let total = 0;
    let today = 0;
    let week = 0;
    let last: Date | null = null;
    for (const r of rows) {
      const minutes = this.sessions.studiedMinutes(r, now);
      total += minutes;
      if (r.startedAt >= todayStart) today += minutes;
      if (r.startedAt >= weekAgo) week += minutes;
      if (!last || r.startedAt > last) last = r.startedAt;
      const s = bySubject.get(r.subject) ?? { subject: r.subject, minutes: 0, sessions: 0 };
      s.minutes += minutes;
      s.sessions++;
      bySubject.set(r.subject, s);
    }
    return {
      totalMinutes: total,
      todayMinutes: today,
      weekMinutes: week,
      sessions: rows.length,
      lastStudiedAt: last,
      bySubject: [...bySubject.values()].sort((a, b) => b.minutes - a.minutes),
    };
  }

  private toListUser(u: Prisma.UserGetPayload<{ select: typeof listSelect }>) {
    return {
      id: u.id,
      role: u.role,
      name: u.name,
      email: u.email,
      phone: u.phone,
      dateOfBirth: u.dateOfBirth,
      verified: u.verifiedAt !== null,
      disabled: u.disabledAt !== null,
      lastActiveAt: u.lastActiveAt,
      createdAt: u.createdAt,
      counts: {
        sessions: u._count.studySessions,
        exams: u._count.exams,
        parents: u._count.parentLinks,
        children: u._count.childLinks,
      },
    };
  }
}
