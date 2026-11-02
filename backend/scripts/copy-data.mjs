// Copies every row from one database to another, for moving to a new host.
//
//   1. node scripts/copy-data.mjs export data.json          (Prisma client generated for the SOURCE, e.g. SQLite)
//   2. node scripts/prisma-provider.mjs postgresql && npx prisma generate
//   3. DATABASE_URL=<target> npx prisma db push --skip-generate
//   4. DATABASE_URL=<target> node scripts/copy-data.mjs import data.json
//
// The target must be empty. Rows are inserted parents first, so foreign keys hold.
// The export file contains all user data: delete it when done.
import { readFileSync, writeFileSync } from 'node:fs';
import { Prisma, PrismaClient } from '@prisma/client';

/** Parents before children. */
const ORDER = [
  'User', 'AppSetting', 'OtpSend', 'OtpCode', 'Session', 'PairingCode', 'FamilyLink', 'QuestionSet',
  'ParentLock', 'StudySession', 'StudyPhoto', 'Exam', 'Device', 'UsageDay', 'Notification',
  'CalendarEvent', 'AiUsage', 'ContentReport', 'ActivityEvent',
];

const models = Prisma.dmmf.datamodel.models;
const missing = models.map((m) => m.name).filter((n) => !ORDER.includes(n));
if (missing.length) throw new Error(`Add these models to ORDER: ${missing.join(', ')}`);
const delegate = (prisma, name) => prisma[name.charAt(0).toLowerCase() + name.slice(1)];
const bytesFields = (name) => models.find((m) => m.name === name).fields.filter((f) => f.type === 'Bytes').map((f) => f.name);

const [mode, file] = process.argv.slice(2);
if (!['export', 'import'].includes(mode) || !file) {
  console.error('Usage: node scripts/copy-data.mjs export|import <file.json>');
  process.exit(2);
}
const prisma = new PrismaClient();
try {
  if (mode === 'export') {
    const out = {};
    for (const name of ORDER) {
      const rows = await delegate(prisma, name).findMany();
      const bytes = bytesFields(name);
      out[name] = rows.map((r) => {
        for (const f of bytes) if (r[f]) r[f] = { $bytes: Buffer.from(r[f]).toString('base64') };
        return r;
      });
      console.log(`${name}: ${rows.length}`);
    }
    writeFileSync(file, JSON.stringify(out));
  } else {
    const data = JSON.parse(readFileSync(file, 'utf8'));
    for (const name of ORDER) {
      const existing = await delegate(prisma, name).count();
      if (existing > 0) throw new Error(`${name} already has ${existing} rows: the target must be empty.`);
    }
    for (const name of ORDER) {
      const rows = (data[name] ?? []).map((r) => {
        for (const [k, v] of Object.entries(r)) if (v && typeof v === 'object' && '$bytes' in v) r[k] = Buffer.from(v.$bytes, 'base64');
        return r;
      });
      for (let i = 0; i < rows.length; i += 500) {
        await delegate(prisma, name).createMany({ data: rows.slice(i, i + 500) });
      }
      console.log(`${name}: ${rows.length} copied`);
    }
  }
} finally {
  await prisma.$disconnect();
}
