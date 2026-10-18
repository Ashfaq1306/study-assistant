const BANGLA_DIGITS = '০১২৩৪৫৬৭৮৯';

/** Converts Bangla digits to ASCII so "০১৭১২৩৪৫৬৭৮" is understood. */
const toAsciiDigits = (s: string): string =>
  s.replace(/[০-৯]/g, (d) => String(BANGLA_DIGITS.indexOf(d)));

/**
 * Normalises a phone number to E.164.
 * Bangladeshi local numbers (01XXXXXXXXX) get +880; anything else must already
 * be international (+<country><number> or 00<country><number>).
 * Returns null when the input is not a usable number.
 */
export function normalizePhone(input: string): string | null {
  const cleaned = toAsciiDigits(input.trim()).replace(/[\s\-().]/g, '');
  if (/^01[3-9]\d{8}$/.test(cleaned)) return `+88${cleaned}`;
  if (/^8801[3-9]\d{8}$/.test(cleaned)) return `+${cleaned}`;
  if (/^00[1-9]\d{7,14}$/.test(cleaned)) return `+${cleaned.slice(2)}`;
  if (/^\+[1-9]\d{7,14}$/.test(cleaned)) return cleaned;
  return null;
}

/** "+8801712345678" → "+880•••••••678" */
export const maskPhone = (e164: string): string =>
  `${e164.slice(0, 4)}${'•'.repeat(Math.max(0, e164.length - 7))}${e164.slice(-3)}`;

/** "rahim@example.com" → "ra•••@example.com" */
export function maskEmail(email: string): string {
  const [local = '', domain = ''] = email.split('@');
  const visible = local.slice(0, local.length <= 2 ? 1 : 2);
  return `${visible}${'•'.repeat(Math.max(1, local.length - visible.length))}@${domain}`;
}
