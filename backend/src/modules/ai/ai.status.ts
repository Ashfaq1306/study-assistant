import type { FastifyBaseLogger } from 'fastify';
import type { Clock } from '../../lib/clock.js';
import type { AiHealthState, AiProvider } from './ai.types.js';

export interface AiStatus {
  state: AiHealthState;
  model: string | null;
  /** When the AI was last asked; null before the first check. */
  checkedAt: Date | null;
}

/** Re-check at most this often when asked on demand (the Control Room's "Check now"). */
const MIN_GAP_MS = 10_000;

/**
 * Knows whether the AI actually answers, by sending it a tiny request now and then. Without
 * this, a revoked or expired key only shows up when a student's exam fails to generate.
 * The result is safe to show anyone: a state and a model name, never the key.
 */
export class AiStatusService {
  private status: AiStatus;
  private running: Promise<AiStatus> | null = null;

  constructor(
    private readonly ai: AiProvider,
    private readonly clock: Clock,
    private readonly log: FastifyBaseLogger,
  ) {
    this.status = { state: ai.check ? 'UNCHECKED' : 'NOT_CONFIGURED', model: null, checkedAt: null };
  }

  get current(): AiStatus {
    return this.status;
  }

  /** Asks the AI now (shared by concurrent callers; skipped if it was asked a moment ago). */
  async refresh(force = false): Promise<AiStatus> {
    const check = this.ai.check?.bind(this.ai);
    if (!check) return this.status;
    const last = this.status.checkedAt?.getTime();
    if (!force && last !== undefined && this.clock().getTime() - last < MIN_GAP_MS) return this.status;
    this.running ??= check()
      .catch(() => ({ state: 'ERROR' as const, model: undefined }))
      .then((health) => {
        const was = this.status.state;
        this.status = { state: health.state, model: health.model ?? null, checkedAt: this.clock() };
        if (health.state !== 'OK') this.log.error({ state: health.state }, 'AI check failed');
        else if (was !== 'OK') this.log.info({ model: health.model }, 'AI check passed');
        return this.status;
      })
      .finally(() => {
        this.running = null;
      });
    return this.running;
  }
}
