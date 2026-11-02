import type { Device, PrismaClient } from '@prisma/client';
import { z } from 'zod';
import { packageName } from '../sessions/sessions.schemas.js';

/** Screen time a phone reports: up to the last 7 days, by the phone's local date. */
export const UsageReport = z
  .array(
    z.object({
      day: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
      apps: z
        .array(
          z.object({
            package: packageName.refine((p) => p !== '*'),
            minutes: z.number().int().min(0).max(1440),
          }),
        )
        .max(500),
    }),
  )
  .max(8);
export type UsageReport = z.infer<typeof UsageReport>;

export interface ScreenTimeDay {
  day: string;
  totalMinutes: number;
  apps: { package: string; label: string; minutes: number }[];
}

/** Keeps only the most used apps per day; the rest is in the total. */
const TOP_APPS = 20;

export class UsageService {
  constructor(private readonly prisma: PrismaClient) {}

  async record(device: Device, report: UsageReport): Promise<void> {
    for (const { day, apps } of report) {
      const used = apps.filter((a) => a.minutes > 0).sort((a, b) => b.minutes - a.minutes);
      const totalMinutes = Math.min(
        1440,
        used.reduce((sum, a) => sum + a.minutes, 0),
      );
      const top = JSON.stringify(used.slice(0, TOP_APPS));
      await this.prisma.usageDay.upsert({
        where: { deviceId_day: { deviceId: device.id, day } },
        create: { studentId: device.studentId, deviceId: device.id, day, totalMinutes, apps: top },
        update: { totalMinutes, apps: top },
      });
    }
  }

  /** The student's screen time across their phones, newest day first, with app names. */
  async forStudent(studentId: string, days: string[]): Promise<ScreenTimeDay[]> {
    const rows = await this.prisma.usageDay.findMany({
      where: { studentId, day: { in: days }, device: { revokedAt: null } },
      include: { device: { select: { installedApps: true } } },
    });
    const labels = new Map<string, string>();
    for (const row of rows) {
      for (const app of JSON.parse(row.device.installedApps) as { package: string; label: string }[]) {
        labels.set(app.package, app.label);
      }
    }
    return days.map((day) => {
      const perApp = new Map<string, number>();
      let totalMinutes = 0;
      for (const row of rows.filter((r) => r.day === day)) {
        totalMinutes += row.totalMinutes;
        for (const app of JSON.parse(row.apps) as { package: string; minutes: number }[]) {
          perApp.set(app.package, (perApp.get(app.package) ?? 0) + app.minutes);
        }
      }
      const apps = [...perApp]
        .map(([pkg, minutes]) => ({ package: pkg, label: labels.get(pkg) ?? pkg.split('.').pop() ?? pkg, minutes }))
        .sort((a, b) => b.minutes - a.minutes);
      return { day, totalMinutes: Math.min(totalMinutes, 1440), apps };
    });
  }
}
