import { describe, expect, it } from 'vitest';
import { ageOn, parseIsoDate } from '../src/lib/age.js';
import {
  formatPairingCode,
  generateOtp,
  generatePairingCode,
  hashPassword,
  normalizePairingCode,
  verifyPassword,
} from '../src/lib/crypto.js';
import { maskEmail, maskPhone, normalizePhone } from '../src/lib/phone.js';

describe('normalizePhone', () => {
  it.each([
    ['01712345678', '+8801712345678'],
    ['017-1234-5678', '+8801712345678'],
    ['8801712345678', '+8801712345678'],
    ['+8801712345678', '+8801712345678'],
    ['০১৭১২৩৪৫৬৭৮', '+8801712345678'],
    ['00447911123456', '+447911123456'],
    ['+14155552671', '+14155552671'],
  ])('%s → %s', (input, expected) => {
    expect(normalizePhone(input)).toBe(expected);
  });

  it.each(['', '12345', '01212345678', 'not a number', '+0123456789'])('rejects %s', (input) => {
    expect(normalizePhone(input)).toBeNull();
  });
});

describe('masking', () => {
  it('hides the middle of phone numbers and emails', () => {
    expect(maskPhone('+8801712345678')).toBe('+880•••••••678');
    expect(maskEmail('rahim@example.com')).toBe('ra•••@example.com');
    expect(maskEmail('a@example.com')).toBe('a•@example.com');
  });
});

describe('age', () => {
  const today = new Date('2026-06-01T00:00:00Z');

  it('counts whole years, birthday not yet reached', () => {
    expect(ageOn(new Date('2011-06-02T00:00:00Z'), today)).toBe(14);
    expect(ageOn(new Date('2011-06-01T00:00:00Z'), today)).toBe(15);
  });

  it('parses only real calendar dates', () => {
    expect(parseIsoDate('2012-02-29')?.toISOString()).toBe('2012-02-29T00:00:00.000Z');
    expect(parseIsoDate('2013-02-29')).toBeNull();
    expect(parseIsoDate('2013-13-01')).toBeNull();
    expect(parseIsoDate('01/02/2013')).toBeNull();
  });
});

describe('codes', () => {
  it('generates 6-digit OTPs', () => {
    for (let i = 0; i < 50; i++) expect(generateOtp()).toMatch(/^\d{6}$/);
  });

  it('generates readable pairing codes and normalises typed input', () => {
    const code = generatePairingCode();
    expect(code).toMatch(/^[0-9A-HJKMNP-TV-Z]{8}$/);
    expect(normalizePairingCode(formatPairingCode(code).toLowerCase())).toBe(code);
    expect(normalizePairingCode('ab0o il1-xyz')).toBe('AB00111XYZ');
  });
});

describe('password hashing', () => {
  it('verifies the right password only', async () => {
    const hash = await hashPassword('correct horse 1');
    expect(hash.startsWith('scrypt$')).toBe(true);
    await expect(verifyPassword('correct horse 1', hash)).resolves.toBe(true);
    await expect(verifyPassword('wrong horse 1', hash)).resolves.toBe(false);
    await expect(verifyPassword('anything', 'garbage')).resolves.toBe(false);
  });
});
