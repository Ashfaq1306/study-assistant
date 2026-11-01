/* eslint-disable no-console -- a command-line tool talks to the terminal. */
/**
 * Sends one test email with the SMTP settings in .env, so a wrong password shows up here
 * and not when a student is waiting for a code.
 *
 *   npm run email:check -- you@example.com
 */
import { loadEnv } from '../config/env.js';
import { SmtpEmailNotifier } from '../modules/notify/notifier.js';

async function main(): Promise<void> {
  const to = process.argv[2];
  if (!to?.includes('@')) {
    console.error('Usage: npm run email:check -- you@example.com');
    process.exit(2);
  }
  // Only the email settings matter here; dummy secrets let a half-finished .env load.
  const env = loadEnv({
    JWT_SECRET: 'x'.repeat(32),
    OTP_SECRET: 'x'.repeat(32),
    ...process.env,
    NODE_ENV: 'development',
    EMAIL_PROVIDER: 'smtp',
  });
  await new SmtpEmailNotifier(env).send({
    channel: 'EMAIL',
    to,
    subject: 'Study Assistant: email works',
    text: 'This is a test from your Study Assistant server. One-time codes will arrive like this.',
  });
  console.log(`Sent a test email to ${to}.`);
}

main().catch((error: unknown) => {
  console.error(`Email failed: ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
});
