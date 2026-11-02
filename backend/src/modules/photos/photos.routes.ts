import type { PrismaClient } from '@prisma/client';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { currentUser, requireAuth } from '../../plugins/auth-guard.js';
import { parse } from '../../lib/validate.js';
import { PHOTO_BODY_LIMIT, PhotoBody, type PhotosService } from './photos.service.js';

const SessionParams = z.object({ id: z.string().min(1) });
const PhotoParams = z.object({ id: z.string().min(1), photoId: z.string().min(1) });
const FileParams = z.object({ photoId: z.string().min(1) });

/** /v1/sessions/:id/photos: a student adds or removes photos of what they are studying. */
export const sessionPhotosRoutes =
  (prisma: PrismaClient, photos: PhotosService): FastifyPluginAsync =>
  async (app) => {
    app.addHook('preHandler', requireAuth(prisma, ['STUDENT']));

    app.post('/:id/photos', { bodyLimit: PHOTO_BODY_LIMIT }, async (request, reply) => {
      const { id } = parse(SessionParams, request.params);
      const body = parse(PhotoBody, request.body);
      return reply.code(201).send(await photos.add(currentUser(request), id, body));
    });

    app.delete('/:id/photos/:photoId', async (request) => {
      const { id, photoId } = parse(PhotoParams, request.params);
      return photos.remove(currentUser(request), id, photoId);
    });
  };

/** /v1/photos/:photoId: the image, for its student and their linked parents. */
export const photoFileRoutes =
  (prisma: PrismaClient, photos: PhotosService): FastifyPluginAsync =>
  async (app) => {
    app.addHook('preHandler', requireAuth(prisma));

    app.get('/:photoId', async (request, reply) => {
      const { photoId } = parse(FileParams, request.params);
      const file = await photos.file(currentUser(request), photoId);
      return reply
        .header('content-type', file.mime)
        .header('cache-control', 'private, max-age=86400')
        .header('x-content-type-options', 'nosniff')
        .send(file.data);
    });
  };
