import type { Device, PrismaClient } from '@prisma/client';
import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { currentUser, requireAuth } from '../../plugins/auth-guard.js';
import { parse } from '../../lib/validate.js';
import { HeartbeatBody, RegisterDeviceBody, type DevicesService } from './devices.service.js';

declare module 'fastify' {
  interface FastifyRequest {
    device?: Device;
  }
}

const DeviceParams = z.object({ id: z.string().min(1) });

/** /v1/devices: a signed-in student manages their phones. */
export const devicesRoutes =
  (prisma: PrismaClient, devices: DevicesService): FastifyPluginAsync =>
  async (app) => {
    app.addHook('preHandler', requireAuth(prisma, ['STUDENT']));

    app.post('/', async (request, reply) => {
      const body = parse(RegisterDeviceBody, request.body);
      return reply.code(201).send(await devices.register(currentUser(request), body));
    });

    app.get('/', async (request) => ({ devices: await devices.list(currentUser(request).id) }));

    app.delete('/:id', async (request, reply) => {
      const { id } = parse(DeviceParams, request.params);
      await devices.revoke(currentUser(request).id, id);
      return reply.code(204).send();
    });
  };

/** /v1/device: the phone itself, authenticated by its X-Device-Token. */
export const deviceSyncRoutes =
  (devices: DevicesService): FastifyPluginAsync =>
  async (app) => {
    app.addHook('preHandler', async (request: FastifyRequest) => {
      const header = request.headers['x-device-token'];
      request.device = await devices.authenticate(Array.isArray(header) ? header[0] : header);
    });

    app.get('/state', async (request) => devices.state(request.device!));

    app.post('/heartbeat', async (request) => {
      const body = parse(HeartbeatBody, request.body);
      return devices.heartbeat(request.device!, body);
    });
  };
