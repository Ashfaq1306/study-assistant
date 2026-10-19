import type { Notification, PrismaClient } from '@prisma/client';
import type { Clock } from '../../lib/clock.js';

export type NotificationKind =
  | 'EXAM_PASSED'
  | 'EXAM_FAILED'
  | 'LOCK_PASSED'
  | 'SESSION_STARTED'
  | 'PROTECTION_OFF'
  | 'PARENT_LOCK';

export interface NotificationView {
  id: string;
  kind: string;
  title: string;
  body: string;
  data: Record<string, string>;
  read: boolean;
  createdAt: string;
}

/** Notifications older than this are cleaned up when new ones arrive. */
const KEEP_DAYS = 60;

/** In-app alerts. Parents hear about exams, locks and protection; students about parent locks. */
export class NotificationsService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly clock: Clock,
  ) {}

  async notify(
    userIds: string[],
    kind: NotificationKind,
    title: string,
    body: string,
    data: Record<string, string> = {},
  ): Promise<void> {
    if (userIds.length === 0) return;
    const now = this.clock();
    await this.prisma.notification.createMany({
      data: userIds.map((userId) => ({ userId, kind, title, body, data: JSON.stringify(data), createdAt: now })),
    });
    await this.prisma.notification.deleteMany({
      where: { userId: { in: userIds }, createdAt: { lt: new Date(now.getTime() - KEEP_DAYS * 86_400_000) } },
    });
  }

  /** Tells every parent linked to the student. */
  async notifyParents(
    studentId: string,
    kind: NotificationKind,
    title: string,
    body: string,
    data: Record<string, string> = {},
  ): Promise<void> {
    const links = await this.prisma.familyLink.findMany({ where: { studentId }, select: { parentId: true } });
    await this.notify(
      links.map((l) => l.parentId),
      kind,
      title,
      body,
      { studentId, ...data },
    );
  }

  async list(userId: string, limit: number): Promise<{ notifications: NotificationView[]; unread: number }> {
    const [rows, unread] = await Promise.all([
      this.prisma.notification.findMany({ where: { userId }, orderBy: { createdAt: 'desc' }, take: limit }),
      this.prisma.notification.count({ where: { userId, readAt: null } }),
    ]);
    return { notifications: rows.map(toView), unread };
  }

  /** Marks the given notifications (or all of them) as read. */
  async markRead(userId: string, ids?: string[]): Promise<void> {
    await this.prisma.notification.updateMany({
      where: { userId, readAt: null, ...(ids ? { id: { in: ids } } : {}) },
      data: { readAt: this.clock() },
    });
  }
}

function toView(n: Notification): NotificationView {
  return {
    id: n.id,
    kind: n.kind,
    title: n.title,
    body: n.body,
    data: JSON.parse(n.data) as Record<string, string>,
    read: n.readAt !== null,
    createdAt: n.createdAt.toISOString(),
  };
}
