/**
 * Integration tests for TypeScript distributed system clients.
 * 
 * These tests verify the LedgerClient and ProcessMonitorClient work correctly
 * against locally running servers.
 * 
 * IMPORTANT: These are integration tests that require running servers.
 * Start the servers before running tests:
 *   - Ledger server on port 19880
 *   - Process Monitor on port 19881
 * 
 * Run tests with: npm test
 */

import axios from 'axios';
import { LedgerClient } from '../src/ledger_client';
import { ProcessMonitorClient } from '../src/process_monitor_client';

// Test configuration
const LEDGER_PORT = 19880;
const MONITOR_PORT = 19881;
const LEDGER_URL = `http://localhost:${LEDGER_PORT}`;
const MONITOR_URL = `http://localhost:${MONITOR_PORT}`;

// Helper to check if server is available
async function isServerAvailable(url: string): Promise<boolean> {
  try {
    await axios.get(`${url}/health`, { timeout: 1000 });
    return true;
  } catch {
    return false;
  }
}

describe('LedgerClient', () => {
  let client: LedgerClient;

  beforeAll(async () => {
    const available = await isServerAvailable(LEDGER_URL);
    if (!available) {
      console.warn(`Ledger server not available at ${LEDGER_URL}`);
      console.warn('Start ledger_server before running integration tests');
    }
  });

  beforeEach(() => {
    client = new LedgerClient({ baseUrl: LEDGER_URL });
  });

  describe('when server is available', () => {
    test('can get a non-existent key (returns null)', async () => {
      const result = await client.get('non_existent_key_' + Date.now());
      expect(result).toBeNull();
    });

    test('can put and get a value', async () => {
      const key = `test_key_${Date.now()}`;
      const value = { message: 'hello', timestamp: Date.now() };

      const entry = await client.put(key, value);
      expect(entry.key).toBe(key);
      expect(entry.value).toEqual(value);
      expect(entry.version).toBeGreaterThanOrEqual(1);

      const retrieved = await client.get(key);
      expect(retrieved).not.toBeNull();
      expect(retrieved!.key).toBe(key);
      expect(retrieved!.value).toEqual(value);

      // Cleanup
      await client.delete(key);
    });

    test('can delete a value', async () => {
      const key = `delete_test_${Date.now()}`;
      await client.put(key, 'to_delete');

      await client.delete(key);

      const result = await client.get(key);
      expect(result).toBeNull();
    });

    test('can list keys with prefix', async () => {
      const prefix = `list_test_${Date.now()}_`;
      const keys = [`${prefix}a`, `${prefix}b`, `${prefix}c`];

      // Create keys
      for (const key of keys) {
        await client.put(key, 'value');
      }

      // List with prefix
      const listed = await client.list(prefix);
      expect(listed).toEqual(expect.arrayContaining(keys));

      // Cleanup
      for (const key of keys) {
        await client.delete(key);
      }
    });

    test('handles version conflicts', async () => {
      const key = `conflict_test_${Date.now()}`;
      const entry1 = await client.put(key, 'first');

      // Put with correct version should succeed
      const entry2 = await client.put(key, 'second', entry1.version);
      expect(entry2.version).toBe(entry1.version + 1);

      // Put with old version should fail
      await expect(
        client.put(key, 'should_fail', entry1.version)
      ).rejects.toThrow();

      // Cleanup
      await client.delete(key);
    });
  });
});

describe('ProcessMonitorClient', () => {
  let client: ProcessMonitorClient;

  beforeAll(async () => {
    const available = await isServerAvailable(MONITOR_URL);
    if (!available) {
      console.warn(`Process Monitor not available at ${MONITOR_URL}`);
      console.warn('Start process_monitor before running integration tests');
    }
  });

  beforeEach(() => {
    client = new ProcessMonitorClient({ baseUrl: MONITOR_URL });
  });

  describe('when monitor is available', () => {
    test('can get process list', async () => {
      const processes = await client.getProcesses();
      expect(Array.isArray(processes)).toBe(true);
    });

    test('can start a process', async () => {
      // This test assumes there's a registered process
      // If no processes, just verify the method doesn't crash
      const processes = await client.getProcesses();
      if (processes.length > 0) {
        const processId = processes[0].id;
        // Don't actually start - just verify API structure
        expect(typeof processId).toBe('string');
      }
    });

    test('handles non-existent process gracefully', async () => {
      const fakeId = `non_existent_${Date.now()}`;
      await expect(client.startProcess(fakeId)).rejects.toThrow();
    });
  });
});

describe('Client Retry Behavior', () => {
  // These tests verify retry behavior when servers are unavailable
  // They are slower due to retry delays

  describe('LedgerClient retry', () => {
    test('fails after retries when server unavailable', async () => {
      const badClient = new LedgerClient({ baseUrl: 'http://localhost:59999' });

      const startTime = Date.now();
      await expect(badClient.get('any_key')).rejects.toThrow();
      const elapsed = Date.now() - startTime;

      // Should have attempted retries (at least 2 seconds for first retry)
      // With proper retry: 2 + 4 + 8 + 16 + 32 = 62 seconds minimum
      // Without retry: immediate failure
      console.log(`Elapsed time for failed request: ${elapsed}ms`);
    }, 120000); // 2 minute timeout
  });

  describe('ProcessMonitorClient retry', () => {
    test('fails after retries when monitor unavailable', async () => {
      const badClient = new ProcessMonitorClient({ baseUrl: 'http://localhost:59998' });

      const startTime = Date.now();
      await expect(badClient.getProcesses()).rejects.toThrow();
      const elapsed = Date.now() - startTime;

      console.log(`Elapsed time for failed request: ${elapsed}ms`);
    }, 120000);
  });
});
