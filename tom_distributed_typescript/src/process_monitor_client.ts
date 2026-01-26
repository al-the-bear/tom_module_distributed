import axios, { AxiosInstance } from 'axios';

export interface MonitorOptions {
  baseUrl?: string;
}

export interface ProcessStatus {
  id: string;
  name: string;
  state: 'running' | 'stopped' | 'crashed' | 'disabled' | 'failed' | 'starting' | 'unknown';
  pid?: number;
  uptime?: number;
}

export class ProcessMonitorClient {
  private client: AxiosInstance;

  constructor(options: MonitorOptions = {}) {
    this.client = axios.create({
      baseURL: options.baseUrl || 'http://localhost:19881',
    });
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
