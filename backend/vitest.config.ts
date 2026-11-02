import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globalSetup: ['./test/global-setup.ts'],
    env: {
      NODE_ENV: 'test',
      // SQLite by default; CI also sets a throwaway Postgres (see test/global-setup.ts).
      DATABASE_URL: process.env.TEST_DATABASE_URL ?? 'file:./test.db',
    },
    // Test files share one database, so run them one at a time.
    fileParallelism: false,
  },
});
