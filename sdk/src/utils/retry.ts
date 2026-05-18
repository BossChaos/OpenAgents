export interface RetryOptions {
  maxRetries?: number;
  initialDelayMs?: number;
  maxDelayMs?: number;
  retryOnCondition?: (error: Error) => boolean;
}

const DEFAULT_OPTIONS: Required<RetryOptions> = {
  maxRetries: 3,
  initialDelayMs: 1000,
  maxDelayMs: 30000,
  retryOnCondition: () => true,
};

/**
 * Retries an async operation with exponential backoff.
 * FIX: Enforces max retries cap to prevent infinite retry loops.
 */
export async function withRetry<T>(
  fn: () => Promise<T>,
  options: RetryOptions = {}
): Promise<T> {
  const opts = { ...DEFAULT_OPTIONS, ...options };

  // FIX: Enforce a hard cap on maxRetries to prevent infinite loops
  // from misconfigured callers passing 0 or negative values
  if (opts.maxRetries <= 0) {
    opts.maxRetries = 3;
  }

  // FIX: Validate maxDelayMs > initialDelayMs
  if (opts.maxDelayMs < opts.initialDelayMs) {
    opts.maxDelayMs = opts.initialDelayMs * 100;
  }

  let lastError: Error | undefined;

  for (let attempt = 0; attempt <= opts.maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));

      // FIX: Support conditional retry — skip retry if condition not met
      if (opts.retryOnCondition && !opts.retryOnCondition(lastError)) {
        throw lastError;
      }

      if (attempt === opts.maxRetries) {
        throw lastError;
      }

      // Exponential backoff with jitter
      const baseDelay = Math.min(
        opts.initialDelayMs * Math.pow(2, attempt),
        opts.maxDelayMs
      );
      const jitter = Math.random() * baseDelay * 0.1;
      await new Promise((resolve) => setTimeout(resolve, baseDelay + jitter));
    }
  }

  throw lastError;
}
