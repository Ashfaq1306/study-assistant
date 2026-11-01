/* eslint-disable no-console -- a command-line tool talks to the terminal. */
/**
 * Manages admin accounts from the server (admins can't be made from the app or the panel).
 *
 *   npm run admin -- create <email> "<name>"   new admin; prints a one-time random password
 *   npm run admin -- promote <email>           an existing verified account becomes an admin
 *   npm run admin -- reset-password <email>    new random password for an admin
 *   npm run admin -- list
 */
import { PrismaClient } from '@prisma/client';
import { hashPassword, randomToken } from '../lib/crypto.js';

const prisma = new PrismaClient();

const usage = () => {
  console.error('Usage: npm run admin -- create <email> "<name>" | promote <email> | reset-password <email> | list');
  process.exit(2);
};

/** 18 random characters: long enough that it never needs complexity rules. */
const newPassword = () => randomToken(14).slice(0, 18);

async function main(): Promise<void> {
  const [command, rawEmail, name] = process.argv.slice(2);
  const email = rawEmail?.trim().toLowerCase();

  switch (command) {
    case 'create': {
      if (!email || !name) usage();
      if (await prisma.user.findUnique({ where: { email } })) {
        throw new Error(`${email} already has an account: use "promote" instead.`);
      }
      const password = newPassword();
      const now = new Date();
      await prisma.user.create({
        data: {
          role: 'ADMIN',
          name: name!.trim(),
          email,
          passwordHash: await hashPassword(password),
          // Not used for admins, but the column is required.
          dateOfBirth: new Date('1990-01-01T00:00:00Z'),
          otpChannel: 'EMAIL',
          verifiedAt: now,
          emailVerifiedAt: now,
        },
      });
      console.log(`Admin created: ${email}\nPassword (shown once, keep it safe): ${password}`);
      return;
    }
    case 'promote': {
      if (!email) usage();
      const user = await prisma.user.findUnique({ where: { email } });
      if (!user?.verifiedAt) throw new Error(`No verified account for ${email}.`);
      await prisma.user.update({ where: { id: user.id }, data: { role: 'ADMIN', disabledAt: null } });
      console.log(`${email} is now an admin (it was a ${user.role.toLowerCase()} account).`);
      return;
    }
    case 'reset-password': {
      if (!email) usage();
      const user = await prisma.user.findUnique({ where: { email } });
      if (user?.role !== 'ADMIN') throw new Error(`${email} is not an admin.`);
      const password = newPassword();
      await prisma.$transaction([
        prisma.user.update({ where: { id: user.id }, data: { passwordHash: await hashPassword(password) } }),
        prisma.session.updateMany({ where: { userId: user.id, revokedAt: null }, data: { revokedAt: new Date() } }),
      ]);
      console.log(`New password for ${email} (shown once): ${password}`);
      return;
    }
    case 'list': {
      const admins = await prisma.user.findMany({ where: { role: 'ADMIN' }, select: { email: true, name: true, disabledAt: true } });
      for (const a of admins) console.log(`${a.email}\t${a.name}${a.disabledAt ? '\t(disabled)' : ''}`);
      if (admins.length === 0) console.log('No admins yet.');
      return;
    }
    default:
      usage();
  }
}

main()
  .catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
