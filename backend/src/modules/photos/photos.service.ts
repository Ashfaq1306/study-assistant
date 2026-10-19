import type { PrismaClient, User } from '@prisma/client';
import { z } from 'zod';
import { AppError, notFound } from '../../lib/errors.js';
import type { Clock } from '../../lib/clock.js';

/** Enough to cover a few book pages; each photo is compressed on the phone. */
export const MAX_PHOTOS_PER_SESSION = 4;
const MAX_PHOTO_BYTES = 1_500_000;
export const PHOTO_BODY_LIMIT = 2_200_000;

export const PhotoBody = z.object({
  mime: z.enum(['image/jpeg', 'image/png', 'image/webp']),
  /** Base64 of the image file. */
  data: z.string().min(100).max(Math.ceil((MAX_PHOTO_BYTES * 4) / 3) + 4),
});

export interface PhotoFile {
  mime: string;
  data: Buffer;
}

/** Checks the file really is the image type it claims to be. */
export function looksLike(mime: string, bytes: Buffer): boolean {
  if (mime === 'image/jpeg') return bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  if (mime === 'image/png') return bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
  return bytes.subarray(0, 4).toString('latin1') === 'RIFF' && bytes.subarray(8, 12).toString('latin1') === 'WEBP';
}

/** Photos of the study material. The student and their linked parents can see them. */
export class PhotosService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly clock: Clock,
  ) {}

  /** Adds a photo while the student is still studying (the exam uses them). */
  async add(student: User, sessionId: string, input: z.infer<typeof PhotoBody>): Promise<{ id: string; photoIds: string[] }> {
    const data = Buffer.from(input.data, 'base64');
    if (data.length > MAX_PHOTO_BYTES || !looksLike(input.mime, data)) {
      throw new AppError(400, 'BAD_PHOTO', 'That photo could not be used. Try taking it again.');
    }
    return this.prisma.$transaction(async (tx) => {
      const session = await tx.studySession.findUnique({ where: { id: sessionId } });
      if (!session || session.studentId !== student.id) throw notFound('Session not found.');
      if (session.status !== 'STUDYING') {
        throw new AppError(409, 'SESSION_NOT_STUDYING', 'Photos can be added while you are studying.');
      }
      const ids = JSON.parse(session.photoIds) as string[];
      if (ids.length >= MAX_PHOTOS_PER_SESSION) {
        throw new AppError(409, 'TOO_MANY_PHOTOS', `You can add up to ${MAX_PHOTOS_PER_SESSION} photos.`);
      }
      const photo = await tx.studyPhoto.create({
        data: { studentId: student.id, sessionId, mime: input.mime, data, createdAt: this.clock() },
      });
      const photoIds = [...ids, photo.id];
      // Guarded on the list we read, so two uploads at once cannot exceed the limit.
      const { count } = await tx.studySession.updateMany({
        where: { id: sessionId, photoIds: session.photoIds },
        data: { photoIds: JSON.stringify(photoIds) },
      });
      if (count === 0) throw new AppError(409, 'TRY_AGAIN', 'Another photo was being added. Please try again.');
      return { id: photo.id, photoIds };
    });
  }

  async remove(student: User, sessionId: string, photoId: string): Promise<{ photoIds: string[] }> {
    return this.prisma.$transaction(async (tx) => {
      const session = await tx.studySession.findUnique({ where: { id: sessionId } });
      if (!session || session.studentId !== student.id) throw notFound('Session not found.');
      if (session.status !== 'STUDYING') {
        throw new AppError(409, 'SESSION_NOT_STUDYING', 'Photos can be changed while you are studying.');
      }
      const photoIds = (JSON.parse(session.photoIds) as string[]).filter((id) => id !== photoId);
      await tx.studyPhoto.deleteMany({ where: { id: photoId, sessionId } });
      await tx.studySession.update({ where: { id: sessionId }, data: { photoIds: JSON.stringify(photoIds) } });
      return { photoIds };
    });
  }

  /** The photo file, for its student or a parent linked to them. */
  async file(viewer: User, photoId: string): Promise<PhotoFile> {
    const photo = await this.prisma.studyPhoto.findUnique({ where: { id: photoId } });
    if (!photo) throw notFound('Photo not found.');
    if (photo.studentId !== viewer.id) {
      const linked =
        viewer.role === 'PARENT' &&
        (await this.prisma.familyLink.count({ where: { parentId: viewer.id, studentId: photo.studentId } })) > 0;
      if (!linked) throw notFound('Photo not found.');
    }
    return { mime: photo.mime, data: Buffer.from(photo.data) };
  }

  /** The session's photos, for writing the exam from them. */
  async forExam(sessionId: string): Promise<{ mediaType: 'image/jpeg' | 'image/png' | 'image/webp'; data: string }[]> {
    const photos = await this.prisma.studyPhoto.findMany({
      where: { sessionId },
      orderBy: { createdAt: 'asc' },
      take: MAX_PHOTOS_PER_SESSION,
    });
    return photos.map((p) => ({
      mediaType: p.mime as 'image/jpeg' | 'image/png' | 'image/webp',
      data: Buffer.from(p.data).toString('base64'),
    }));
  }
}
