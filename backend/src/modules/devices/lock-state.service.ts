import type { PrismaClient } from '@prisma/client';
import type { SessionsService } from '../sessions/sessions.service.js';

export interface LockReason {
  kind: 'SESSION' | 'PARENT';
  id: string;
  title: string;
  status: string;
}

/** What a student's phones must block right now. The server is the source of truth. */
export interface DeviceLockState {
  locked: boolean;
  /** Block every app except the always-allowed ones (phone, keyboard, launcher, this app). */
  wholePhone: boolean;
  packages: string[];
  /** Also block Settings, Play Store and the uninstaller while locked. */
  strict: boolean;
  reasons: LockReason[];
}

export class LockStateService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly sessions: SessionsService,
  ) {}

  async forStudent(studentId: string): Promise<DeviceLockState> {
    const packages = new Set<string>();
    const reasons: LockReason[] = [];
    let strict = false;
    let wholePhone = false;

    const add = (lockedApps: string) => {
      for (const app of JSON.parse(lockedApps) as string[]) {
        if (app === '*') wholePhone = true;
        else packages.add(app);
      }
    };

    const session = await this.sessions.findActive(studentId);
    if (session) {
      add(session.lockedApps);
      strict ||= session.strict;
      reasons.push({
        kind: 'SESSION',
        id: session.id,
        title: `${session.subject}: ${session.topics}`,
        status: session.status,
      });
    }

    const parentLocks = await this.prisma.parentLock.findMany({
      where: { studentId, status: 'ACTIVE' },
      orderBy: { createdAt: 'asc' },
    });
    for (const lock of parentLocks) {
      add(lock.lockedApps);
      strict ||= lock.strict;
      reasons.push({ kind: 'PARENT', id: lock.id, title: lock.title, status: lock.status });
    }

    const locked = wholePhone || packages.size > 0;
    return { locked, wholePhone, packages: [...packages].sort(), strict: locked && strict, reasons };
  }
}
