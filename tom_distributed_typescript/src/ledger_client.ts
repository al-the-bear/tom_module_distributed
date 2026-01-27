/**
 * TypeScript client for Distributed Ledger.
 * 
 * Provides remote access to the Ledger Server via HTTP API.
 * Mirrors the Dart RemoteLedger client implementation.
 * 
 * The Ledger system manages distributed operations with:
 * - Operation lifecycle (create, join, leave, complete)
 * - Call tracking (start, end, fail)
 * - Heartbeat monitoring
 * - Logging
 * 
 * This client provides both:
 * - Low-level API methods (createOperation, joinOperation, etc.)
 * - High-level Operation objects (getOperation, getOrCreateOperation)
 */

import { HttpClient, HttpClientOptions, HttpException, RetryExhaustedException } from './http_client';
import { discover, DiscoveryFailedException, scanSubnet } from './discovery';
import {
  Operation,
  OperationState as InternalOperationState,
  OperationCallback,
  CallCallback,
  Call,
  SpawnedCall,
  LedgerClientInterface,
  OperationFailedInfo,
  OperationFailedException,
  HeartbeatResult as OperationHeartbeatResult,
  HeartbeatError,
  HeartbeatErrorType,
  SyncResult,
  StartCallOptions,
  SpawnCallOptions,
} from './operation';

export { DiscoveryFailedException, RetryExhaustedException };
export {
  Operation,
  OperationCallback,
  CallCallback,
  Call,
  SpawnedCall,
  OperationFailedInfo,
  OperationFailedException,
  OperationHeartbeatResult,
  HeartbeatError,
  HeartbeatErrorType,
  SyncResult,
  StartCallOptions,
  SpawnCallOptions,
};

// ─────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────

/**
 * Log level for ledger logging.
 */
export type LogLevel = 'debug' | 'info' | 'warning' | 'error';

/**
 * Operation state.
 */
export type OperationState = 
  | 'active'
  | 'completed'
  | 'aborted'
  | 'unknown';

/**
 * Server status response.
 */
export interface LedgerServerStatus {
  service: string;
  version: string;
  status: string;
  port: number;
  basePath: string;
  timestamp: Date;
}

/**
 * Operation info returned when creating/joining.
 */
export interface OperationInfo {
  operationId: string;
  participantId: string;
  isInitiator: boolean;
  sessionId: string;
  startTime: Date;
}

/**
 * Heartbeat result.
 */
export interface HeartbeatResult {
  success: boolean;
  reason?: string;
  abortFlag?: boolean;
  callFrameCount?: number;
  tempResourceCount?: number;
  heartbeatAgeMs?: number;
  isStale?: boolean;
  participants?: string[];
  staleParticipants?: string[];
}

/**
 * Operation state response.
 */
export interface OperationStateResponse {
  operationId: string;
  state: OperationState;
  aborted: boolean;
  callFrameCount: number;
  participants: string[];
}

/**
 * Call info returned when starting a call.
 */
export interface CallInfo {
  callId: string;
  startedAt: Date;
}

// ─────────────────────────────────────────────────────────────
// Exceptions
// ─────────────────────────────────────────────────────────────

/**
 * Exception thrown when an operation is not found.
 */
export class OperationNotFoundException extends Error {
  readonly operationId: string;
  
  constructor(operationId: string) {
    super(`Operation not found: ${operationId}`);
    this.name = 'OperationNotFoundException';
    this.operationId = operationId;
  }
}

/**
 * Exception thrown when a ledger operation fails.
 */
export class LedgerException extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'LedgerException';
  }
}

// ─────────────────────────────────────────────────────────────
// Client Options
// ─────────────────────────────────────────────────────────────

/**
 * Options for creating a LedgerClient.
 */
export interface LedgerClientOptions extends HttpClientOptions {
  /** Participant ID for this client. Required for operations. */
  participantId?: string;
  
  /** Process ID of this participant. */
  participantPid?: number;
}

// ─────────────────────────────────────────────────────────────
// Client Implementation
// ─────────────────────────────────────────────────────────────

/** Default Ledger server port. */
export const DEFAULT_LEDGER_PORT = 19880;

/**
 * Remote client for Distributed Ledger.
 * 
 * Provides HTTP-based access to all Ledger operations.
 * 
 * This client provides two levels of API:
 * 
 * **High-level API** (recommended):
 * - `getOperation()` - Create or join with full Operation object
 * - `getOrCreateOperation()` - Get existing or create new
 * - Operation objects with Call/SpawnedCall tracking
 * 
 * **Low-level API** (for advanced use):
 * - `createOperation()` - Create operation, get raw info
 * - `joinOperation()` - Join operation, get raw info
 * - `startCall()`, `endCall()`, `failCall()` - Manual call tracking
 */
export class LedgerClient implements LedgerClientInterface {
  private readonly httpClient: HttpClient;
  
  /** Tracked operations by ID. */
  private readonly _operations = new Map<string, InternalOperationState>();
  
  /** The base URL of the Ledger server. */
  readonly baseUrl: string;
  
  /** Participant ID for this client. */
  readonly participantId: string;
  
  /** Process ID of this participant. */
  readonly participantPid: number;
  
  /**
   * Creates a new LedgerClient.
   * 
   * @param options Client options
   */
  constructor(options: LedgerClientOptions = {}) {
    this.baseUrl = options.baseUrl ?? `http://localhost:${DEFAULT_LEDGER_PORT}`;
    this.participantId = options.participantId ?? `ts_client_${Date.now()}`;
    this.participantPid = options.participantPid ?? (typeof process !== 'undefined' ? process.pid : -1);
    this.httpClient = new HttpClient({
      baseUrl: this.baseUrl,
      enableRetry: options.enableRetry ?? true,
      retryConfig: options.retryConfig,
      timeout: options.timeout,
    });
  }
  
  // ─────────────────────────────────────────────────────────────
  // LedgerClientInterface Implementation
  // ─────────────────────────────────────────────────────────────
  
  /**
   * Post to a path on the server.
   * @internal
   */
  async post(path: string, body: Record<string, unknown>): Promise<{ status: number; body: string; ok: boolean }> {
    return this.httpClient.post(path, body);
  }
  
  /**
   * Unregister a tracked operation.
   * @internal
   */
  unregisterOperation(operationId: string): void {
    const state = this._operations.get(operationId);
    if (state) {
      state.stopHeartbeat();
      this._operations.delete(operationId);
    }
  }
  
  // ─────────────────────────────────────────────────────────────
  // High-Level Operation API
  // ─────────────────────────────────────────────────────────────
  
  /**
   * Create a new operation and return an Operation object.
   * 
   * The Operation object provides high-level call management
   * with automatic session tracking.
   * 
   * @example
   * ```typescript
   * const operation = await client.getOperation({ description: 'Process payment' });
   * 
   * const call = await operation.startCall<number>();
   * try {
   *   const result = await processPayment();
   *   await call.end(result);
   * } catch (e) {
   *   await call.fail(e);
   * }
   * 
   * await operation.complete();
   * ```
   */
  async getOperation(options: {
    description?: string;
    autoHeartbeat?: boolean;
    heartbeatIntervalMs?: number;
    callback?: OperationCallback;
  } = {}): Promise<Operation> {
    const {
      description,
      autoHeartbeat = true,
      heartbeatIntervalMs = 4500,
      callback,
    } = options;
    
    // Create operation on server
    const response = await this.httpClient.post('/operation/create', {
      participantId: this.participantId,
      participantPid: this.participantPid,
      description,
    });
    this.checkResponse(response);
    const info = this.parseOperationInfo(JSON.parse(response.body));
    
    // Create internal state
    const state = new InternalOperationState({
      operationId: info.operationId,
      participantId: info.participantId,
      pid: this.participantPid,
      isInitiator: info.isInitiator,
      startTime: info.startTime,
    });
    
    // Register initial session
    const sessionId = parseInt(info.sessionId, 10) || 1;
    state.registerSession(sessionId);
    
    // Track operation
    this._operations.set(info.operationId, state);
    
    // Create Operation object
    const operation = new Operation(state, this, sessionId);
    
    // Start heartbeat if requested
    if (autoHeartbeat) {
      operation.startHeartbeat({
        intervalMs: heartbeatIntervalMs,
        onError: callback?.onHeartbeatError,
        onSuccess: callback?.onHeartbeatSuccess,
      });
    }
    
    // Set up callback handlers
    if (callback?.onAbort) {
      operation.onAbort.then(() => callback.onAbort?.(operation));
    }
    if (callback?.onFailure) {
      operation.onFailure.then((info) => callback.onFailure?.(operation, info));
    }
    
    return operation;
  }
  
  /**
   * Join an existing operation and return an Operation object.
   */
  async joinOperationAsOperation(
    operationId: string,
    options: {
      autoHeartbeat?: boolean;
      heartbeatIntervalMs?: number;
      callback?: OperationCallback;
    } = {},
  ): Promise<Operation> {
    const {
      autoHeartbeat = true,
      heartbeatIntervalMs = 4500,
      callback,
    } = options;
    
    // Check if we already have this operation
    let state = this._operations.get(operationId);
    
    if (state) {
      // Already tracking - create a new session
      const sessionId = ++state.sessionCounter;
      state.registerSession(sessionId);
      
      // Also notify server
      await this.httpClient.post('/operation/join', {
        operationId,
        participantId: this.participantId,
        participantPid: this.participantPid,
      });
      
      return new Operation(state, this, sessionId);
    }
    
    // Join on server
    const response = await this.httpClient.post('/operation/join', {
      operationId,
      participantId: this.participantId,
      participantPid: this.participantPid,
    });
    this.checkResponse(response);
    const info = this.parseOperationInfo(JSON.parse(response.body));
    
    // Create internal state
    state = new InternalOperationState({
      operationId: info.operationId,
      participantId: info.participantId,
      pid: this.participantPid,
      isInitiator: info.isInitiator,
      startTime: info.startTime,
    });
    
    // Register session
    const sessionId = parseInt(info.sessionId, 10) || 1;
    state.registerSession(sessionId);
    
    // Track operation
    this._operations.set(info.operationId, state);
    
    // Create Operation object
    const operation = new Operation(state, this, sessionId);
    
    // Start heartbeat if requested
    if (autoHeartbeat) {
      operation.startHeartbeat({
        intervalMs: heartbeatIntervalMs,
        onError: callback?.onHeartbeatError,
        onSuccess: callback?.onHeartbeatSuccess,
      });
    }
    
    // Set up callback handlers
    if (callback?.onAbort) {
      operation.onAbort.then(() => callback.onAbort?.(operation));
    }
    if (callback?.onFailure) {
      operation.onFailure.then((info) => callback.onFailure?.(operation, info));
    }
    
    return operation;
  }
  
  /**
   * Get an existing tracked operation or create a new one.
   */
  async getOrCreateOperation(
    operationId: string | null,
    options: {
      description?: string;
      autoHeartbeat?: boolean;
      heartbeatIntervalMs?: number;
      callback?: OperationCallback;
    } = {},
  ): Promise<Operation> {
    if (operationId) {
      return this.joinOperationAsOperation(operationId, options);
    }
    return this.getOperation(options);
  }

  /**
   * Auto-discover a Ledger server.
   * 
   * Discovery order:
   * 1. Try localhost on default port (19880)
   * 2. Try 127.0.0.1 on default port
   * 3. Try all local machine IP addresses
   * 4. Scan all /24 subnets for each local IP
   * 
   * @param options Discovery options
   */
  static async discover(options: {
    port?: number;
    timeout?: number;
    participantId?: string;
  } = {}): Promise<LedgerClient> {
    const port = options.port ?? DEFAULT_LEDGER_PORT;
    
    const result = await discover({
      port,
      timeout: options.timeout ?? 5000,
      healthPath: '/health',
    });
    
    return new LedgerClient({
      baseUrl: result.url,
      participantId: options.participantId,
    });
  }
  
  /**
   * Scan a subnet for Ledger servers.
   * 
   * @param subnet First 3 octets (e.g., "192.168.1")
   * @param options Scan options
   */
  static async scanSubnet(
    subnet: string,
    options: { port?: number; timeout?: number } = {},
  ): Promise<string[]> {
    const port = options.port ?? DEFAULT_LEDGER_PORT;
    return scanSubnet(subnet, port, '/health', options.timeout ?? 500);
  }
  
  /**
   * Disposes the client.
   */
  dispose(): void {
    this.httpClient.dispose();
  }
  
  // ─────────────────────────────────────────────────────────────
  // Health & Status
  // ─────────────────────────────────────────────────────────────
  
  /**
   * Check if server is healthy.
   */
  async isHealthy(): Promise<boolean> {
    try {
      const response = await this.httpClient.get('/health');
      return response.ok;
    } catch {
      return false;
    }
  }
  
  /**
   * Get server status.
   */
  async getStatus(): Promise<LedgerServerStatus> {
    const response = await this.httpClient.get('/status');
    this.checkResponse(response);
    const data = JSON.parse(response.body);
    return {
      service: data.service,
      version: data.version,
      status: data.status,
      port: data.port,
      basePath: data.basePath,
      timestamp: new Date(data.timestamp),
    };
  }
  
  // ─────────────────────────────────────────────────────────────
  // Operation Lifecycle
  // ─────────────────────────────────────────────────────────────
  
  /**
   * Create a new operation.
   * 
   * The creating participant becomes the initiator.
   */
  async createOperation(options: { description?: string } = {}): Promise<OperationInfo> {
    const response = await this.httpClient.post('/operation/create', {
      participantId: this.participantId,
      participantPid: this.participantPid,
      description: options.description,
    });
    this.checkResponse(response);
    return this.parseOperationInfo(JSON.parse(response.body));
  }
  
  /**
   * Join an existing operation.
   */
  async joinOperation(operationId: string): Promise<OperationInfo> {
    const response = await this.httpClient.post('/operation/join', {
      operationId,
      participantId: this.participantId,
      participantPid: this.participantPid,
    });
    this.checkResponse(response);
    return this.parseOperationInfo(JSON.parse(response.body));
  }
  
  /**
   * Leave an operation.
   */
  async leaveOperation(operationId: string): Promise<void> {
    const response = await this.httpClient.post('/operation/leave', {
      operationId,
    });
    this.checkResponse(response);
  }
  
  /**
   * Complete an operation.
   */
  async completeOperation(operationId: string): Promise<void> {
    const response = await this.httpClient.post('/operation/complete', {
      operationId,
    });
    this.checkResponse(response);
  }
  
  // ─────────────────────────────────────────────────────────────
  // Heartbeat & State
  // ─────────────────────────────────────────────────────────────
  
  /**
   * Send a heartbeat for an operation.
   */
  async heartbeat(operationId: string): Promise<HeartbeatResult> {
    const response = await this.httpClient.post('/operation/heartbeat', {
      operationId,
    });
    this.checkResponse(response);
    return JSON.parse(response.body) as HeartbeatResult;
  }
  
  /**
   * Set the abort flag for an operation.
   */
  async setAbortFlag(operationId: string, value: boolean = true): Promise<void> {
    const response = await this.httpClient.post('/operation/abort', {
      operationId,
      value,
    });
    this.checkResponse(response);
  }
  
  /**
   * Get the state of an operation.
   */
  async getOperationState(operationId: string): Promise<OperationStateResponse> {
    const response = await this.httpClient.post('/operation/state', {
      operationId,
    });
    this.checkResponse(response);
    const data = JSON.parse(response.body);
    return {
      operationId: data.operationId,
      state: data.state as OperationState,
      aborted: data.aborted,
      callFrameCount: data.callFrameCount,
      participants: data.participants ?? [],
    };
  }
  
  // ─────────────────────────────────────────────────────────────
  // Logging
  // ─────────────────────────────────────────────────────────────
  
  /**
   * Log a message to an operation.
   */
  async log(
    operationId: string,
    message: string,
    level: LogLevel = 'info',
  ): Promise<void> {
    const response = await this.httpClient.post('/operation/log', {
      operationId,
      message,
      level,
    });
    this.checkResponse(response);
  }
  
  // ─────────────────────────────────────────────────────────────
  // Call Tracking
  // ─────────────────────────────────────────────────────────────
  
  /**
   * Start a tracked call within an operation.
   */
  async startCall(
    operationId: string,
    options: { description?: string; failOnCrash?: boolean } = {},
  ): Promise<CallInfo> {
    const response = await this.httpClient.post('/call/start', {
      operationId,
      description: options.description,
      failOnCrash: options.failOnCrash ?? true,
    });
    this.checkResponse(response);
    const data = JSON.parse(response.body);
    return {
      callId: data.callId,
      startedAt: new Date(data.startedAt),
    };
  }
  
  /**
   * End a tracked call successfully.
   */
  async endCall(operationId: string, callId: string): Promise<void> {
    const response = await this.httpClient.post('/call/end', {
      operationId,
      callId,
    });
    this.checkResponse(response);
  }
  
  /**
   * Mark a tracked call as failed.
   */
  async failCall(
    operationId: string,
    callId: string,
    error?: string,
  ): Promise<void> {
    const response = await this.httpClient.post('/call/fail', {
      operationId,
      callId,
      error,
    });
    this.checkResponse(response);
  }
  
  // ─────────────────────────────────────────────────────────────
  // Call Frame Management (Low-level)
  // ─────────────────────────────────────────────────────────────
  
  /**
   * Create a call frame directly.
   */
  async createCallFrame(operationId: string, callId: string): Promise<void> {
    const response = await this.httpClient.post('/callframe/create', {
      operationId,
      callId,
    });
    this.checkResponse(response);
  }
  
  /**
   * Delete a call frame directly.
   */
  async deleteCallFrame(operationId: string, callId: string): Promise<void> {
    const response = await this.httpClient.post('/callframe/delete', {
      operationId,
      callId,
    });
    this.checkResponse(response);
  }
  
  // ─────────────────────────────────────────────────────────────
  // Private Helpers
  // ─────────────────────────────────────────────────────────────
  
  private checkResponse(response: { status: number; body: string; ok: boolean }): void {
    if (response.status === 404) {
      try {
        const body = JSON.parse(response.body);
        if (body.message?.includes('Operation not found')) {
          throw new OperationNotFoundException(body.operationId ?? 'unknown');
        }
      } catch (e) {
        if (e instanceof OperationNotFoundException) throw e;
      }
      throw new LedgerException(`Not found: ${response.body}`);
    }
    if (!response.ok) {
      throw new HttpException(response.status, response.body);
    }
  }
  
  private parseOperationInfo(data: Record<string, unknown>): OperationInfo {
    return {
      operationId: data.operationId as string,
      participantId: data.participantId as string,
      isInitiator: data.isInitiator as boolean,
      sessionId: data.sessionId as string,
      startTime: new Date(data.startTime as string),
    };
  }
}
