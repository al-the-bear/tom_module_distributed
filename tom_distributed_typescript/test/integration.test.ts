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

import { 
  LedgerClient,
  ProcessMonitorClient,
  RetryExhaustedException,
  DiscoveryFailedException,
  DEFAULT_LEDGER_PORT,
  DEFAULT_PROCESS_MONITOR_PORT,
  Operation,
  Call,
  SpawnedCall,
} from '../src';

// Test configuration
const LEDGER_URL = `http://localhost:${DEFAULT_LEDGER_PORT}`;
const MONITOR_URL = `http://localhost:${DEFAULT_PROCESS_MONITOR_PORT}`;

// Helper to check if server is available
async function isServerAvailable(url: string, healthPath: string = '/health'): Promise<boolean> {
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 2000);
    try {
      const response = await fetch(`${url}${healthPath}`, {
        signal: controller.signal,
      });
      return response.ok || response.status === 200;
    } finally {
      clearTimeout(timeoutId);
    }
  } catch {
    return false;
  }
}

// ─────────────────────────────────────────────────────────────
// Ledger Client Tests
// ─────────────────────────────────────────────────────────────

describe('LedgerClient', () => {
  let client: LedgerClient;
  let ledgerAvailable: boolean;
  
  beforeAll(async () => {
    ledgerAvailable = await isServerAvailable(LEDGER_URL);
    if (!ledgerAvailable) {
      console.warn(`Ledger server not available at ${LEDGER_URL}`);
      console.warn('Start ledger_server before running integration tests');
    }
  });
  
  beforeEach(() => {
    client = new LedgerClient({
      baseUrl: LEDGER_URL,
      participantId: `test_client_${Date.now()}`,
    });
  });
  
  afterEach(() => {
    client.dispose();
  });
  
  describe('when server is available', () => {
    test('can check health', async () => {
      if (!ledgerAvailable) {
        console.log('Skipping: Ledger server not available');
        return;
      }
      
      const healthy = await client.isHealthy();
      expect(healthy).toBe(true);
    });
    
    test('can get server status', async () => {
      if (!ledgerAvailable) {
        console.log('Skipping: Ledger server not available');
        return;
      }
      
      const status = await client.getStatus();
      expect(status.service).toBe('tom_dist_ledger');
      expect(status.status).toBe('ok');
      expect(status.port).toBe(DEFAULT_LEDGER_PORT);
    });
    
    test('can create and complete an operation', async () => {
      if (!ledgerAvailable) {
        console.log('Skipping: Ledger server not available');
        return;
      }
      
      // Create operation
      const operation = await client.createOperation({
        description: 'Test operation',
      });
      
      expect(operation.operationId).toBeDefined();
      expect(operation.participantId).toBe(client.participantId);
      expect(operation.isInitiator).toBe(true);
      
      // Get state
      const state = await client.getOperationState(operation.operationId);
      expect(state.operationId).toBe(operation.operationId);
      expect(state.aborted).toBe(false);
      
      // Complete operation
      await client.completeOperation(operation.operationId);
    });
    
    test('can send heartbeat', async () => {
      if (!ledgerAvailable) {
        console.log('Skipping: Ledger server not available');
        return;
      }
      
      const operation = await client.createOperation();
      
      const heartbeat = await client.heartbeat(operation.operationId);
      expect(heartbeat.success).toBe(true);
      
      await client.completeOperation(operation.operationId);
    });
    
    test('can log messages', async () => {
      if (!ledgerAvailable) {
        console.log('Skipping: Ledger server not available');
        return;
      }
      
      const operation = await client.createOperation();
      
      await client.log(operation.operationId, 'Test log message', 'info');
      await client.log(operation.operationId, 'Warning message', 'warning');
      
      await client.completeOperation(operation.operationId);
    });
    
    test('can start and end calls', async () => {
      if (!ledgerAvailable) {
        console.log('Skipping: Ledger server not available');
        return;
      }
      
      const operation = await client.createOperation();
      
      // Start a call
      const call = await client.startCall(operation.operationId, {
        description: 'Test call',
      });
      expect(call.callId).toBeDefined();
      expect(call.startedAt).toBeInstanceOf(Date);
      
      // End the call
      await client.endCall(operation.operationId, call.callId);
      
      await client.completeOperation(operation.operationId);
    });
    
    test('can set abort flag', async () => {
      if (!ledgerAvailable) {
        console.log('Skipping: Ledger server not available');
        return;
      }
      
      const operation = await client.createOperation();
      
      await client.setAbortFlag(operation.operationId, true);
      
      const state = await client.getOperationState(operation.operationId);
      expect(state.aborted).toBe(true);
      
      await client.completeOperation(operation.operationId);
    });
  });
  
  describe('retry behavior', () => {
    test('fails after retries when server unavailable', async () => {
      // Use a port that's definitely not running
      // Uses production delays: 2 + 4 + 8 + 16 + 32 = 62 seconds
      const badClient = new LedgerClient({
        baseUrl: 'http://localhost:19999',
        enableRetry: true,
        // Use production delays for realistic integration testing
      });
      
      const startTime = Date.now();
      
      await expect(badClient.getStatus()).rejects.toThrow(RetryExhaustedException);
      
      const elapsed = Date.now() - startTime;
      // Should have waited at least 62 seconds (2 + 4 + 8 + 16 + 32)
      expect(elapsed).toBeGreaterThanOrEqual(60000);
      console.log(`Ledger retry exhausted after ${elapsed}ms`);
      
      badClient.dispose();
    }, 120000); // 2 minute timeout for production retries
  });
  
  describe('high-level Operation API', () => {
    test('can create operation with getOperation', async () => {
      if (!ledgerAvailable) {
        console.log('Skipping: Ledger server not available');
        return;
      }
      
      const operation = await client.getOperation({
        description: 'Test high-level operation',
        autoHeartbeat: false, // Disable for testing
      });
      
      expect(operation).toBeInstanceOf(Operation);
      expect(operation.operationId).toBeDefined();
      expect(operation.participantId).toBe(client.participantId);
      expect(operation.isInitiator).toBe(true);
      expect(operation.sessionId).toBeDefined();
      expect(operation.startTime).toBeInstanceOf(Date);
      expect(operation.isAborted).toBe(false);
      
      await operation.complete();
    });
    
    test('can use Call objects', async () => {
      if (!ledgerAvailable) {
        console.log('Skipping: Ledger server not available');
        return;
      }
      
      const operation = await client.getOperation({
        autoHeartbeat: false,
      });
      
      // Start a typed call
      const call = await operation.startCall<number>({
        description: 'Test call with result',
      });
      
      expect(call).toBeInstanceOf(Call);
      expect(call.callId).toBeDefined();
      expect(call.startedAt).toBeInstanceOf(Date);
      expect(call.isCompleted).toBe(false);
      
      // End with result
      await call.end(42);
      expect(call.isCompleted).toBe(true);
      
      await operation.complete();
    });
    
    test('can fail a Call', async () => {
      if (!ledgerAvailable) {
        console.log('Skipping: Ledger server not available');
        return;
      }
      
      const operation = await client.getOperation({
        autoHeartbeat: false,
      });
      
      const call = await operation.startCall<string>();
      
      await call.fail(new Error('Test failure'));
      expect(call.isCompleted).toBe(true);
      
      await operation.complete();
    });
    
    test('can use SpawnedCall', async () => {
      if (!ledgerAvailable) {
        console.log('Skipping: Ledger server not available');
        return;
      }
      
      const operation = await client.getOperation({
        autoHeartbeat: false,
      });
      
      // Spawn a call
      const spawnedCall = operation.spawnCall<string>({
        work: async () => {
          await new Promise(r => setTimeout(r, 100));
          return 'completed';
        },
        description: 'Test spawned call',
      });
      
      expect(spawnedCall).toBeInstanceOf(SpawnedCall);
      expect(spawnedCall.callId).toBeDefined();
      
      // Wait for completion
      await spawnedCall.future;
      
      expect(spawnedCall.isCompleted).toBe(true);
      expect(spawnedCall.isSuccess).toBe(true);
      expect(spawnedCall.result).toBe('completed');
      
      await operation.complete();
    });
    
    test('SpawnedCall can be cancelled', async () => {
      if (!ledgerAvailable) {
        console.log('Skipping: Ledger server not available');
        return;
      }
      
      const operation = await client.getOperation({
        autoHeartbeat: false,
      });
      
      let workCompleted = false;
      
      const spawnedCall = operation.spawnCall<string>({
        work: async (call: SpawnedCall<string>) => {
          for (let i = 0; i < 100; i++) {
            if (call.isCancelled) {
              return 'cancelled';
            }
            await new Promise(r => setTimeout(r, 10));
          }
          workCompleted = true;
          return 'completed';
        },
      });
      
      // Wait a bit then cancel
      await new Promise(r => setTimeout(r, 50));
      await spawnedCall.cancel();
      
      // Wait for completion
      await spawnedCall.future;
      
      expect(spawnedCall.isCancelled).toBe(true);
      expect(workCompleted).toBe(false);
      
      await operation.complete();
    });
    
    test('can sync multiple spawned calls', async () => {
      if (!ledgerAvailable) {
        console.log('Skipping: Ledger server not available');
        return;
      }
      
      const operation = await client.getOperation({
        autoHeartbeat: false,
      });
      
      const call1 = operation.spawnCall<number>({
        work: async () => {
          await new Promise(r => setTimeout(r, 50));
          return 1;
        },
      });
      
      const call2 = operation.spawnCall<number>({
        work: async () => {
          await new Promise(r => setTimeout(r, 100));
          return 2;
        },
      });
      
      const result = await operation.sync([call1, call2]);
      
      expect(result.successfulCalls.length).toBe(2);
      expect(result.failedCalls.length).toBe(0);
      expect(result.operationFailed).toBe(false);
      
      expect(call1.result).toBe(1);
      expect(call2.result).toBe(2);
      
      await operation.complete();
    });
    
    test('can log to operation', async () => {
      if (!ledgerAvailable) {
        console.log('Skipping: Ledger server not available');
        return;
      }
      
      const operation = await client.getOperation({
        autoHeartbeat: false,
      });
      
      await operation.log('Test info message', 'info');
      await operation.log('Test warning', 'warning');
      
      await operation.complete();
    });
    
    test('elapsed time tracking', async () => {
      if (!ledgerAvailable) {
        console.log('Skipping: Ledger server not available');
        return;
      }
      
      const operation = await client.getOperation({
        autoHeartbeat: false,
      });
      
      await new Promise(r => setTimeout(r, 100));
      
      const elapsed = operation.elapsedDuration;
      expect(elapsed).toBeGreaterThanOrEqual(100);
      
      const formatted = operation.elapsedFormatted;
      expect(formatted).toMatch(/^\d{3}\.\d{3}$/);
      
      await operation.complete();
    });
    
    test('manual heartbeat', async () => {
      if (!ledgerAvailable) {
        console.log('Skipping: Ledger server not available');
        return;
      }
      
      const operation = await client.getOperation({
        autoHeartbeat: false,
      });
      
      const result = await operation.heartbeat();
      expect(result).not.toBeNull();
      expect(result!.ledgerExists).toBe(true);
      expect(result!.heartbeatUpdated).toBe(true);
      
      await operation.complete();
    });
    
    test('can set abort flag via operation', async () => {
      if (!ledgerAvailable) {
        console.log('Skipping: Ledger server not available');
        return;
      }
      
      const operation = await client.getOperation({
        autoHeartbeat: false,
      });
      
      await operation.setAbortFlag(true);
      
      const isAborted = await operation.checkAbort();
      expect(isAborted).toBe(true);
      expect(operation.isAborted).toBe(true);
      
      await operation.complete();
    });
  });
});

// ─────────────────────────────────────────────────────────────
// Process Monitor Client Tests
// ─────────────────────────────────────────────────────────────

describe('ProcessMonitorClient', () => {
  let client: ProcessMonitorClient;
  let monitorAvailable: boolean;
  
  beforeAll(async () => {
    monitorAvailable = await isServerAvailable(MONITOR_URL, '/monitor/status');
    if (!monitorAvailable) {
      console.warn(`Process Monitor not available at ${MONITOR_URL}`);
      console.warn('Start process_monitor before running integration tests');
    }
  });
  
  beforeEach(() => {
    client = new ProcessMonitorClient({
      baseUrl: MONITOR_URL,
    });
  });
  
  afterEach(() => {
    client.dispose();
  });
  
  describe('when monitor is available', () => {
    test('can get monitor status', async () => {
      if (!monitorAvailable) {
        console.log('Skipping: Process Monitor not available');
        return;
      }
      
      const status = await client.getMonitorStatus();
      expect(status.instanceId).toBeDefined();
      expect(status.pid).toBeGreaterThan(0);
      expect(status.state).toBe('running');
      expect(status.startedAt).toBeInstanceOf(Date);
    });
    
    test('can get all process statuses', async () => {
      if (!monitorAvailable) {
        console.log('Skipping: Process Monitor not available');
        return;
      }
      
      const statuses = await client.getAllStatus();
      expect(statuses).toBeInstanceOf(Map);
    });
    
    test('can register, start, stop, and deregister a process', async () => {
      if (!monitorAvailable) {
        console.log('Skipping: Process Monitor not available');
        return;
      }
      
      const processId = `test_process_${Date.now()}`;
      
      try {
        // Register
        await client.register({
          id: processId,
          name: 'Test Process',
          command: '/bin/sleep',
          args: ['10'],
          autostart: false,
        });
        
        // Verify registered
        const statuses = await client.getAllStatus();
        expect(statuses.has(processId)).toBe(true);
        
        // Start
        await client.start(processId);
        await new Promise(r => setTimeout(r, 500));
        
        // Check running
        const status = await client.getStatus(processId);
        expect(status.state).toBe('running');
        expect(status.pid).toBeGreaterThan(0);
        
        // Stop
        await client.stop(processId);
        await new Promise(r => setTimeout(r, 500));
        
        // Check stopped
        const stoppedStatus = await client.getStatus(processId);
        expect(stoppedStatus.state).toBe('stopped');
      } finally {
        // Cleanup
        try {
          await client.deregister(processId);
        } catch {
          // Ignore cleanup errors
        }
      }
    }, 15000);
    
    test('can enable and disable a process', async () => {
      if (!monitorAvailable) {
        console.log('Skipping: Process Monitor not available');
        return;
      }
      
      const processId = `toggle_process_${Date.now()}`;
      
      try {
        await client.register({
          id: processId,
          name: 'Toggle Process',
          command: '/bin/echo',
          args: ['test'],
          autostart: false,
        });
        
        // Disable
        await client.disable(processId);
        let status = await client.getStatus(processId);
        expect(status.state).toBe('disabled');
        
        // Enable
        await client.enable(processId);
        status = await client.getStatus(processId);
        expect(status.state).not.toBe('disabled');
      } finally {
        try {
          await client.deregister(processId);
        } catch {
          // Ignore cleanup errors
        }
      }
    });
    
    test('can set autostart', async () => {
      if (!monitorAvailable) {
        console.log('Skipping: Process Monitor not available');
        return;
      }
      
      const processId = `autostart_process_${Date.now()}`;
      
      try {
        await client.register({
          id: processId,
          name: 'Autostart Process',
          command: '/bin/echo',
          args: ['test'],
          autostart: false,
        });
        
        // Set autostart
        await client.setAutostart(processId, true);
        const status = await client.getStatus(processId);
        expect(status.autostart).toBe(true);
        
        // Unset autostart
        await client.setAutostart(processId, false);
        const status2 = await client.getStatus(processId);
        expect(status2.autostart).toBe(false);
      } finally {
        try {
          await client.deregister(processId);
        } catch {
          // Ignore cleanup errors
        }
      }
    });
  });
  
  describe('retry behavior', () => {
    test('fails after retries when monitor unavailable', async () => {
      // Use a port that's definitely not running
      // Uses production delays: 2 + 4 + 8 + 16 + 32 = 62 seconds
      const badClient = new ProcessMonitorClient({
        baseUrl: 'http://localhost:19999',
        enableRetry: true,
        // Use production delays for realistic integration testing
      });
      
      const startTime = Date.now();
      
      await expect(badClient.getMonitorStatus()).rejects.toThrow(RetryExhaustedException);
      
      const elapsed = Date.now() - startTime;
      // Should have waited at least 62 seconds (2 + 4 + 8 + 16 + 32)
      expect(elapsed).toBeGreaterThanOrEqual(60000);
      console.log(`Monitor retry exhausted after ${elapsed}ms`);
      
      badClient.dispose();
    }, 120000); // 2 minute timeout for production retries
  });
  
  describe('discovery', () => {
    test('can discover local monitor', async () => {
      if (!monitorAvailable) {
        console.log('Skipping: Process Monitor not available');
        return;
      }
      
      const discovered = await ProcessMonitorClient.discover({
        timeout: 2000,
      });
      
      expect(discovered.baseUrl).toContain('localhost');
      
      const status = await discovered.getMonitorStatus();
      expect(status.state).toBe('running');
      
      discovered.dispose();
    });
    
    test('throws DiscoveryFailedException when no monitor found', async () => {
      await expect(
        ProcessMonitorClient.discover({
          port: 19999, // Unused port
          timeout: 500,
        })
      ).rejects.toThrow(DiscoveryFailedException);
    }, 10000);
  });
});

// ─────────────────────────────────────────────────────────────
// HTTP Retry Tests
// ─────────────────────────────────────────────────────────────

describe('HTTP Retry', () => {
  test('retries with correct delays (production: 2, 4, 8, 16, 32 seconds)', async () => {
    const retryDelays: number[] = [];
    const startTime = Date.now();
    
    const badClient = new LedgerClient({
      baseUrl: 'http://localhost:19999',
      enableRetry: true,
      retryConfig: {
        // Production delays: allows time for process monitor to restart crashed services
        onRetry: (attempt: number, _error: unknown, delayMs: number) => {
          const elapsed = Date.now() - startTime;
          retryDelays.push(delayMs);
          console.log(`Retry ${attempt}: elapsed ${elapsed}ms, waiting ${delayMs}ms`);
        },
      },
    });
    
    await expect(badClient.getStatus()).rejects.toThrow(RetryExhaustedException);
    
    // Should have 5 retries with production delays
    expect(retryDelays.length).toBe(5);
    
    // Verify the retry delays match production configuration: 2, 4, 8, 16, 32 seconds
    expect(retryDelays[0]).toBe(2000);
    expect(retryDelays[1]).toBe(4000);
    expect(retryDelays[2]).toBe(8000);
    expect(retryDelays[3]).toBe(16000);
    expect(retryDelays[4]).toBe(32000);
    
    const totalElapsed = Date.now() - startTime;
    console.log(`Total retry time: ${totalElapsed}ms (expected ~62s)`);
    // Total: 2 + 4 + 8 + 16 + 32 = 62 seconds
    expect(totalElapsed).toBeGreaterThanOrEqual(62000);
    
    badClient.dispose();
  }, 120000); // 2 minute timeout
});
