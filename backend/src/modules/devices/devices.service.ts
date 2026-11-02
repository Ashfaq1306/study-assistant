import type { Device, PrismaClient, User } from '@prisma/client';
import { z } from 'zod';
import { randomToken, sha256 } from '../../lib/crypto.js';
import { AppError, notFound } from '../../lib/errors.js';
import type { Clock } from '../../lib/clock.js';
import { packageName } from '../sessions/sessions.schemas.js';
import type { NotificationsService } from '../notifications/notifications.service.js';
import type { DeviceLockState, LockStateService } from './lock-state.service.js';
import { UsageReport, type UsageService } from './usage.service.js';

export const RegisterDeviceBody = z.object({
  name: z.string().trim().min(1).max(80),
  platform: z.enum(['android', 'ios']),
  appVersion: z.string().trim().max(40).optional(),
  /** The token this phone held for another account: that registration is retired. */
  previousDeviceToken: z.string().min(1).max(200).optional(),
});

export const HeartbeatBody = z.object({
  protectionOn: z.boolean(),
  usageAccess: z.boolean().default(false),
  shortcutOn: z.boolean().default(false),
  appVersion: z.string().trim().max(40).optional(),
  installedApps: z
    .array(z.object({ package: packageName.refine((p) => p !== '*'), label: z.string().trim().min(1).max(80) }))
    .max(1000)
    .optional(),
  usage: UsageReport.optional(),
});

export interface DeviceView {
  id: string;
  name: string;
  platform: string;
  appVersion: string | null;
  protectionOn: boolean;
  usageAccess: boolean;
  shortcutOn: boolean;
  lastSeenAt: string;
  installedApps: { package: string; label: string }[];
}

const unauthorizedDevice = () =>
  new AppError(401, 'DEVICE_UNAUTHORIZED', 'This phone is not registered. Please sign in again.');

export class DevicesService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly lockState: LockStateService,
    private readonly usage: UsageService,
    private readonly notifications: NotificationsService,
    private readonly clock: Clock,
  ) {}

  /** Issues a device token. Only its hash is stored. */
  async register(
    student: User,
    input: z.infer<typeof RegisterDeviceBody>,
  ): Promise<{ deviceId: string; deviceToken: string }> {
    if (input.previousDeviceToken) await this.retire(input.previousDeviceToken, student.id);
    const deviceToken = randomToken(32);
    const device = await this.prisma.device.create({
      data: {
        studentId: student.id,
        tokenHash: sha256(deviceToken),
        name: input.name,
        platform: input.platform,
        appVersion: input.appVersion,
        lastSeenAt: this.clock(),
      },
    });
    return { deviceId: device.id, deviceToken };
  }

  async authenticate(token: string | undefined): Promise<Device> {
    if (!token || token.length > 200) throw unauthorizedDevice();
    const device = await this.prisma.device.findUnique({
      where: { tokenHash: sha256(token) },
      include: { student: { select: { disabledAt: true } } },
    });
    if (!device || device.revokedAt || device.student.disabledAt) throw unauthorizedDevice();
    return device;
  }

  state(device: Device): Promise<DeviceLockState> {
    return this.lockState.forStudent(device.studentId);
  }

  async heartbeat(device: Device, input: z.infer<typeof HeartbeatBody>): Promise<DeviceLockState> {
    const wasProtected = device.protectionOn && !device.shortcutOn;
    const nowProtected = input.protectionOn && !input.shortcutOn;
    await this.prisma.device.update({
      where: { id: device.id },
      data: {
        protectionOn: input.protectionOn,
        usageAccess: input.usageAccess,
        shortcutOn: input.shortcutOn,
        appVersion: input.appVersion ?? device.appVersion,
        ...(input.installedApps ? { installedApps: JSON.stringify(input.installedApps) } : {}),
        lastSeenAt: this.clock(),
      },
    });
    if (input.usage) await this.usage.record(device, input.usage);
    if (wasProtected && !nowProtected) {
      const student = await this.prisma.user.findUnique({ where: { id: device.studentId }, select: { name: true } });
      await this.notifications.notifyParents(
        device.studentId,
        'PROTECTION_OFF',
        'App lock was switched off',
        `App lock is off on ${student?.name ?? 'your child'}'s phone (${device.name}). Locks can't be enforced until it is back on.`,
        { deviceId: device.id },
      );
    }
    return this.state(device);
  }

  /**
   * Retires the registration a handed-over phone held for another account, so
   * it stops showing as that account's phone. Never while that account is locked.
   */
  private async retire(previousToken: string, newOwnerId: string): Promise<void> {
    const old = await this.prisma.device.findUnique({ where: { tokenHash: sha256(previousToken) } });
    if (!old || old.revokedAt || old.studentId === newOwnerId) return;
    if ((await this.lockState.forStudent(old.studentId)).locked) {
      throw new AppError(409, 'LOCK_ACTIVE', "This phone is locked for another student until they pass their exam.");
    }
    await this.prisma.device.update({ where: { id: old.id }, data: { revokedAt: this.clock() } });
  }

  async list(studentId: string): Promise<DeviceView[]> {
    const devices = await this.prisma.device.findMany({
      where: { studentId, revokedAt: null },
      orderBy: { lastSeenAt: 'desc' },
    });
    return devices.map(toView);
  }

  /** Not while a lock is running: removing the phone would end the lock without an exam. */
  async revoke(studentId: string, deviceId: string): Promise<void> {
    if ((await this.lockState.forStudent(studentId)).locked) {
      throw new AppError(409, 'LOCK_ACTIVE', 'You can remove this phone after your locked apps are unlocked.');
    }
    const { count } = await this.prisma.device.updateMany({
      where: { id: deviceId, studentId, revokedAt: null },
      data: { revokedAt: this.clock() },
    });
    if (count === 0) throw notFound('Device not found.');
  }
}

export function toView(d: Device): DeviceView {
  return {
    id: d.id,
    name: d.name,
    platform: d.platform,
    appVersion: d.appVersion,
    protectionOn: d.protectionOn,
    usageAccess: d.usageAccess,
    shortcutOn: d.shortcutOn,
    lastSeenAt: d.lastSeenAt.toISOString(),
    installedApps: JSON.parse(d.installedApps) as { package: string; label: string }[],
  };
}
