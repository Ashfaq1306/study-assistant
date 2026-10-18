import nodemailer, { type Transporter } from 'nodemailer';
import type { FastifyBaseLogger } from 'fastify';
import type { Env } from '../../config/env.js';

export type OutboundMessage =
  | { channel: 'EMAIL'; to: string; subject: string; text: string; html?: string }
  | { channel: 'SMS'; to: string; text: string };

/** Delivers one-time codes and notices. Swap implementations per environment. */
export interface Notifier {
  send(message: OutboundMessage): Promise<void>;
}

/** Development only: prints the message to the server log instead of sending it. */
export class ConsoleNotifier implements Notifier {
  constructor(private readonly log: FastifyBaseLogger) {}

  send(message: OutboundMessage): Promise<void> {
    this.log.warn({ channel: message.channel, to: message.to, text: message.text }, 'DEV OTP (not sent)');
    return Promise.resolve();
  }
}

export class SmtpEmailNotifier implements Notifier {
  private readonly transport: Transporter;

  constructor(private readonly env: Env) {
    this.transport = nodemailer.createTransport({
      host: env.SMTP_HOST,
      port: env.SMTP_PORT,
      secure: env.SMTP_PORT === 465,
      auth: env.SMTP_USER ? { user: env.SMTP_USER, pass: env.SMTP_PASS } : undefined,
    });
  }

  async send(message: OutboundMessage): Promise<void> {
    if (message.channel !== 'EMAIL') throw new Error('SmtpEmailNotifier only sends email');
    await this.transport.sendMail({
      from: this.env.SMTP_FROM,
      to: message.to,
      subject: message.subject,
      text: message.text,
      html: message.html,
    });
  }
}

export class TwilioSmsNotifier implements Notifier {
  constructor(
    private readonly accountSid: string,
    private readonly authToken: string,
    private readonly from: string,
  ) {}

  async send(message: OutboundMessage): Promise<void> {
    if (message.channel !== 'SMS') throw new Error('TwilioSmsNotifier only sends SMS');
    const res = await fetch(
      `https://api.twilio.com/2010-04-01/Accounts/${this.accountSid}/Messages.json`,
      {
        method: 'POST',
        headers: {
          Authorization: `Basic ${Buffer.from(`${this.accountSid}:${this.authToken}`).toString('base64')}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({ To: message.to, From: this.from, Body: message.text }),
        signal: AbortSignal.timeout(10_000),
      },
    );
    if (!res.ok) throw new Error(`Twilio responded ${res.status}: ${await res.text()}`);
  }
}

/** Routes each message to the email or SMS provider. */
export class ChannelNotifier implements Notifier {
  constructor(
    private readonly email: Notifier,
    private readonly sms: Notifier,
  ) {}

  send(message: OutboundMessage): Promise<void> {
    return message.channel === 'EMAIL' ? this.email.send(message) : this.sms.send(message);
  }
}

export function createNotifier(env: Env, log: FastifyBaseLogger): Notifier {
  const consoleNotifier = new ConsoleNotifier(log);
  const email = env.EMAIL_PROVIDER === 'smtp' ? new SmtpEmailNotifier(env) : consoleNotifier;
  const sms =
    env.SMS_PROVIDER === 'twilio'
      ? new TwilioSmsNotifier(env.TWILIO_ACCOUNT_SID!, env.TWILIO_AUTH_TOKEN!, env.TWILIO_FROM!)
      : consoleNotifier;
  return new ChannelNotifier(email, sms);
}
