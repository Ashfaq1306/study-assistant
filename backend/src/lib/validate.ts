import { z } from 'zod';
import { AppError } from './errors.js';

/** Parses untrusted input, turning schema failures into a 400 with per-field messages. */
export function parse<T extends z.ZodType>(schema: T, input: unknown): z.infer<T> {
  const result = schema.safeParse(input);
  if (!result.success) {
    throw new AppError(400, 'VALIDATION_FAILED', 'Please check the highlighted fields.', {
      fields: z.flattenError(result.error).fieldErrors,
    });
  }
  return result.data;
}
