import type { FastifyPluginAsync } from 'fastify';
import { parse } from '../../lib/validate.js';
import { type ActivityService, requestContext } from '../activity/activity.service.js';
import type { AuthService } from './auth.service.js';
import {
  ForgotPasswordBody,
  LoginBody,
  RefreshBody,
  RegisterBody,
  ResendVerificationBody,
  ResetPasswordBody,
  VerifyAccountBody,
} from './auth.schemas.js';

/** Stricter per-IP limit for endpoints that send messages or check secrets. */
const sensitive = { rateLimit: { max: 10, timeWindow: '1 minute' } };

export const authRoutes =
  (auth: AuthService, activity: ActivityService): FastifyPluginAsync =>
  async (app) => {
    app.post('/register', { config: sensitive }, async (request, reply) => {
      const body = parse(RegisterBody, request.body);
      return reply.code(201).send(await auth.register(body));
    });

    app.post('/verify', { config: sensitive }, async (request) => {
      const { userId, code } = parse(VerifyAccountBody, request.body);
      const signedIn = await auth.verifyAccount(userId, code, request.headers['user-agent']);
      await activity.record(signedIn.user.id, 'SIGNUP', requestContext(request));
      return signedIn;
    });

    app.post('/verify/resend', { config: sensitive }, async (request) => {
      const { userId, channel } = parse(ResendVerificationBody, request.body);
      return auth.resendVerification(userId, channel);
    });

    app.post('/login', { config: sensitive }, async (request) => {
      const { identifier, password } = parse(LoginBody, request.body);
      const signedIn = await auth.login(identifier, password, request.headers['user-agent']);
      await activity.record(signedIn.user.id, 'LOGIN', requestContext(request));
      return signedIn;
    });

    app.post('/password/forgot', { config: sensitive }, async (request) => {
      const { identifier } = parse(ForgotPasswordBody, request.body);
      return auth.forgotPassword(identifier);
    });

    app.post('/password/reset', { config: sensitive }, async (request) => {
      const { identifier, code, newPassword } = parse(ResetPasswordBody, request.body);
      const signedIn = await auth.resetPassword(identifier, code, newPassword, request.headers['user-agent']);
      await activity.record(signedIn.user.id, 'PASSWORD_RESET', requestContext(request));
      return signedIn;
    });

    app.post('/refresh', async (request) => {
      const { refreshToken } = parse(RefreshBody, request.body);
      return auth.refresh(refreshToken, request.headers['user-agent']);
    });

    app.post('/logout', async (request, reply) => {
      const { refreshToken } = parse(RefreshBody, request.body);
      const userId = await auth.logout(refreshToken);
      if (userId) await activity.record(userId, 'LOGOUT', requestContext(request));
      return reply.code(204).send();
    });
  };
