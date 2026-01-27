/**
 * HTTP client abstraction for cross-platform support.
 * 
 * Works in Node.js, Deno, browsers, and VS Code extensions.
 * Uses the native fetch API which is available in all modern runtimes.
 */

import { 
  withRetry, 
  RetryConfig, 
  isRetryableStatusCode,
  RetryExhaustedException,
} from './http_retry';

export { RetryExhaustedException };

/**
 * HTTP response interface.
 */
export interface HttpResponse {
  status: number;
  statusText: string;
  body: string;
  ok: boolean;
}

/**
 * HTTP client options.
 */
export interface HttpClientOptions {
  /** Base URL for all requests. */
  baseUrl?: string;
  
  /** Enable retry with exponential backoff. Default: true */
  enableRetry?: boolean;
  
  /** Custom retry configuration. */
  retryConfig?: RetryConfig;
  
  /** Default timeout in milliseconds. Default: 30000 */
  timeout?: number;
}

/**
 * Request options for individual requests.
 */
export interface RequestOptions {
  /** HTTP method. */
  method?: 'GET' | 'POST' | 'PUT' | 'DELETE' | 'PATCH';
  
  /** Request headers. */
  headers?: Record<string, string>;
  
  /** Request body (will be JSON stringified if object). */
  body?: unknown;
  
  /** Request timeout in milliseconds. */
  timeout?: number;
}

/**
 * HTTP exception with status code.
 */
export class HttpException extends Error {
  readonly statusCode: number;
  readonly response: string;
  
  constructor(statusCode: number, response: string) {
    super(`HTTP ${statusCode}: ${response}`);
    this.name = 'HttpException';
    this.statusCode = statusCode;
    this.response = response;
  }
}

/**
 * Cross-platform HTTP client with retry support.
 */
export class HttpClient {
  private readonly baseUrl: string;
  private readonly enableRetry: boolean;
  private readonly retryConfig: RetryConfig;
  private readonly defaultTimeout: number;
  private abortController?: AbortController;
  
  constructor(options: HttpClientOptions = {}) {
    this.baseUrl = options.baseUrl ?? '';
    this.enableRetry = options.enableRetry ?? true;
    this.retryConfig = options.retryConfig ?? {};
    this.defaultTimeout = options.timeout ?? 30000;
  }
  
  /**
   * Makes an HTTP request.
   */
  async request(path: string, options: RequestOptions = {}): Promise<HttpResponse> {
    const url = this.baseUrl ? `${this.baseUrl}${path}` : path;
    const method = options.method ?? 'GET';
    const timeout = options.timeout ?? this.defaultTimeout;
    
    const headers: Record<string, string> = {
      ...options.headers,
    };
    
    let body: string | undefined;
    if (options.body !== undefined) {
      if (typeof options.body === 'string') {
        body = options.body;
      } else {
        body = JSON.stringify(options.body);
        headers['Content-Type'] = headers['Content-Type'] ?? 'application/json';
      }
    }
    
    const doRequest = async (): Promise<HttpResponse> => {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), timeout);
      
      try {
        const response = await fetch(url, {
          method,
          headers,
          body,
          signal: controller.signal,
        });
        
        const responseBody = await response.text();
        
        // Check for retryable status codes and throw to trigger retry
        if (this.enableRetry && isRetryableStatusCode(response.status)) {
          throw new HttpException(response.status, responseBody);
        }
        
        return {
          status: response.status,
          statusText: response.statusText,
          body: responseBody,
          ok: response.ok,
        };
      } finally {
        clearTimeout(timeoutId);
      }
    };
    
    if (this.enableRetry) {
      return withRetry(doRequest, {
        ...this.retryConfig,
        shouldRetry: (error) => {
          // Retry on network errors or retryable HTTP status codes
          if (error instanceof HttpException) {
            return isRetryableStatusCode(error.statusCode);
          }
          // Let the default shouldRetry handle network errors
          return this.retryConfig.shouldRetry?.(error) ?? true;
        },
      });
    }
    
    return doRequest();
  }
  
  /**
   * Makes a GET request.
   */
  async get(path: string, options?: Omit<RequestOptions, 'method' | 'body'>): Promise<HttpResponse> {
    return this.request(path, { ...options, method: 'GET' });
  }
  
  /**
   * Makes a POST request.
   */
  async post(path: string, body?: unknown, options?: Omit<RequestOptions, 'method' | 'body'>): Promise<HttpResponse> {
    return this.request(path, { ...options, method: 'POST', body });
  }
  
  /**
   * Makes a PUT request.
   */
  async put(path: string, body?: unknown, options?: Omit<RequestOptions, 'method' | 'body'>): Promise<HttpResponse> {
    return this.request(path, { ...options, method: 'PUT', body });
  }
  
  /**
   * Makes a DELETE request.
   */
  async delete(path: string, options?: Omit<RequestOptions, 'method' | 'body'>): Promise<HttpResponse> {
    return this.request(path, { ...options, method: 'DELETE' });
  }
  
  /**
   * Disposes the client.
   */
  dispose(): void {
    this.abortController?.abort();
  }
}

/**
 * Parse JSON response body, returning null on 404.
 */
export function parseJsonResponse<T>(response: HttpResponse): T | null {
  if (response.status === 404) {
    return null;
  }
  if (!response.ok) {
    throw new HttpException(response.status, response.body);
  }
  return JSON.parse(response.body) as T;
}

/**
 * Check response and throw on error.
 */
export function checkResponse(response: HttpResponse): void {
  if (!response.ok) {
    throw new HttpException(response.status, response.body);
  }
}
