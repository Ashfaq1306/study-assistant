import { execSync } from 'node:child_process';
import { rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const TEST_DB_URL = 'file:./test.db';
// SQLite paths in DATABASE_URL are relative to prisma/schema.prisma.
const TEST_DB_FILE = fileURLToPath(new URL('../prisma/test.db', import.meta.url));

/** Builds a fresh, throwaway SQLite database for this test run. Never touches dev.db. */
export default function setup(): void {
  rmSync(TEST_DB_FILE, { force: true });
  rmSync(`${TEST_DB_FILE}-journal`, { force: true });
  execSync('npx prisma db push --skip-generate', {
    stdio: 'pipe',
    env: { ...process.env, DATABASE_URL: TEST_DB_URL },
  });
}
