# Tom Distributed TypeScript User Guide

This guide provides detailed documentation for using the TypeScript clients to interact with the Tom Distributed System components: the Ledger Server and the Process Monitor.

## Table of Contents

- [Tom Distributed TypeScript User Guide](#tom-distributed-typescript-user-guide)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Installation](#installation)
  - [Quick Start](#quick-start)
    - [Connecting to the Ledger](#connecting-to-the-ledger)
    - [Connecting to the Process Monitor](#connecting-to-the-process-monitor)
  - [LedgerClient API](#ledgerclient-api)
    - [Creating a Ledger Client](#creating-a-ledger-client)
    - [Ledger Auto-Discovery](#ledger-auto-discovery)
    - [High-Level Operation API (Recommended)](#high-level-operation-api-recommended)
      - [Creating an Operation](#creating-an-operation)
      - [Using Call Objects](#using-call-objects)
      - [Using SpawnedCall for Async Work](#using-spawnedcall-for-async-work)
      - [Heartbeat Management](#heartbeat-management)
      - [Abort and Failure Handling](#abort-and-failure-handling)
      - [Syncing Multiple Calls](#syncing-multiple-calls)
      - [Wrapping Callback-Based APIs](#wrapping-callback-based-apis)
    - [Low-Level Operations API](#low-level-operations-api)
      - [Create an Operation](#create-an-operation)
      - [Join an Existing Operation](#join-an-existing-operation)
      - [Leave an Operation](#leave-an-operation)
      - [Complete an Operation](#complete-an-operation)
    - [Heartbeat and State](#heartbeat-and-state)
      - [Send a Heartbeat](#send-a-heartbeat)
      - [Check Operation State](#check-operation-state)
      - [Set Abort Flag](#set-abort-flag)
    - [Logging](#logging)
    - [Call Tracking (Low-Level)](#call-tracking-low-level)
    - [Health and Status](#health-and-status)
  - [ProcessMonitorClient API](#processmonitorclient-api)
    - [Creating a ProcessMonitor Client](#creating-a-processmonitor-client)
    - [ProcessMonitor Auto-Discovery](#processmonitor-auto-discovery)
    - [Process Registration](#process-registration)
    - [Process Control](#process-control)
      - [Start, Stop, Restart](#start-stop-restart)
      - [Enable and Disable](#enable-and-disable)
      - [Autostart Configuration](#autostart-configuration)
    - [Status Monitoring](#status-monitoring)
      - [Get Single Process Status](#get-single-process-status)
      - [Get All Processes Status](#get-all-processes-status)
      - [Get Monitor Status](#get-monitor-status)
    - [Configuration Management](#configuration-management)
      - [Remote Access](#remote-access)
      - [Trusted Hosts](#trusted-hosts)
      - [Executable Filtering](#executable-filtering)
      - [Standalone Mode and Partner Discovery](#standalone-mode-and-partner-discovery)
      - [Restart Monitor](#restart-monitor)
  - [Retry Handling](#retry-handling)
    - [Default Retry Configuration](#default-retry-configuration)
    - [Custom Retry Configuration](#custom-retry-configuration)
    - [Disabling Retry](#disabling-retry)
  - [Error Handling](#error-handling)
    - [Common Exceptions](#common-exceptions)
    - [Example Error Handling](#example-error-handling)
  - [Platform Compatibility](#platform-compatibility)
    - [Browser Limitations](#browser-limitations)
    - [Using in Different Environments](#using-in-different-environments)
  - [Default Ports](#default-ports)
  - [Best Practices](#best-practices)
  - [See Also](#see-also)

---

## Overview

The Tom Distributed TypeScript package provides cross-platform TypeScript clients for:

1. **LedgerClient** - Communicates with the Distributed Ledger Server for managing distributed operations, call tracking, heartbeats, and logging.

2. **ProcessMonitorClient** - Communicates with the Process Monitor for managing and monitoring system processes.

Both clients include:
- Automatic retry with exponential backoff (2, 4, 8, 16, 32 seconds)
- Network auto-discovery
- Full TypeScript types
- Cross-platform support (Node.js, Deno, browsers, VS Code extensions)

---

## Installation

```bash
npm install tom_distributed_typescript
```

Or with yarn:

```bash
yarn add tom_distributed_typescript
```

---

## Quick Start

### Connecting to the Ledger

```typescript
import { LedgerClient } from 'tom_distributed_typescript';

// Create client with explicit URL
const ledger = new LedgerClient({
  baseUrl: 'http://localhost:19880',
  participantId: 'my_service',
});

// Or use auto-discovery
const ledger = await LedgerClient.discover();

// Create an operation with high-level API (recommended)
const operation = await ledger.getOperation({
  description: 'Process payment',
});

// Start a tracked call
const call = await operation.startCall<number>();
try {
  const result = await processPayment();
  await call.end(result);
} catch (e) {
  await call.fail(e);
}

// Complete the operation
await operation.complete();

// Clean up
ledger.dispose();
```

### Connecting to the Process Monitor

```typescript
import { ProcessMonitorClient } from 'tom_distributed_typescript';

// Create client with explicit URL
const monitor = new ProcessMonitorClient({
  baseUrl: 'http://localhost:19881',
});

// Or use auto-discovery
const monitor = await ProcessMonitorClient.discover();

// Get status of all managed processes
const statuses = await monitor.getAllStatus();
for (const [id, status] of statuses) {
  console.log(`${id}: ${status.state}`);
}

// Clean up
monitor.dispose();
```

---

## LedgerClient API

The Ledger system manages distributed operations with support for:
- Operation lifecycle (create, join, leave, complete)
- Call tracking (start, end, fail)
- Heartbeat monitoring
- Distributed logging

### Creating a Ledger Client

```typescript
import { LedgerClient } from 'tom_distributed_typescript';

const client = new LedgerClient({
  // Server URL (default: http://localhost:19880)
  baseUrl: 'http://localhost:19880',
  
  // Unique identifier for this participant (auto-generated if not provided)
  participantId: 'my_service_instance_1',
  
  // Process ID (auto-detected in Node.js)
  participantPid: process.pid,
  
  // Enable retry with exponential backoff (default: true)
  enableRetry: true,
  
  // Request timeout in milliseconds (default: 30000)
  timeout: 30000,
  
  // Custom retry configuration
  retryConfig: {
    retryDelaysMs: [2000, 4000, 8000, 16000, 32000],
    onRetry: (attempt, error, delayMs) => {
      console.log(`Retry ${attempt}: waiting ${delayMs}ms`);
    },
  },
});
```

### Ledger Auto-Discovery

The client can automatically find a Ledger server on the network:

```typescript
// Auto-discover with defaults
const client = await LedgerClient.discover();

// With options
const client = await LedgerClient.discover({
  port: 19880,
  timeout: 5000,
  participantId: 'my_service',
});

// Scan a specific subnet
const servers = await LedgerClient.scanSubnet('192.168.1', {
  port: 19880,
  timeout: 500,
});
console.log('Found servers:', servers);
```

Discovery order:
1. Try `localhost` on default port (19880)
2. Try `127.0.0.1` on default port
3. Try all local machine IP addresses
4. Scan all /24 subnets for each local IP

### High-Level Operation API (Recommended)

The high-level API provides `Operation`, `Call<T>`, and `SpawnedCall<T>` objects that mirror the Dart implementation. This is the recommended approach for most use cases.

#### Creating an Operation

```typescript
import { LedgerClient, Operation, OperationCallback } from 'tom_distributed_typescript';

const client = await LedgerClient.discover();

// Create operation with full Operation object
const operation = await client.getOperation({
  description: 'Process payment',
  autoHeartbeat: true,         // Automatically send heartbeats (default: true)
  heartbeatIntervalMs: 4500,   // Heartbeat interval (default: 4500ms)
  callback: {
    onHeartbeatSuccess: (op, result) => {
      console.log('Heartbeat OK, participants:', result.participants);
    },
    onHeartbeatError: (op, error) => {
      console.log('Heartbeat error:', error.message);
    },
    onAbort: (op) => {
      console.log('Operation was aborted');
    },
    onFailure: (op, info) => {
      console.log('Operation failed:', info.reason);
    },
  },
});

console.log('Operation ID:', operation.operationId);
console.log('Session ID:', operation.sessionId);
console.log('Is initiator:', operation.isInitiator);
console.log('Elapsed:', operation.elapsedFormatted); // e.g., "005.123"
```

#### Using Call Objects

The `Call<T>` class tracks synchronous work within an operation:

```typescript
// Start a typed call
const call = await operation.startCall<number>({
  description: 'Calculate total',
  failOnCrash: true,  // Mark operation failed if process crashes (default: true)
  callback: {
    onCleanup: async () => {
      // Called when call fails - cleanup resources
      console.log('Cleaning up after failure');
    },
    onCompletion: async (result) => {
      // Called when call ends successfully
      console.log('Completed with result:', result);
    },
  },
});

console.log('Call ID:', call.callId);
console.log('Started at:', call.startedAt);

try {
  const total = calculateTotal();
  await call.end(total);  // End with typed result
} catch (e) {
  await call.fail(e);     // Mark as failed
}
```

#### Using SpawnedCall for Async Work

`SpawnedCall<T>` runs work asynchronously with cancellation support:

```typescript
// Spawn an async call that can be cancelled
const spawnedCall = operation.spawnCall<string>({
  work: async (call, op) => {
    // Check for cancellation periodically
    for (let i = 0; i < 10; i++) {
      if (call.isCancelled) {
        return 'cancelled';
      }
      await doChunk(i);
    }
    return 'completed';
  },
  description: 'Background processing',
  callback: {
    onCleanup: async () => {
      console.log('Cleanup called');
    },
    onCompletion: async (result) => {
      console.log('Work completed:', result);
    },
    onCallCrashed: async () => {
      // Return a fallback value on crash
      return 'fallback-value';
    },
  },
});

// The call runs in the background
console.log('Spawned call ID:', spawnedCall.callId);

// Wait for completion
await spawnedCall.future;

// Check results
if (spawnedCall.isSuccess) {
  console.log('Result:', spawnedCall.result);
} else if (spawnedCall.isFailed) {
  console.log('Error:', spawnedCall.error);
} else if (spawnedCall.isCancelled) {
  console.log('Was cancelled');
}

// Or use await() which throws on failure
try {
  const result = await spawnedCall.await();
} catch (e) {
  console.log('Call failed:', e);
}
```

**Cancellation:**

```typescript
// Request cancellation
await spawnedCall.cancel();

// The work function should check call.isCancelled
```

#### Heartbeat Management

```typescript
// Start automatic heartbeat (usually done via autoHeartbeat option)
operation.startHeartbeat({
  intervalMs: 4500,
  jitterMs: 500,  // Random jitter to avoid thundering herd
  onSuccess: (op, result) => {
    console.log('Heartbeat age:', result.heartbeatAgeMs, 'ms');
  },
  onError: (op, error) => {
    if (error.type === 'abortFlagSet') {
      // Handle abort
    }
  },
});

// Stop automatic heartbeat
operation.stopHeartbeat();

// Manual heartbeat
const result = await operation.heartbeat();
if (result) {
  console.log('Participants:', result.participants);
}
```

#### Abort and Failure Handling

```typescript
// React to abort
operation.onAbort.then(() => {
  console.log('Operation was aborted!');
  // Cleanup and stop work
});

// React to failure
operation.onFailure.then((info) => {
  console.log('Operation failed:', info.reason);
  console.log('Crashed calls:', info.crashedCallIds);
});

// Check abort status
const isAborted = await operation.checkAbort();

// Trigger local abort (stops heartbeat, notifies listeners)
operation.triggerAbort();

// Set abort flag on server (other participants will see this)
await operation.setAbortFlag(true);
```

#### Syncing Multiple Calls

Wait for multiple spawned calls to complete:

```typescript
const call1 = operation.spawnCall({ work: async () => fetchData1() });
const call2 = operation.spawnCall({ work: async () => fetchData2() });
const call3 = operation.spawnCall({ work: async () => fetchData3() });

// Wait for all calls
const result = await operation.sync([call1, call2, call3], {
  onOperationFailed: async (info) => {
    console.log('Operation failed during sync:', info.reason);
  },
  onCompletion: async () => {
    console.log('All calls completed successfully');
  },
});

console.log('Successful:', result.successfulCalls.length);
console.log('Failed:', result.failedCalls.length);
console.log('Unknown:', result.unknownCalls.length);
console.log('Operation failed:', result.operationFailed);
```

**Complete the operation:**

```typescript
// Leave this session (if not initiator)
await operation.leave({ cancelPendingCalls: false });

// Complete the operation (initiator only)
await operation.complete();
```

#### Wrapping Callback-Based APIs

When working with callback-based APIs (event emitters, WebSocket responses, etc.), wrap them in a Promise that resolves when the callback fires:

```typescript
// Example: API that delivers results via callback
interface SomeApi {
  startWork(options: {
    onProgress: (percent: number) => void;
    onResult: (result: string) => void;
    onError: (error: Error) => void;
  }): { cancel: () => void };
}

const spawnedCall = operation.spawnCall<string>({
  work: async (call: SpawnedCall<string>) => {
    // Wrap the callback-based API in a Promise
    return new Promise<string>((resolve, reject) => {
      const handle = someApi.startWork({
        onProgress: (percent) => {
          console.log(`Progress: ${percent}%`);
          // Check for cancellation during progress
          if (call.isCancelled) {
            handle.cancel();
            reject(new Error('Cancelled'));
          }
        },
        onResult: (result) => {
          resolve(result);  // This completes the SpawnedCall
        },
        onError: (error) => {
          reject(error);    // This fails the SpawnedCall
        },
      });
      
      // Wire up cancellation - when cancel() is called on SpawnedCall,
      // it will call this handler
      call.setOnCancel(async () => {
        handle.cancel();
        reject(new Error('Cancelled'));
      });
    });
  },
});

// Now await the result normally
const result = await spawnedCall.await();
```

**WebSocket Response Example:**

```typescript
const spawnedCall = operation.spawnCall<ResponseMessage>({
  work: async (call: SpawnedCall<ResponseMessage>) => {
    return new Promise<ResponseMessage>((resolve, reject) => {
      const requestId = generateId();
      
      // Set up one-time listener for the response
      const handler = (message: ResponseMessage) => {
        if (message.requestId === requestId) {
          ws.off('message', handler);
          resolve(message);
        }
      };
      
      ws.on('message', handler);
      ws.send({ type: 'request', requestId, ... });
      
      // Handle timeout
      const timeout = setTimeout(() => {
        ws.off('message', handler);
        reject(new Error('Timeout'));
      }, 30000);
      
      // Handle cancellation
      call.setOnCancel(async () => {
        clearTimeout(timeout);
        ws.off('message', handler);
        ws.send({ type: 'cancel', requestId });
        reject(new Error('Cancelled'));
      });
    });
  },
});
```

Key points:
- Use `call.setOnCancel()` to register a cleanup handler that runs when `cancel()` is called
- Wrap callback-based APIs in a `Promise` to bridge to async/await
- Check `call.isCancelled` during long-running operations

> **See also**: For the Dart equivalent, see the [Dart Ledger API User Guide](../../tom_dist_ledger/doc/ledger_api_user_guide.md#wrapping-callback-based-apis).

### Low-Level Operations API

The low-level API provides direct access to server endpoints without the high-level abstractions.

Operations represent distributed work units that span multiple participants.

#### Create an Operation

```typescript
// The creating participant becomes the "initiator"
const operation = await client.createOperation({
  description: 'Process customer order #12345',
});

console.log('Operation ID:', operation.operationId);
console.log('Am I initiator?', operation.isInitiator); // true
console.log('Session ID:', operation.sessionId);
```

#### Join an Existing Operation

```typescript
// Another participant joins the operation
const operationInfo = await client.joinOperation('operation-uuid-here');

console.log('Joined as:', operationInfo.participantId);
console.log('Am I initiator?', operationInfo.isInitiator); // false
```

#### Leave an Operation

```typescript
// Leave without completing (e.g., participant is done with its part)
await client.leaveOperation('operation-uuid-here');
```

#### Complete an Operation

```typescript
// Mark operation as successfully completed
await client.completeOperation('operation-uuid-here');
```

### Heartbeat and State

Heartbeats indicate that a participant is still active. They should be sent periodically during long operations.

#### Send a Heartbeat

```typescript
const result = await client.heartbeat('operation-uuid-here');

console.log('Success:', result.success);
console.log('Abort flag:', result.abortFlag);
console.log('Participants:', result.participants);
console.log('Stale participants:', result.staleParticipants);
```

#### Check Operation State

```typescript
const state = await client.getOperationState('operation-uuid-here');

console.log('State:', state.state); // 'active', 'completed', 'aborted'
console.log('Aborted:', state.aborted);
console.log('Call frame count:', state.callFrameCount);
console.log('Participants:', state.participants);
```

#### Set Abort Flag

Signal that an operation should be aborted:

```typescript
// Set abort flag (other participants will see this in heartbeat)
await client.setAbortFlag('operation-uuid-here', true);

// Clear abort flag
await client.setAbortFlag('operation-uuid-here', false);
```

### Logging

Log messages to the operation's distributed log:

```typescript
// Log levels: 'debug', 'info', 'warning', 'error'
await client.log('operation-uuid-here', 'Starting payment processing', 'info');
await client.log('operation-uuid-here', 'Payment failed: insufficient funds', 'error');
```

### Call Tracking (Low-Level)

For direct call tracking without the high-level `Call` and `SpawnedCall` objects:

```typescript
// Start a call (creates a call frame)
const call = await client.startCall('operation-uuid-here', {
  description: 'POST /api/payment',
  failOnCrash: true, // Mark operation failed if process crashes
});

console.log('Call ID:', call.callId);
console.log('Started at:', call.startedAt);

try {
  // Do the actual work...
  await processPayment();
  
  // End call successfully
  await client.endCall('operation-uuid-here', call.callId);
} catch (error) {
  // Mark call as failed
  await client.failCall('operation-uuid-here', call.callId, error.message);
}
```

### Health and Status

```typescript
// Check if server is reachable
const healthy = await client.isHealthy();

// Get detailed server status
const status = await client.getStatus();
console.log('Service:', status.service);
console.log('Version:', status.version);
console.log('Port:', status.port);
```

---

## ProcessMonitorClient API

The Process Monitor manages and monitors system processes with features for:
- Process registration and lifecycle management
- Automatic restart policies
- Health/aliveness checks
- Partner monitoring (high availability)

### Creating a ProcessMonitor Client

```typescript
import { ProcessMonitorClient } from 'tom_distributed_typescript';

const client = new ProcessMonitorClient({
  // Server URL (default: http://localhost:19881)
  baseUrl: 'http://localhost:19881',
  
  // Target instance ID (default: 'default')
  instanceId: 'default',
  
  // Enable retry with exponential backoff (default: true)
  enableRetry: true,
  
  // Request timeout in milliseconds
  timeout: 30000,
});
```

### ProcessMonitor Auto-Discovery

```typescript
// Auto-discover with defaults
const client = await ProcessMonitorClient.discover();

// With options
const client = await ProcessMonitorClient.discover({
  port: 19881,
  timeout: 5000,
  instanceId: 'default',
});

// Scan a specific subnet
const monitors = await ProcessMonitorClient.scanSubnet('192.168.1', {
  port: 19881,
  timeout: 500,
});
```

### Process Registration

Register a new process to be managed:

```typescript
await client.register({
  // Required fields
  id: 'my_service',
  name: 'My Background Service',
  command: '/usr/local/bin/my_service',
  
  // Optional fields
  args: ['--port', '8080', '--config', '/etc/my_service.yaml'],
  workingDirectory: '/var/lib/my_service',
  environment: {
    NODE_ENV: 'production',
    LOG_LEVEL: 'info',
  },
  autostart: true,
  
  // Restart policy
  restartPolicy: {
    type: 'on-failure', // 'always', 'on-failure', 'never'
    maxAttempts: 5,
    delayMs: 1000,
    maxDelayMs: 30000,
    backoffMultiplier: 2.0,
  },
  
  // HTTP health check
  alivenessCheck: {
    url: 'http://localhost:8080/health',
    intervalMs: 5000,
    timeoutMs: 2000,
    successCodes: [200, 204],
  },
});
```

Remove a registered process:

```typescript
// Must stop the process first if running
await client.stop('my_service');
await client.deregister('my_service');
```

### Process Control

#### Start, Stop, Restart

```typescript
// Start a process
await client.start('my_service');

// Stop a process
await client.stop('my_service');

// Restart a process
await client.restart('my_service');
```

#### Enable and Disable

Disabled processes cannot be started (manually or automatically):

```typescript
// Disable a process (prevents starting)
await client.disable('my_service');

// Enable a process
await client.enable('my_service');
```

#### Autostart Configuration

```typescript
// Enable autostart (starts when ProcessMonitor initializes)
await client.setAutostart('my_service', true);

// Disable autostart
await client.setAutostart('my_service', false);
```

### Status Monitoring

#### Get Single Process Status

```typescript
const status = await client.getStatus('my_service');

console.log('ID:', status.id);
console.log('Name:', status.name);
console.log('State:', status.state); // 'running', 'stopped', 'crashed', etc.
console.log('Enabled:', status.enabled);
console.log('Autostart:', status.autostart);
console.log('PID:', status.pid);
console.log('Last Started:', status.lastStartedAt);
console.log('Last Stopped:', status.lastStoppedAt);
console.log('Restart Attempts:', status.restartAttempts);
```

Process states:
- `stopped` - Process is not running
- `running` - Process is actively running
- `starting` - Process is being started
- `stopping` - Process is being stopped
- `crashed` - Process exited unexpectedly
- `disabled` - Process is disabled and cannot start

#### Get All Processes Status

```typescript
const statuses = await client.getAllStatus();

for (const [processId, status] of statuses) {
  console.log(`${processId}: ${status.state} (PID: ${status.pid ?? 'N/A'})`);
}
```

#### Get Monitor Status

```typescript
const monitorStatus = await client.getMonitorStatus();

console.log('Instance ID:', monitorStatus.instanceId);
console.log('Monitor PID:', monitorStatus.pid);
console.log('Started At:', monitorStatus.startedAt);
console.log('Uptime:', monitorStatus.uptime, 'seconds');
console.log('State:', monitorStatus.state);
console.log('Standalone Mode:', monitorStatus.standaloneMode);
console.log('Partner Instance:', monitorStatus.partnerInstanceId);
console.log('Partner Status:', monitorStatus.partnerStatus);
console.log('Managed Processes:', monitorStatus.managedProcessCount);
console.log('Running Processes:', monitorStatus.runningProcessCount);
```

### Configuration Management

#### Remote Access

```typescript
// Enable/disable remote HTTP access
await client.setRemoteAccess(true);

// Get current configuration
const config = await client.getRemoteAccessConfig();
console.log('Allow remote register:', config.allowRemoteRegister);
console.log('Allow remote start:', config.allowRemoteStart);

// Set specific permissions
await client.setRemoteAccessPermissions({
  allowRemoteRegister: true,
  allowRemoteDeregister: false,
  allowRemoteStart: true,
  allowRemoteStop: true,
});
```

#### Trusted Hosts

```typescript
// Set trusted hosts (IP addresses that can make requests)
await client.setTrustedHosts(['192.168.1.100', '192.168.1.101']);

// Get current trusted hosts
const hosts = await client.getTrustedHosts();
```

#### Executable Filtering

```typescript
// Whitelist: only these executables can be registered
await client.setExecutableWhitelist([
  '/usr/local/bin/*',
  '/opt/my_app/*',
]);

// Blacklist: these executables are blocked
await client.setExecutableBlacklist([
  '/bin/rm',
  '/bin/dd',
]);
```

#### Standalone Mode and Partner Discovery

```typescript
// Enable standalone mode (no partner monitoring)
await client.setStandaloneMode(true);

// Check current mode
const isStandalone = await client.isStandaloneMode();

// Configure partner discovery
await client.setPartnerDiscoveryConfig({
  enabled: true,
  scanIntervalMs: 10000,
  subnets: ['192.168.1', '10.0.0'],
});
```

#### Restart Monitor

```typescript
// Restart the ProcessMonitor itself
await client.restartMonitor();
```

---

## Retry Handling

Both clients include automatic retry with exponential backoff. This is critical for handling temporary network issues and allowing time for crashed services to be restarted by the Process Monitor.

### Default Retry Configuration

- **Delays**: 2, 4, 8, 16, 32 seconds (total: 62 seconds)
- **Retry conditions**: Connection errors, timeouts, 503 Service Unavailable

### Custom Retry Configuration

```typescript
const client = new LedgerClient({
  baseUrl: 'http://localhost:19880',
  enableRetry: true,
  retryConfig: {
    // Custom delays
    retryDelaysMs: [1000, 2000, 5000, 10000],
    
    // Callback on each retry
    onRetry: (attempt, error, delayMs) => {
      console.log(`Attempt ${attempt} failed: ${error.message}`);
      console.log(`Retrying in ${delayMs}ms...`);
    },
  },
});
```

### Disabling Retry

```typescript
const client = new LedgerClient({
  baseUrl: 'http://localhost:19880',
  enableRetry: false,
});
```

---

## Error Handling

### Common Exceptions

```typescript
import {
  LedgerClient,
  ProcessMonitorClient,
  RetryExhaustedException,
  DiscoveryFailedException,
  OperationNotFoundException,
  ProcessNotFoundException,
  PermissionDeniedException,
  HttpException,
} from 'tom_distributed_typescript';
```

### Example Error Handling

```typescript
try {
  const operation = await ledger.createOperation();
  await ledger.completeOperation(operation.operationId);
} catch (error) {
  if (error instanceof RetryExhaustedException) {
    console.error('Server unreachable after all retries');
  } else if (error instanceof OperationNotFoundException) {
    console.error('Operation not found:', error.operationId);
  } else if (error instanceof HttpException) {
    console.error(`HTTP error ${error.status}: ${error.body}`);
  } else {
    throw error;
  }
}
```

```typescript
try {
  await monitor.start('my_service');
} catch (error) {
  if (error instanceof ProcessNotFoundException) {
    console.error('Process not found:', error.processId);
  } else if (error instanceof PermissionDeniedException) {
    console.error('Permission denied:', error.message);
  } else if (error instanceof RetryExhaustedException) {
    console.error('Monitor unreachable after all retries');
  } else {
    throw error;
  }
}
```

---

## Platform Compatibility

The TypeScript clients are designed to work across multiple platforms:

| Platform | Support | Notes |
|----------|---------|-------|
| Node.js 18+ | ✅ Full | Native fetch API |
| Deno | ✅ Full | Native fetch API |
| VS Code Extensions | ✅ Full | Node.js runtime |
| Modern Browsers | ✅ Full | Native fetch API |
| Older Node.js (<18) | ⚠️ Polyfill | Requires `cross-fetch` |

### Browser Limitations

- **Subnet scanning**: Not available (no access to local network interfaces)
- **Auto-discovery**: Limited to localhost only
- **CORS**: Server must have appropriate CORS headers

### Using in Different Environments

```typescript
// Node.js / Deno / VS Code Extension - full functionality
const ledger = await LedgerClient.discover();

// Browser - must specify URL explicitly (or use localhost)
const ledger = new LedgerClient({
  baseUrl: 'http://localhost:19880',
});
```

---

## Default Ports

| Service | Default Port |
|---------|-------------|
| Ledger Server | 19880 |
| Process Monitor | 19881 |

---

## Best Practices

1. **Always dispose clients** when done to clean up resources:
   ```typescript
   const client = new LedgerClient();
   try {
     // Use client...
   } finally {
     client.dispose();
   }
   ```

2. **Use auto-discovery** for flexible deployment configurations.

3. **Send regular heartbeats** during long operations to prevent stale detection.

4. **Use call tracking** for critical operations to enable crash detection.

5. **Handle retry exhaustion** gracefully - the service may genuinely be down.

6. **Set appropriate timeouts** for your use case:
   ```typescript
   const client = new LedgerClient({
     timeout: 60000, // 60 seconds for long operations
   });
   ```

---

## See Also

- [Dart Ledger Client Documentation](../tom_dist_ledger/doc/README.md)
- [Dart Process Monitor Client Documentation](../tom_process_monitor/doc/README.md)
- [Integration Tests](./test/integration.test.ts) - Working examples
