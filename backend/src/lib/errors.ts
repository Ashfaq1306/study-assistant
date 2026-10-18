/**
 * An expected, client-facing failure. Anything else that is thrown is treated
 * as a bug: logged, and returned as a generic 500.
 *
 * Responses always have the shape `{ error: { code, message, details? } }`.
 * Clients branch on `code`; `message` is safe to show to the user.
 */
export class AppError extends Error {
  constructor(
    readonly statusCode: number,
    readonly code: string,
    message: string,
    readonly details?: Record<string, unknown>,
  ) {
    super(message);
    this.name = 'AppError';
  }
}

export const unauthorized = (message = 'Please sign in again.') =>
  new AppError(401, 'UNAUTHORIZED', message);

export const forbidden = (message = 'You are not allowed to do that.') =>
  new AppError(403, 'FORBIDDEN', message);

export const notFound = (message = 'Not found.') => new AppError(404, 'NOT_FOUND', message);
