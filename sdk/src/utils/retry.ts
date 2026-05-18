/**
 * retry.ts - Exponential backoff retry utility
 * Contributor: BossChaos (hermes-agent)
 * Fixes: #137, #139 - max retries cap, per-error-type backoff
 */

export interface RetryOptions {
  maxRetries?: number;
  baseDelayMs?: number;
  maxDelayMs?: number;
  backoffMultiplier?: number;
  retryableErrors?: Set<string>;
}

const DEFAULT_MAX_RETRIES = 5;
const DEFAULT_BASE_DELAY = 1000;
const DEFAULT_MAX_DELAY = 30000;
const DEFAULT_BACKOFF_MULTIPLIER = 2;

/**
 * FIX #137: Add hard cap on maxRetries and per-error-type backoff
 */
export async function withRetry<T>(
  fn: () => Promise<T>,
  options: RetryOptions = {}
): Promise<T> {
  const maxRetries = Math.min(options.maxRetries ?? DEFAULT_MAX_RETRIES, 10); // FIX: Hard cap at 10
  const baseDelay = options.baseDelayMs ?? DEFAULT_BASE_DELAY;
  const maxDelay = options.maxDelayMs ?? DEFAULT_MAX_DELAY;
  const multiplier = options.backoffMultiplier ?? DEFAULT_BACKOFF_MULTIPLIER;
  const retryable = options.retryableErrors ?? new Set(["ECONNRESET", "ETIMEDOUT", "503", "429"]);

  let lastError: Error | undefined;

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } catch (err: any) {
      lastError = err instanceof Error ? err : new Error(String(err));

      // FIX #139: Per-error-type backoff multiplier
      let errorMultiplier = 1;
      if (lastError.message.includes("429")) {
        errorMultiplier = 3; // Rate limit: back off more aggressively
      } else if (lastError.message.includes("503")) {
        errorMultiplier = 2; // Service unavailable: moderate backoff
      }

      if (attempt >= maxRetries) break;

      const delay = Math.min(
        baseDelay * Math.pow(multiplier, attempt) * errorMultiplier,
        maxDelay
      );

      await new Promise((r) => setTimeout(r, delay));
    }
  }

  throw lastError;
}
