import type { PrismaClient, User } from '@prisma/client';
import { z } from 'zod';
import { ageOn } from '../../lib/age.js';
import { AppError } from '../../lib/errors.js';
import type { Clock } from '../../lib/clock.js';
import { AiUnavailableError, type AiProvider } from '../ai/ai.types.js';
import type { ConfigService } from '../config/config.service.js';
import type { ExamsService } from '../exams/exams.service.js';
import type { SessionsService } from '../sessions/sessions.service.js';

export const TutorBody = z.object({
  messages: z
    .array(
      z.discriminatedUnion('role', [
        z.object({ role: z.literal('user'), content: z.string().trim().min(1).max(2000) }),
        // Replies can be long; the app sends them back as history.
        z.object({ role: z.literal('assistant'), content: z.string().trim().min(1).max(8000) }),
      ]),
    )
    .min(1)
    .max(20)
    .refine((m) => m[0]?.role === 'user' && m.at(-1)?.role === 'user', 'Start and end with a student message.'),
});

const DAY_MS = 24 * 3_600_000;

export class TutorService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly ai: AiProvider,
    private readonly config: ConfigService,
    private readonly sessions: SessionsService,
    private readonly exams: ExamsService,
    private readonly clock: Clock,
  ) {}

  async reply(student: User, input: z.infer<typeof TutorBody>): Promise<{ reply: string; remainingToday: number }> {
    await this.sessions.assertStudyAllowed(student);
    const settings = await this.config.get();
    if (!settings.aiEnabled || this.ai.source !== 'AI') {
      throw new AppError(503, 'AI_OFF', 'The AI study helper is not switched on yet.');
    }
    if (await this.exams.hasRunningExam(student.id)) {
      throw new AppError(409, 'EXAM_IN_PROGRESS', 'The study helper takes a break while your exam is open. Good luck!');
    }

    const session = await this.sessions.findActive(student.id);
    const now = this.clock();
    // Take a slot first and count after (ours included), so parallel requests cannot all slip under the limit.
    const slot = await this.prisma.aiUsage.create({ data: { userId: student.id, kind: 'TUTOR', createdAt: now } });
    const used = await this.prisma.aiUsage.count({
      where: { userId: student.id, kind: 'TUTOR', createdAt: { gt: new Date(now.getTime() - DAY_MS) } },
    });
    if (used > settings.tutorDailyLimit) {
      await this.prisma.aiUsage.delete({ where: { id: slot.id } });
      throw new AppError(429, 'TUTOR_LIMIT', "You've used all your questions for today. Come back tomorrow!");
    }

    let reply: string;
    try {
      reply = await this.ai.tutor(input.messages, {
        name: student.name.split(/\s+/)[0] ?? student.name,
        age: ageOn(student.dateOfBirth, now),
        subject: session?.subject,
        topics: session?.topics,
      });
    } catch (err) {
      // A failed answer does not use up a question.
      await this.prisma.aiUsage.delete({ where: { id: slot.id } }).catch(() => undefined);
      if (err instanceof AiUnavailableError) throw new AppError(503, 'AI_UNAVAILABLE', err.message);
      throw err;
    }
    return { reply, remainingToday: Math.max(0, settings.tutorDailyLimit - used) };
  }
}
