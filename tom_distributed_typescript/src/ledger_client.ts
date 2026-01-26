import axios, { AxiosInstance } from 'axios';

export interface LedgerOptions {
  baseUrl?: string;
}

export interface LedgerEntry {
  key: string;
  value: any;
  version: number;
}

export class LedgerClient {
  private client: AxiosInstance;

  constructor(options: LedgerOptions = {}) {
    this.client = axios.create({
      baseURL: options.baseUrl || 'http://localhost:19880',
    });
  }

  /**
   * Gets a value from the ledger.
   * @param key The key to look up.
   */
  async get(key: string): Promise<LedgerEntry | null> {
    try {
      const response = await this.client.get(`/api/v1/entries/${key}`);
      return response.data as LedgerEntry;
    } catch (error: any) {
      if (error.response && error.response.status === 404) {
        return null;
      }
      throw error;
    }
  }

  /**
   * Puts a value into the ledger.
   * @param key The key to update.
   * @param value The value to store.
   * @param expectedVersion Optional concurrent modification check.
   */
  async put(key: string, value: any, expectedVersion?: number): Promise<LedgerEntry> {
    const response = await this.client.put(`/api/v1/entries/${key}`, {
      value,
      expectedVersion,
    });
    return response.data as LedgerEntry;
  }

  /**
   * Deletes a value from the ledger.
   * @param key The key to delete.
   */
  async delete(key: string): Promise<void> {
    await this.client.delete(`/api/v1/entries/${key}`);
  }

  /**
   * Lists keys with an optional prefix.
   * @param prefix Key prefix filter.
   */
  async list(prefix?: string): Promise<string[]> {
    const params = prefix ? { prefix } : {};
    const response = await this.client.get('/api/v1/keys', { params });
    return response.data.keys as string[];
  }
}
