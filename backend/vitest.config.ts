import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globalSetup: ['./test/global-setup.ts'],
    env: {
      NODE_ENV: 'test',
      DATABASE_URL: 'file:./test.db',
    },
    // Test files share one SQLite database, so run them one at a time.
    fileParallelism: false,
  },
});
