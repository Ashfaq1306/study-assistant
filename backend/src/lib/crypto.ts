import {
  createHash,
  createHmac,
  randomBytes,
  randomInt,
  scrypt as scryptCb,
  timingSafeEqual,
  type BinaryLike,
  type ScryptOptions,
} from 'node:crypto';

const scrypt = (password: BinaryLike, salt: BinaryLike, keylen: number, options: ScryptOptions) =>
  new Promise<Buffer>((resolve, reject) => {
    scryptCb(password, salt, keylen, options, (err, key) => (err ? reject(err) : resolve(key)));
  });

// OWASP-recommended scrypt cost (N=2^15, r=8, p=1), about 32 MiB per hash.
const SCRYPT = { N: 2 ** 15, r: 8, p: 1, keylen: 64, maxmem: 64 * 1024 * 1024 } as const;

/** Hash format: `scrypt$N$r$p$<salt>$<hash>` (base64url) so parameters can be raised later. */
export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const key = await scrypt(password.normalize('NFKC'), salt, SCRYPT.keylen, SCRYPT);
  return [
    'scrypt',
    SCRYPT.N,
    SCRYPT.r,
    SCRYPT.p,
    salt.toString('base64url'),
    key.toString('base64url'),
  ].join('$');
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const [scheme, n, r, p, salt, hash] = stored.split('$');
  if (scheme !== 'scrypt' || !n || !r || !p || !salt || !hash) return false;
  const expected = Buffer.from(hash, 'base64url');
  const actual = await scrypt(
    password.normalize('NFKC'),
    Buffer.from(salt, 'base64url'),
    expected.length,
    { N: Number(n), r: Number(r), p: Number(p), maxmem: SCRYPT.maxmem },
  );
  return timingSafeEqual(actual, expected);
}

export const randomToken = (bytes = 32): string => randomBytes(bytes).toString('base64url');

export const sha256 = (value: string): string => createHash('sha256').update(value).digest('hex');

export const hmac = (secret: string, value: string): string =>
  createHmac('sha256', secret).update(value).digest('hex');

export function safeEqual(a: string, b: string): boolean {
  const left = Buffer.from(a);
  const right = Buffer.from(b);
  return left.length === right.length && timingSafeEqual(left, right);
}

/** Uniformly random 6-digit code, zero-padded. */
export const generateOtp = (): string => randomInt(0, 1_000_000).toString().padStart(6, '0');

// Crockford base32: no I, L, O or U, so codes are easy to read aloud and type.
const PAIRING_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
export const PAIRING_CODE_LENGTH = 8;

export function generatePairingCode(): string {
  let code = '';
  for (let i = 0; i < PAIRING_CODE_LENGTH; i++) {
    code += PAIRING_ALPHABET[randomInt(PAIRING_ALPHABET.length)];
  }
  return code;
}

/** Accepts what a person might type ("abcd-efgh", "ABCD EFGH", O for 0) and returns the canonical code. */
export const normalizePairingCode = (input: string): string =>
  input.toUpperCase().replace(/[\s-]/g, '').replace(/O/g, '0').replace(/[IL]/g, '1');

export const formatPairingCode = (code: string): string => `${code.slice(0, 4)}-${code.slice(4)}`;
