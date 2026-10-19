import type { z } from 'zod';
import { AppError } from './errors.js';

/**
 * Parses untrusted input, turning schema failures into a 400 with per-field
 * messages keyed by dotted path (e.g. "exam.passMarks"); the first message per
 * field wins.
 */
export function parse<T extends z.ZodType>(schema: T, input: unknown): z.infer<T> {
  const result = schema.safeParse(input);
  if (!result.success) {
    const fields: Record<string, string[]> = {};
    for (const issue of result.error.issues) {
      const key = issue.path.length > 0 ? issue.path.join('.') : '_form';
      (fields[key] ??= []).push(issue.message);
    }
    throw new AppError(400, 'VALIDATION_FAILED', 'Please check the highlighted fields.', { fields });
  }
  return result.data;
}
