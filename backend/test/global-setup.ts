import { execSync } from 'node:child_process';
import { rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

// SQLite paths in DATABASE_URL are relative to prisma/schema.prisma.
const TEST_DB_FILE = fileURLToPath(new URL('../prisma/test.db', import.meta.url));

/**
 * Builds a fresh, throwaway database for this test run. Never touches dev.db.
 * By default a SQLite file; CI also runs the suite on Postgres by setting TEST_DATABASE_URL
 * (after `node scripts/prisma-provider.mjs postgresql`).
 */
export default function setup(): void {
  const url = process.env.TEST_DATABASE_URL;
  if (url?.startsWith('postgres')) {
    execSync('npx prisma db push --skip-generate --force-reset', { stdio: 'pipe', env: { ...process.env, DATABASE_URL: url } });
    return;
  }
  rmSync(TEST_DB_FILE, { force: true });
  rmSync(`${TEST_DB_FILE}-journal`, { force: true });
  execSync('npx prisma db push --skip-generate', {
    stdio: 'pipe',
    env: { ...process.env, DATABASE_URL: 'file:./test.db' },
  });
}
