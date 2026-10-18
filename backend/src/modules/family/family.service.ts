import { Prisma, type PrismaClient, type Role, type User } from '@prisma/client';
import { ageOn } from '../../lib/age.js';
import {
  formatPairingCode,
  generatePairingCode,
  hmac,
  normalizePairingCode,
  PAIRING_CODE_LENGTH,
} from '../../lib/crypto.js';
import { AppError, forbidden, notFound } from '../../lib/errors.js';
import type { Clock } from '../../lib/clock.js';
import type { UsersService } from '../users/users.service.js';

export const PAIRING_CODE_TTL_MS = 10 * 60_000;
export const MAX_PARENTS_PER_STUDENT = 4;
/** QR payload the parent's app recognises. Also works as a deep link later. */
export const PAIRING_URI_PREFIX = 'studyassistant://pair?code=';

export interface FamilyLinkView {
  id: string;
  linkedAt: string;
  person: { id: string; name: string; role: Role; age: number };
}

const SERIALIZABLE = { isolationLevel: Prisma.TransactionIsolationLevel.Serializable };

const tooManyParents = () =>
  new AppError(409, 'TOO_MANY_PARENTS', `A student can have at most ${MAX_PARENTS_PER_STUDENT} parents linked.`);

/** A serializable transaction lost a race: ask the client to try again. */
const retryableConflict = (err: unknown): unknown =>
  err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2034'
    ? new AppError(409, 'CONFLICT', 'Something changed at the same time. Please try again.')
    : err;

const invalidCode = () =>
  new AppError(400, 'PAIRING_CODE_INVALID', 'This code is wrong or has expired. Ask for a new QR code.');

export class FamilyService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly users: UsersService,
    private readonly secret: string,
    private readonly clock: Clock,
  ) {}

  /** A student creates a code to show as a QR; any older unused code stops working. */
  async createPairingCode(student: User): Promise<{ code: string; qrPayload: string; expiresAt: string }> {
    const now = this.clock();
    const code = generatePairingCode();
    const expiresAt = new Date(now.getTime() + PAIRING_CODE_TTL_MS);
    await this.prisma.$transaction([
      this.prisma.pairingCode.deleteMany({ where: { studentId: student.id, consumedAt: null } }),
      this.prisma.pairingCode.create({
        data: { studentId: student.id, codeHash: this.hash(code), expiresAt, createdAt: now },
      }),
    ]);
    return {
      code: formatPairingCode(code),
      qrPayload: `${PAIRING_URI_PREFIX}${code}`,
      expiresAt: expiresAt.toISOString(),
    };
  }

  /** A parent redeems a student's code (scanned or typed) to link the two accounts. */
  async linkParent(parent: User, rawCode: string): Promise<FamilyLinkView> {
    const code = normalizePairingCode(rawCode.replace(PAIRING_URI_PREFIX, ''));
    if (code.length !== PAIRING_CODE_LENGTH) throw invalidCode();

    const now = this.clock();
    const pairing = await this.prisma.pairingCode.findUnique({
      where: { codeHash: this.hash(code) },
      include: { student: { include: { _count: { select: { parentLinks: true } } } } },
    });
    if (!pairing || pairing.consumedAt || pairing.expiresAt <= now || pairing.student.disabledAt) {
      throw invalidCode();
    }
    if (pairing.student.id === parent.id) throw invalidCode();
    if (pairing.student._count.parentLinks >= MAX_PARENTS_PER_STUDENT) throw tooManyParents();

    try {
      const link = await this.prisma.$transaction(async (tx) => {
        const { count } = await tx.pairingCode.updateMany({
          where: { id: pairing.id, consumedAt: null },
          data: { consumedAt: now },
        });
        if (count === 0) throw invalidCode();
        // Re-count inside the transaction so parallel links cannot exceed the limit.
        const linked = await tx.familyLink.count({ where: { studentId: pairing.studentId } });
        if (linked >= MAX_PARENTS_PER_STUDENT) throw tooManyParents();
        return tx.familyLink.create({ data: { parentId: parent.id, studentId: pairing.studentId, createdAt: now } });
      }, SERIALIZABLE);
      return this.view(link.id, link.createdAt, pairing.student);
    } catch (err) {
      if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
        throw new AppError(409, 'ALREADY_LINKED', `You are already linked with ${pairing.student.name}.`);
      }
      throw retryableConflict(err);
    }
  }

  async listLinks(user: User): Promise<FamilyLinkView[]> {
    if (user.role === 'STUDENT') {
      const links = await this.prisma.familyLink.findMany({
        where: { studentId: user.id },
        include: { parent: true },
        orderBy: { createdAt: 'asc' },
      });
      return links.map((l) => this.view(l.id, l.createdAt, l.parent));
    }
    const links = await this.prisma.familyLink.findMany({
      where: { parentId: user.id },
      include: { student: true },
      orderBy: { createdAt: 'asc' },
    });
    return links.map((l) => this.view(l.id, l.createdAt, l.student));
  }

  /**
   * Parents can always unlink. A student can unlink only if they are old
   * enough not to need parental control, or another parent stays linked.
   */
  async unlink(user: User, linkId: string): Promise<void> {
    const link = await this.prisma.familyLink.findUnique({ where: { id: linkId }, include: { student: true } });
    if (!link || (link.parentId !== user.id && link.studentId !== user.id)) {
      throw notFound('Link not found.');
    }
    const studentMustKeepOne = link.studentId === user.id && this.users.requiresParentalControl(link.student);
    try {
      await this.prisma.$transaction(async (tx) => {
        await tx.familyLink.delete({ where: { id: link.id } });
        // Counted after deleting, in one serializable transaction, so two
        // parallel unlinks cannot both pass and leave no parent.
        if (studentMustKeepOne && (await tx.familyLink.count({ where: { studentId: link.studentId } })) === 0) {
          throw forbidden('Students under 15 must keep at least one parent linked.');
        }
      }, SERIALIZABLE);
    } catch (err) {
      if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2025') throw notFound('Link not found.');
      throw retryableConflict(err);
    }
  }

  private view(id: string, linkedAt: Date, person: User): FamilyLinkView {
    return {
      id,
      linkedAt: linkedAt.toISOString(),
      person: {
        id: person.id,
        name: person.name,
        role: person.role,
        age: ageOn(person.dateOfBirth, this.clock()),
      },
    };
  }

  private hash(code: string): string {
    return hmac(this.secret, `pairing:${code}`);
  }
}
