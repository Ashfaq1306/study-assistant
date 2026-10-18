import type { PrismaClient } from '@prisma/client';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { currentUser, requireAuth } from '../../plugins/auth-guard.js';
import { parse } from '../../lib/validate.js';
import type { UsersService } from './users.service.js';

const UpdateMeBody = z.object({ name: z.string().trim().min(2, 'Enter your name.').max(60) });

export const usersRoutes =
  (prisma: PrismaClient, users: UsersService): FastifyPluginAsync =>
  async (app) => {
    app.addHook('preHandler', requireAuth(prisma));

    app.get('/', async (request) => users.getProfile(currentUser(request).id));

    app.patch('/', async (request) => {
      const { name } = parse(UpdateMeBody, request.body);
      return users.updateName(currentUser(request).id, name);
    });
  };
