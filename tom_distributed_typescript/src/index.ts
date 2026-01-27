/**
 * TypeScript clients for Tom Distributed System.
 * 
 * Provides cross-platform HTTP clients for:
 * - ProcessMonitor: Process lifecycle management
 * - Ledger: Distributed operation coordination
 * 
 * Works in Node.js, Deno, browsers, and VS Code extensions.
 */

// HTTP utilities
export {
  RetryExhaustedException,
  RetryConfig,
  DEFAULT_RETRY_DELAYS_MS,
  withRetry,
  isRetryableError,
  isRetryableStatusCode,
} from './http_retry';

export {
  HttpClient,
  HttpClientOptions,
  HttpResponse,
  HttpException,
  RequestOptions,
  parseJsonResponse,
  checkResponse,
} from './http_client';

// Discovery
export {
  discover,
  scanSubnet,
  DiscoveryFailedException,
  DiscoveryOptions,
  DiscoveryResult,
} from './discovery';

// Process Monitor
export {
  ProcessMonitorClient,
  ProcessMonitorClientOptions,
  DEFAULT_PROCESS_MONITOR_PORT,
  // Types
  ProcessState,
  ProcessConfig,
  ProcessStatus,
  MonitorStatus,
  RestartPolicy,
  RestartPolicyType,
  AlivenessCheck,
  RemoteAccessConfig,
  PartnerDiscoveryConfig,
  // Exceptions
  ProcessNotFoundException,
  PermissionDeniedException,
} from './process_monitor_client';

// Ledger
export {
  LedgerClient,
  LedgerClientOptions,
  DEFAULT_LEDGER_PORT,
  // Types
  LogLevel,
  OperationState,
  LedgerServerStatus,
  OperationInfo,
  HeartbeatResult,
  OperationStateResponse,
  CallInfo,
  // High-level Operation API
  Operation,
  OperationCallback,
  Call,
  CallCallback,
  SpawnedCall,
  StartCallOptions,
  SpawnCallOptions,
  OperationFailedInfo,
  OperationFailedException,
  OperationHeartbeatResult,
  HeartbeatError,
  HeartbeatErrorType,
  SyncResult,
  // Exceptions
  OperationNotFoundException,
  LedgerException,
} from './ledger_client';
