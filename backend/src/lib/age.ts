/** Students younger than this must be linked to a parent before using the app. */
export const PARENTAL_CONTROL_AGE = 15;
export const MIN_STUDENT_AGE = 5;
export const MIN_PARENT_AGE = 18;
export const MAX_AGE = 120;

/** Whole years between `dateOfBirth` and `today`, using UTC calendar dates. */
export function ageOn(dateOfBirth: Date, today: Date): number {
  let age = today.getUTCFullYear() - dateOfBirth.getUTCFullYear();
  const monthDiff = today.getUTCMonth() - dateOfBirth.getUTCMonth();
  if (monthDiff < 0 || (monthDiff === 0 && today.getUTCDate() < dateOfBirth.getUTCDate())) age--;
  return age;
}

/** Parses a strict `YYYY-MM-DD` date as UTC midnight; null for impossible dates like 2025-02-30. */
export function parseIsoDate(value: string): Date | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return null;
  const [y, m, d] = [Number(match[1]), Number(match[2]), Number(match[3])];
  const date = new Date(Date.UTC(y, m - 1, d));
  const valid =
    date.getUTCFullYear() === y && date.getUTCMonth() === m - 1 && date.getUTCDate() === d;
  return valid ? date : null;
}

export const toIsoDate = (date: Date): string => date.toISOString().slice(0, 10);
