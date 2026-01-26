import axios, { AxiosInstance } from 'axios';
import axiosRetry, { isNetworkOrIdempotentRequestError } from 'axios-retry';

export interface MonitorOptions {
  baseUrl?: string;
  /** Enable retry with exponential backoff (2, 4, 8, 16, 32 seconds) */
  enableRetry?: boolean;
}

export interface ProcessStatus {
  id: string;
  name: string;
  state: 'running' | 'stopped' | 'crashed' | 'disabled' | 'failed' | 'starting' | 'unknown';
  pid?: number;
  uptime?: number;
}

/** Default retry delays in milliseconds: 2, 4, 8, 16, 32 seconds */
const DEFAULT_RETRY_DELAYS = [2000, 4000, 8000, 16000, 32000];

export class ProcessMonitorClient {
  private client: AxiosInstance;

  constructor(options: MonitorOptions = {}) {
    this.client = axios.create({
      baseURL: options.baseUrl || 'http://localhost:19881',
    });

    // Configure retry with exponential backoff
    if (options.enableRetry !== false) {
      axiosRetry(this.client, {
        retries: DEFAULT_RETRY_DELAYS.length,
        retryDelay: (retryCount: number) => {
          // Use configured delays (2, 4, 8, 16, 32 seconds)
          const delay = DEFAULT_RETRY_DELAYS[retryCount - 1] || DEFAULT_RETRY_DELAYS[DEFAULT_RETRY_DELAYS.length - 1];
          console.log(`Retry attempt ${retryCount}, waiting ${delay}ms...`);
          return delay;
        },
        retryCondition: (error: any) => {
          // Retry on network errors or 5xx server errors
          return isNetworkOrIdempotentRequestError(error) || 
                 (error.response?.status ?? 0) >= 500;
        },
      });
    }
  }

  /**
   * Gets the status of all managed processes.
   */
  async getProcesses(): Promise<ProcessStatus[]> {
    const response = await this.client.get('/api/v1/processes');
    return response.data.processes as ProcessStatus[];
  }

  /**
   * Starts a process by ID.
   * @param processId The ID of the process to start.
   */
  async startProcess(processId: string): Promise<void> {
    await this.client.post(`/api/v1/processes/${processId}/start`);
  }

  /**
   * Stops a process by ID.
   * @param processId The ID of the process to stop.
   */
  async stopProcess(processId: string): Promise<void> {
    await this.client.post(`/api/v1/processes/${processId}/stop`);
  }

  /**
   * Restarts a process by ID.
   * @param processId The ID of the process to restart.
   */
  async restartProcess(processId: string): Promise<void> {
    await this.client.post(`/api/v1/processes/${processId}/restart`);
  }
}
