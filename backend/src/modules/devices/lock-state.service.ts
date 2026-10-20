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
  constructor(private readonly sessions: SessionsService) {}

  async forStudent(studentId: string): Promise<DeviceLockState> {
    const packages = new Set<string>();
    const reasons: LockReason[] = [];
    let strict = false;
    let wholePhone = false;

    const session = await this.sessions.findActive(studentId);
    if (session) {
      const apps = JSON.parse(session.lockedApps) as string[];
      for (const app of apps) {
        if (app === '*') wholePhone = true;
        else packages.add(app);
      }
      strict ||= session.strict;
      reasons.push({
        kind: 'SESSION',
        id: session.id,
        title: `${session.subject}: ${session.topics}`,
        status: session.status,
      });
    }

    const locked = wholePhone || packages.size > 0;
    return { locked, wholePhone, packages: [...packages].sort(), strict: locked && strict, reasons };
  }
}
