import type { FastifyPluginAsync } from 'fastify';
import type { ConfigService } from './config.service.js';

/** Public, read-only settings the app needs before and after sign-in. */
export const configRoutes =
  (config: ConfigService): FastifyPluginAsync =>
  async (app) => {
    app.get('/', async () => {
      const s = await config.get();
      return {
        subjects: s.subjects,
        minPassPercent: s.minPassPercent,
        minStudyMinutes: s.minStudyMinutes,
        maxStudyMinutes: s.maxStudyMinutes,
        earlyFinishPercent: s.earlyFinishPercent,
        maxQuestions: s.maxQuestions,
        examRetryCooldownSeconds: s.examRetryCooldownSeconds,
        aiEnabled: s.aiEnabled,
        announcement: s.announcement,
      };
    });
  };
