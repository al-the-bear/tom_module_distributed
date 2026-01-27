/**
 * HTTP retry utility with exponential backoff.
 * 
 * Provides standardized retry logic for HTTP clients.
 * Retries after 2, 4, 8, 16, 32 seconds (up to 62 seconds total).
 */

/** Default retry delays in milliseconds: 2, 4, 8, 16, 32 seconds. */
export const DEFAULT_RETRY_DELAYS_MS = [2000, 4000, 8000, 16000, 32000];

/**
 * Exception thrown when all retries are exhausted.
 */
export class RetryExhaustedException extends Error {
  /** The last error that occurred. */
  readonly lastError: unknown;
  
  /** The number of attempts made. */
  readonly attempts: number;

  constructor(options: { lastError: unknown; attempts: number }) {
    super(`All ${options.attempts} attempts failed. Last error: ${options.lastError}`);
    this.name = 'RetryExhaustedException';
    this.lastError = options.lastError;
    this.attempts = options.attempts;
  }
}

/**
 * Configuration for retry behavior.
 */
export interface RetryConfig {
  /** Delays between retry attempts in milliseconds. */
  retryDelaysMs?: number[];
  
  /** Optional callback for logging retry attempts. */
  onRetry?: (attempt: number, error: unknown, nextDelayMs: number) => void;
  
  /** Optional function to determine if an error should be retried. */
  shouldRetry?: (error: unknown) => boolean;
}

/**
 * Default retry configuration.
 */
export const defaultRetryConfig: Required<Pick<RetryConfig, 'retryDelaysMs'>> = {
  retryDelaysMs: DEFAULT_RETRY_DELAYS_MS,
};

/**
 * Sleep for a specified duration.
 */
export function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Checks if an error is retryable.
 */
export function isRetryableError(error: unknown): boolean {
  if (!error) return false;
  
  // Network errors (fetch API)
  if (error instanceof TypeError && error.message.includes('fetch')) {
    return true;
  }
  
  // Connection errors
  if (error instanceof Error) {
    const message = error.message.toLowerCase();
    if (
      message.includes('network') ||
      message.includes('connection') ||
      message.includes('timeout') ||
      message.includes('econnrefused') ||
      message.includes('econnreset') ||
      message.includes('socket') ||
      message.includes('etimedout') ||
      message.includes('enotfound')
    ) {
      return true;
    }
  }
  
  return false;
}

/**
 * Checks if an HTTP status code indicates a retryable error.
 */
export function isRetryableStatusCode(statusCode: number): boolean {
  // Server errors (5xx) are retryable
  if (statusCode >= 500 && statusCode < 600) return true;
  
  // Request timeout
  if (statusCode === 408) return true;
  
  // Too many requests (rate limiting)
  if (statusCode === 429) return true;
  
  return false;
}

/**
 * Executes an async operation with retry logic.
 * 
 * Retries the operation according to configured delays.
 * By default, retries after 2, 4, 8, 16, 32 seconds.
 * 
 * @example
 * ```typescript
 * const result = await withRetry(
 *   () => fetch(url),
 *   {
 *     onRetry: (attempt, error, delay) => {
 *       console.log(`Retry ${attempt} after ${delay}ms: ${error}`);
 *     },
 *   },
 * );
 * ```
 */
export async function withRetry<T>(
  operation: () => Promise<T>,
  config: RetryConfig = {},
): Promise<T> {
  const delays = config.retryDelaysMs ?? defaultRetryConfig.retryDelaysMs;
  let lastError: unknown;
  
  for (let attempt = 0; attempt <= delays.length; attempt++) {
    try {
      return await operation();
    } catch (e) {
      lastError = e;
      
      // Check if we should retry this error
      if (config.shouldRetry && !config.shouldRetry(e)) {
        throw e;
      }
      
      // Check if this error is retryable
      if (!isRetryableError(e)) {
        throw e;
      }
      
      // Check if we have more retries
      if (attempt >= delays.length) {
        throw new RetryExhaustedException({
          lastError,
          attempts: attempt + 1,
        });
      }
      
      const delay = delays[attempt];
      config.onRetry?.(attempt + 1, e, delay);
      await sleep(delay);
    }
  }
  
  // Should never reach here, but satisfy the compiler
  throw new RetryExhaustedException({
    lastError,
    attempts: delays.length + 1,
  });
}
