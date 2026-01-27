/**
 * TypeScript client for ProcessMonitor.
 * 
 * Provides remote access to ProcessMonitor via HTTP API.
 * Mirrors the Dart RemoteProcessMonitorClient implementation.
 */

import { HttpClient, HttpClientOptions, checkResponse, HttpException, RetryExhaustedException } from './http_client';
import { discover, DiscoveryFailedException, scanSubnet } from './discovery';

export { DiscoveryFailedException, RetryExhaustedException };

// ─────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────

/**
 * Process state enumeration.
 */
export type ProcessState = 
  | 'stopped'
  | 'running'
  | 'starting'
  | 'stopping'
  | 'crashed'
  | 'disabled'
  | 'unknown';

/**
 * Restart policy types.
 */
export type RestartPolicyType = 'always' | 'on-failure' | 'never';

/**
 * Restart policy configuration.
 */
export interface RestartPolicy {
  type: RestartPolicyType;
  maxAttempts?: number;
  delayMs?: number;
  maxDelayMs?: number;
  backoffMultiplier?: number;
}

/**
 * HTTP aliveness check configuration.
 */
export interface AlivenessCheck {
  url: string;
  intervalMs?: number;
  timeoutMs?: number;
  successCodes?: number[];
}

/**
 * Configuration for registering a process.
 */
export interface ProcessConfig {
  /** Unique identifier for the process. */
  id: string;
  
  /** Human-readable name. */
  name: string;
  
  /** Executable command. */
  command: string;
  
  /** Command-line arguments. */
  args?: string[];
  
  /** Working directory. */
  workingDirectory?: string;
  
  /** Environment variables. */
  environment?: Record<string, string>;
  
  /** Start automatically when ProcessMonitor initializes. */
  autostart?: boolean;
  
  /** Restart policy configuration. */
  restartPolicy?: RestartPolicy;
  
  /** HTTP aliveness check configuration. */
  alivenessCheck?: AlivenessCheck;
}

/**
 * Status information for a process.
 */
export interface ProcessStatus {
  /** Unique process identifier. */
  id: string;
  
  /** Human-readable process name. */
  name: string;
  
  /** Current process state. */
  state: ProcessState;
  
  /** Whether the process can be started. */
  enabled: boolean;
  
  /** Start on ProcessMonitor initialization. */
  autostart: boolean;
  
  /** Whether registered via remote API. */
  isRemote: boolean;
  
  /** Current process ID (if running). */
  pid?: number;
  
  /** When process was last started. */
  lastStartedAt?: Date;
  
  /** When process was last stopped. */
  lastStoppedAt?: Date;
  
  /** Current restart attempt count. */
  restartAttempts: number;
}

/**
 * Status information for the ProcessMonitor instance.
 */
export interface MonitorStatus {
  /** ProcessMonitor instance ID. */
  instanceId: string;
  
  /** Process ID of this instance. */
  pid: number;
  
  /** When this instance started. */
  startedAt: Date;
  
  /** Seconds since startup. */
  uptime: number;
  
  /** Current state ("running", "stopping"). */
  state: string;
  
  /** Whether running in standalone mode (no partner). */
  standaloneMode: boolean;
  
  /** Partner instance ID (null if standalone). */
  partnerInstanceId?: string;
  
  /** Partner status ("running", "stopped", "unknown"). */
  partnerStatus?: string;
  
  /** Partner's PID (null if unknown or standalone). */
  partnerPid?: number;
  
  /** Total number of managed processes. */
  managedProcessCount: number;
  
  /** Number of currently running processes. */
  runningProcessCount: number;
}

/**
 * Remote access configuration.
 */
export interface RemoteAccessConfig {
  startRemoteAccess: boolean;
  allowRemoteRegister: boolean;
  allowRemoteDeregister: boolean;
  allowRemoteStart: boolean;
  allowRemoteStop: boolean;
  allowRemoteDisable: boolean;
  allowRemoteAutostart: boolean;
  allowRemoteMonitorRestart: boolean;
}

/**
 * Partner discovery configuration.
 */
export interface PartnerDiscoveryConfig {
  enabled: boolean;
  scanIntervalMs?: number;
  subnets?: string[];
}

// ─────────────────────────────────────────────────────────────
// Exceptions
// ─────────────────────────────────────────────────────────────

/**
 * Exception thrown when a process is not found.
 */
export class ProcessNotFoundException extends Error {
  readonly processId: string;
  
  constructor(processId: string) {
    super(`Process not found: ${processId}`);
    this.name = 'ProcessNotFoundException';
    this.processId = processId;
  }
}

/**
 * Exception thrown when permission is denied.
 */
export class PermissionDeniedException extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PermissionDeniedException';
  }
}

// ─────────────────────────────────────────────────────────────
// Client Options
// ─────────────────────────────────────────────────────────────

/**
 * Options for creating a ProcessMonitorClient.
 */
export interface ProcessMonitorClientOptions extends HttpClientOptions {
  /** Target ProcessMonitor instance ID. Default: 'default' */
  instanceId?: string;
}

// ─────────────────────────────────────────────────────────────
// Client Implementation
// ─────────────────────────────────────────────────────────────

/** Default ProcessMonitor port. */
export const DEFAULT_PROCESS_MONITOR_PORT = 19881;

/**
 * Remote client for ProcessMonitor.
 * 
 * Provides HTTP-based access to all ProcessMonitor operations.
 */
export class ProcessMonitorClient {
  private readonly client: HttpClient;
  
  /** The base URL of the ProcessMonitor. */
  readonly baseUrl: string;
  
  /** The target ProcessMonitor instance ID. */
  readonly instanceId: string;
  
  /**
   * Creates a new ProcessMonitorClient.
   * 
   * @param options Client options
   */
  constructor(options: ProcessMonitorClientOptions = {}) {
    this.baseUrl = options.baseUrl ?? `http://localhost:${DEFAULT_PROCESS_MONITOR_PORT}`;
    this.instanceId = options.instanceId ?? 'default';
    this.client = new HttpClient({
      baseUrl: this.baseUrl,
      enableRetry: options.enableRetry ?? true,
      retryConfig: options.retryConfig,
      timeout: options.timeout,
    });
  }
  
  /**
   * Auto-discover a ProcessMonitor instance.
   * 
   * Discovery order:
   * 1. Try localhost on default port (19881)
   * 2. Try 127.0.0.1 on default port
   * 3. Try all local machine IP addresses
   * 4. Scan all /24 subnets for each local IP
   * 
   * @param options Discovery options
   */
  static async discover(options: {
    port?: number;
    timeout?: number;
    instanceId?: string;
  } = {}): Promise<ProcessMonitorClient> {
    const port = options.port ?? DEFAULT_PROCESS_MONITOR_PORT;
    
    const result = await discover({
      port,
      timeout: options.timeout ?? 5000,
      healthPath: '/monitor/status',
    });
    
    return new ProcessMonitorClient({
      baseUrl: result.url,
      instanceId: options.instanceId ?? 'default',
    });
  }
  
  /**
   * Scan a subnet for ProcessMonitor instances.
   * 
   * @param subnet First 3 octets (e.g., "192.168.1")
   * @param options Scan options
   */
  static async scanSubnet(
    subnet: string,
    options: { port?: number; timeout?: number } = {},
  ): Promise<string[]> {
    const port = options.port ?? DEFAULT_PROCESS_MONITOR_PORT;
    return scanSubnet(subnet, port, '/monitor/status', options.timeout ?? 500);
  }
  
  /**
   * Disposes the client.
   */
  dispose(): void {
    this.client.dispose();
  }
  
  // ─────────────────────────────────────────────────────────────
  // Registration
  // ─────────────────────────────────────────────────────────────
  
  /**
   * Register a new process.
   */
  async register(config: ProcessConfig): Promise<void> {
    const response = await this.client.post('/processes', config);
    this.checkResponse(response);
  }
  
  /**
   * Remove a process from the registry.
   */
  async deregister(processId: string): Promise<void> {
    const response = await this.client.delete(`/processes/${processId}`);
    this.checkResponse(response);
  }
  
  // ─────────────────────────────────────────────────────────────
  // Enable/Disable
  // ─────────────────────────────────────────────────────────────
  
  /**
   * Enable a process.
   */
  async enable(processId: string): Promise<void> {
    const response = await this.client.post(`/processes/${processId}/enable`);
    this.checkResponse(response);
  }
  
  /**
   * Disable a process.
   */
  async disable(processId: string): Promise<void> {
    const response = await this.client.post(`/processes/${processId}/disable`);
    this.checkResponse(response);
  }
  
  // ─────────────────────────────────────────────────────────────
  // Autostart
  // ─────────────────────────────────────────────────────────────
  
  /**
   * Set autostart for a process.
   */
  async setAutostart(processId: string, autostart: boolean): Promise<void> {
    const response = await this.client.put(
      `/processes/${processId}/autostart`,
      { autostart },
    );
    this.checkResponse(response);
  }
  
  // ─────────────────────────────────────────────────────────────
  // Process Control
  // ─────────────────────────────────────────────────────────────
  
  /**
   * Start a process.
   */
  async start(processId: string): Promise<void> {
    const response = await this.client.post(`/processes/${processId}/start`);
    this.checkResponse(response);
  }
  
  /**
   * Stop a process.
   */
  async stop(processId: string): Promise<void> {
    const response = await this.client.post(`/processes/${processId}/stop`);
    this.checkResponse(response);
  }
  
  /**
   * Restart a process.
   */
  async restart(processId: string): Promise<void> {
    const response = await this.client.post(`/processes/${processId}/restart`);
    this.checkResponse(response);
  }
  
  // ─────────────────────────────────────────────────────────────
  // Status
  // ─────────────────────────────────────────────────────────────
  
  /**
   * Get status of a specific process.
   */
  async getStatus(processId: string): Promise<ProcessStatus> {
    const response = await this.client.get(`/processes/${processId}`);
    this.checkResponse(response);
    return this.parseProcessStatus(JSON.parse(response.body));
  }
  
  /**
   * Get status of all processes.
   */
  async getAllStatus(): Promise<Map<string, ProcessStatus>> {
    const response = await this.client.get('/processes');
    this.checkResponse(response);
    
    const data = JSON.parse(response.body);
    const processes = data.processes as unknown[];
    const result = new Map<string, ProcessStatus>();
    
    for (const p of processes) {
      const status = this.parseProcessStatus(p as Record<string, unknown>);
      result.set(status.id, status);
    }
    
    return result;
  }
  
  /**
   * Get ProcessMonitor instance status.
   */
  async getMonitorStatus(): Promise<MonitorStatus> {
    const response = await this.client.get('/monitor/status');
    this.checkResponse(response);
    return this.parseMonitorStatus(JSON.parse(response.body));
  }
  
  // ─────────────────────────────────────────────────────────────
  // Remote Access Configuration
  // ─────────────────────────────────────────────────────────────
  
  /**
   * Enable or disable remote HTTP API access.
   */
  async setRemoteAccess(enabled: boolean): Promise<void> {
    const response = await this.client.put('/config/remote-access', {
      startRemoteAccess: enabled,
    });
    this.checkResponse(response);
  }
  
  /**
   * Get current remote access configuration.
   */
  async getRemoteAccessConfig(): Promise<RemoteAccessConfig> {
    const response = await this.client.get('/config/remote-access');
    this.checkResponse(response);
    return JSON.parse(response.body) as RemoteAccessConfig;
  }
  
  /**
   * Set remote access permissions.
   */
  async setRemoteAccessPermissions(permissions: Partial<RemoteAccessConfig>): Promise<void> {
    const response = await this.client.put('/config/remote-access', permissions);
    this.checkResponse(response);
  }
  
  /**
   * Set trusted hosts list.
   */
  async setTrustedHosts(hosts: string[]): Promise<void> {
    const response = await this.client.put('/config/trusted-hosts', {
      trustedHosts: hosts,
    });
    this.checkResponse(response);
  }
  
  /**
   * Get trusted hosts list.
   */
  async getTrustedHosts(): Promise<string[]> {
    const response = await this.client.get('/config/trusted-hosts');
    this.checkResponse(response);
    const data = JSON.parse(response.body);
    return data.trustedHosts as string[];
  }
  
  // ─────────────────────────────────────────────────────────────
  // Executable Filtering
  // ─────────────────────────────────────────────────────────────
  
  /**
   * Get the current executable whitelist.
   */
  async getExecutableWhitelist(): Promise<string[]> {
    const response = await this.client.get('/config/executable-whitelist');
    this.checkResponse(response);
    const data = JSON.parse(response.body);
    return data.patterns as string[];
  }
  
  /**
   * Set the executable whitelist.
   */
  async setExecutableWhitelist(patterns: string[]): Promise<void> {
    const response = await this.client.put('/config/executable-whitelist', {
      patterns,
    });
    this.checkResponse(response);
  }
  
  /**
   * Get the current executable blacklist.
   */
  async getExecutableBlacklist(): Promise<string[]> {
    const response = await this.client.get('/config/executable-blacklist');
    this.checkResponse(response);
    const data = JSON.parse(response.body);
    return data.patterns as string[];
  }
  
  /**
   * Set the executable blacklist.
   */
  async setExecutableBlacklist(patterns: string[]): Promise<void> {
    const response = await this.client.put('/config/executable-blacklist', {
      patterns,
    });
    this.checkResponse(response);
  }
  
  // ─────────────────────────────────────────────────────────────
  // Standalone / Partner Configuration
  // ─────────────────────────────────────────────────────────────
  
  /**
   * Enable or disable standalone mode.
   */
  async setStandaloneMode(enabled: boolean): Promise<void> {
    const response = await this.client.put('/config/standalone-mode', {
      enabled,
    });
    this.checkResponse(response);
  }
  
  /**
   * Get current standalone mode setting.
   */
  async isStandaloneMode(): Promise<boolean> {
    const response = await this.client.get('/config/standalone-mode');
    this.checkResponse(response);
    const data = JSON.parse(response.body);
    return data.enabled as boolean;
  }
  
  /**
   * Get partner discovery configuration.
   */
  async getPartnerDiscoveryConfig(): Promise<PartnerDiscoveryConfig> {
    const response = await this.client.get('/config/partner-discovery');
    this.checkResponse(response);
    return JSON.parse(response.body) as PartnerDiscoveryConfig;
  }
  
  /**
   * Set partner discovery configuration.
   */
  async setPartnerDiscoveryConfig(config: PartnerDiscoveryConfig): Promise<void> {
    const response = await this.client.put('/config/partner-discovery', config);
    this.checkResponse(response);
  }
  
  // ─────────────────────────────────────────────────────────────
  // Monitor Control
  // ─────────────────────────────────────────────────────────────
  
  /**
   * Restart the ProcessMonitor itself.
   */
  async restartMonitor(): Promise<void> {
    const response = await this.client.post('/monitor/restart');
    this.checkResponse(response);
  }
  
  // ─────────────────────────────────────────────────────────────
  // Private Helpers
  // ─────────────────────────────────────────────────────────────
  
  private checkResponse(response: { status: number; body: string; ok: boolean }): void {
    if (response.status === 403) {
      throw new PermissionDeniedException(response.body);
    }
    if (response.status === 404) {
      try {
        const body = JSON.parse(response.body);
        throw new ProcessNotFoundException(body.processId ?? 'unknown');
      } catch (e) {
        if (e instanceof ProcessNotFoundException) throw e;
        throw new ProcessNotFoundException('unknown');
      }
    }
    if (!response.ok) {
      throw new HttpException(response.status, response.body);
    }
  }
  
  private parseProcessStatus(data: Record<string, unknown>): ProcessStatus {
    return {
      id: data.id as string,
      name: data.name as string,
      state: (data.state as ProcessState) ?? 'unknown',
      enabled: data.enabled as boolean,
      autostart: data.autostart as boolean,
      isRemote: data.isRemote as boolean,
      pid: data.pid as number | undefined,
      lastStartedAt: data.lastStartedAt 
        ? new Date(data.lastStartedAt as string) 
        : undefined,
      lastStoppedAt: data.lastStoppedAt 
        ? new Date(data.lastStoppedAt as string) 
        : undefined,
      restartAttempts: (data.restartAttempts as number) ?? 0,
    };
  }
  
  private parseMonitorStatus(data: Record<string, unknown>): MonitorStatus {
    return {
      instanceId: data.instanceId as string,
      pid: data.pid as number,
      startedAt: new Date(data.startedAt as string),
      uptime: data.uptime as number,
      state: data.state as string,
      standaloneMode: (data.standaloneMode as boolean) ?? false,
      partnerInstanceId: data.partnerInstanceId as string | undefined,
      partnerStatus: data.partnerStatus as string | undefined,
      partnerPid: data.partnerPid as number | undefined,
      managedProcessCount: data.managedProcessCount as number,
      runningProcessCount: data.runningProcessCount as number,
    };
  }
}
