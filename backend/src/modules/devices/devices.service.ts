import type { Device, PrismaClient, User } from '@prisma/client';
import { z } from 'zod';
import { randomToken, sha256 } from '../../lib/crypto.js';
import { AppError, notFound } from '../../lib/errors.js';
import type { Clock } from '../../lib/clock.js';
import { packageName } from '../sessions/sessions.schemas.js';
import type { DeviceLockState, LockStateService } from './lock-state.service.js';

export const RegisterDeviceBody = z.object({
  name: z.string().trim().min(1).max(80),
  platform: z.enum(['android', 'ios']),
  appVersion: z.string().trim().max(40).optional(),
});

export const HeartbeatBody = z.object({
  protectionOn: z.boolean(),
  usageAccess: z.boolean().default(false),
  appVersion: z.string().trim().max(40).optional(),
  installedApps: z
    .array(z.object({ package: packageName.refine((p) => p !== '*'), label: z.string().trim().min(1).max(80) }))
    .max(1000)
    .optional(),
});

export interface DeviceView {
  id: string;
  name: string;
  platform: string;
  appVersion: string | null;
  protectionOn: boolean;
  usageAccess: boolean;
  lastSeenAt: string;
  installedApps: { package: string; label: string }[];
}

const unauthorizedDevice = () =>
  new AppError(401, 'DEVICE_UNAUTHORIZED', 'This phone is not registered. Please sign in again.');

export class DevicesService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly lockState: LockStateService,
    private readonly clock: Clock,
  ) {}

  /** Issues a device token. Only its hash is stored. */
  async register(
    student: User,
    input: z.infer<typeof RegisterDeviceBody>,
  ): Promise<{ deviceId: string; deviceToken: string }> {
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
    await this.prisma.device.update({
      where: { id: device.id },
      data: {
        protectionOn: input.protectionOn,
        usageAccess: input.usageAccess,
        appVersion: input.appVersion ?? device.appVersion,
        ...(input.installedApps ? { installedApps: JSON.stringify(input.installedApps) } : {}),
        lastSeenAt: this.clock(),
      },
    });
    return this.state(device);
  }

  async list(studentId: string): Promise<DeviceView[]> {
    const devices = await this.prisma.device.findMany({
      where: { studentId, revokedAt: null },
      orderBy: { lastSeenAt: 'desc' },
    });
    return devices.map(toView);
  }

  async revoke(studentId: string, deviceId: string): Promise<void> {
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
    lastSeenAt: d.lastSeenAt.toISOString(),
    installedApps: JSON.parse(d.installedApps) as { package: string; label: string }[],
  };
}
