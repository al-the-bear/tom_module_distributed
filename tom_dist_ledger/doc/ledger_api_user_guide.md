# Distributed Ledger API User Guide

A practical guide to using the `tom_dist_ledger` package for coordinating distributed operations.

---

## Table of Contents

1. [Introduction](#introduction)
2. [Installation](#installation)
3. [Quick Start](#quick-start)
4. [Local vs Remote Access](#local-vs-remote-access)
5. [Creating and Joining Operations](#creating-and-joining-operations)
6. [Working with Calls](#working-with-calls)
7. [Spawned Calls and Workers](#spawned-calls-and-workers)
8. [Heartbeats and Crash Detection](#heartbeats-and-crash-detection)
9. [Error Handling](#error-handling)
10. [Best Practices](#best-practices)

---

## Introduction

The Distributed Ledger provides coordination for long-running operations that span multiple processes. It handles:

- **Operation tracking** - Track which processes are participating in an operation
- **Call lifecycle** - Start, track, and complete individual work units
- **Crash detection** - Automatic detection of crashed participants via heartbeats
- **Cleanup coordination** - Orderly cleanup when crashes are detected
- **Signal-based cleanup** - Automatic cleanup on SIGINT/SIGTERM (Ctrl+C, kill)
- **Operation logging** - Centralized logging for debugging

### Use Cases

- Multi-process build systems
- Distributed task orchestration
- Worker process coordination
- Background job tracking

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  tom_dist_ledger:
    path: path/to/tom_dist_ledger
```

Import the package:

```dart
import 'package:tom_dist_ledger/tom_dist_ledger.dart';
```

---

## Quick Start

### Using Ledger.connect() (Recommended)

The easiest way to work with ledgers is through the unified `Ledger.connect()` factory:

```dart
// Connect to a local ledger
final ledger = await Ledger.connect(
  basePath: '/tmp/ledger',
  participantId: 'orchestrator',
);

// Or connect to a remote server (with auto-discovery)
final ledger = await Ledger.connect(
  participantId: 'orchestrator',
);

// Or connect to a specific server
final ledger = await Ledger.connect(
  serverUrl: 'http://localhost:19880',
  participantId: 'orchestrator',
);

if (ledger != null) {
  final operation = await ledger.createOperation();
  // ... do work ...
  await ledger.dispose();
}
```

### Local Ledger (Same Machine)

For file-based coordination on the same machine:

```dart
// Create a local ledger using the unified factory
final ledger = await Ledger.connect(
  basePath: '/tmp/ledger',
  participantId: 'orchestrator',
);

if (ledger == null) {
  print('Failed to create ledger');
  return;
}

// Create an operation (you're the initiator)
final operation = await ledger.createOperation(
  description: 'Build project',
);

// Do work with tracked calls
final call = await operation.startCall<void>();
await doWork();
await call.end();

// Complete the operation
await operation.complete();
ledger.dispose();
```

### Remote Ledger (Network Access)

```dart
// Connect to a ledger server (with auto-discovery)
final client = await Ledger.connect(
  participantId: 'remote_worker',
);

// Or connect to a known server
final clientDirect = await Ledger.connect(
  serverUrl: 'http://localhost:19880',
  participantId: 'remote_worker',
);

if (client == null) {
  print('Could not find server');
  return;
}

// Join an existing operation
final operation = await client.joinOperation(
  operationId: 'known-operation-id',
);

// Do work with typed calls - SAME API as local!
final call = await operation.startCall<String>(
  callback: CallCallback<String>(
    onCompletion: (result) async => print('Got: $result'),
  ),
);
final result = await doWork();
await call.end(result);

// Leave the operation
await operation.leave();
client.dispose();
```

---

## Local vs Remote Access

The ledger supports two access patterns with an **identical API**:

| Pattern | Class | Use Case |
|---------|-------|----------|
| **Local** | `LocalLedger` | Same machine, file-based coordination |
| **Remote** | `RemoteLedgerClient` | Network access via HTTP server |

### Unified API via Ledger.connect()

The recommended way to create a ledger is through the unified `Ledger.connect()` factory:

```dart
// Local access - provide basePath
final ledger = await Ledger.connect(
  basePath: '/tmp/ledger',
  participantId: 'orchestrator',
);

// Remote access - omit basePath, optionally provide serverUrl
final ledger = await Ledger.connect(
  participantId: 'worker',
  serverUrl: 'http://localhost:19880', // Optional, auto-discovers if omitted
);
```

Both local and remote operations provide the **same typed API**:

| Feature | Local (`Operation`) | Remote (`RemoteOperation`) |
|---------|---------------------|---------------------------|
| `startCall<T>()` | Returns `Call<T>` | Returns `Call<T>` |
| `spawnCall<T>()` | Returns `SpawnedCall<T>` | Returns `SpawnedCall<T>` |
| `CallCallback<T>` | Full support | Full support (client-side) |
| Session tracking | Full support | Full support |
| `sync()` | Full support | Full support |

**Key design**: The server only handles file operations. All callbacks, work execution, and type safety happen client-side. This means switching between local and remote only requires changing initialization.

### When to Use Local

- All participants run on the same machine
- You want file-based coordination without network overhead
- You're building a CLI tool or local automation

### When to Use Remote

- Participants run on different machines
- You need network-accessible coordination
- You're building distributed services

### Ledger Abstract Interface

Both `LocalLedger` and `RemoteLedgerClient` extend the abstract `Ledger` class, so you can write code that works with either:

```dart
Future<void> doCoordinatedWork(Ledger ledger, String operationId) async {
  // Works with both LocalLedger and RemoteLedgerClient
  final operation = await ledger.joinOperation(
    operationId: operationId,
  );
  
  // Same typed API for both local and remote
  final call = await (operation as dynamic).startCall<String>(
    callback: CallCallback<String>(
      onCompletion: (result) async => print('Result: $result'),
    ),
  );
  final result = await performTask();
  await call.end(result);
  
  await operation.leave();
}
```
```

### Remote-Specific Features

When using `RemoteLedgerClient`, additional session tracking methods are available:

```dart
final operation = await client.joinOperation(operationId: opId);

// Spawn multiple calls
final call1 = operation.spawnCall<int>(work: () async => 1);
final call2 = operation.spawnCall<int>(work: () async => 2);

// Check session state
print('Has pending: ${operation.hasPendingCalls()}');
print('Pending IDs: ${operation.getPendingCalls()}');
print('Spawned calls: ${operation.getPendingSpawnedCalls().length}');

// Wait for all
final result = await operation.sync([call1, call2]);
```

---

## Creating and Joining Operations

### The Initiator Pattern

One participant creates the operation and coordinates completion:

```dart
final ledger = await Ledger.connect(
  basePath: '/tmp/ledger',
  participantId: 'orchestrator',
);

if (ledger == null) return;

// Create operation - heartbeat auto-starts
final operation = await ledger.createOperation(
  description: 'Coordinate workers',
  callback: OperationCallback(
    onHeartbeatError: (op, error) {
      print('Heartbeat error: ${error.message}');
    },
  ),
);

// The operationId can be shared with workers
print('Operation ID: ${operation.operationId}');

// Spawn workers, wait for completion...
await doOrchestratorWork(operation);

// Complete the operation - archives files, stops heartbeat
await operation.complete();
```

### The Participant Pattern

Other participants join existing operations:

```dart
final ledger = await Ledger.connect(
  basePath: '/tmp/ledger',
  participantId: 'worker-1',
);

if (ledger == null) return;

// Join existing operation - heartbeat auto-starts on first join
final operation = await ledger.joinOperation(
  operationId: operationId,
  callback: OperationCallback(
    onHeartbeatError: (op, error) {
      if (error.type == HeartbeatErrorType.abortFlagSet) {
        print('Operation was aborted!');
      }
    },
  ),
);

// Do work...
await doWorkerTasks(operation);

// Leave the operation - heartbeat stops when last session leaves
operation.leave();
```

### Session Tracking

Multiple joins to the same operation create separate sessions:

```dart
// First join
final session1 = await ledger.joinOperation(operationId: opId);

// Second join - different session
final session2 = await ledger.joinOperation(operationId: opId);

// Each session tracks its own calls
final call1 = await session1.startCall();
final call2 = await session2.startCall();

// Leave each session independently
session1.leave();  // First session done
session2.leave();  // Heartbeat stops when both leave
```

---

## Working with Calls

### The Call<T> Pattern

For synchronous work that you control directly:

```dart
final call = await operation.startCall<int>(
  description: 'Process document',
  callback: CallCallback(
    onCleanup: () async => await releaseResources(),
  ),
);

try {
  final result = await processDocument();
  await call.end(result);  // Success with result
} catch (e, st) {
  await call.fail(e, st);  // Failure with error
  rethrow;
}
```

### Call Properties

```dart
final call = await operation.startCall<String>();

print(call.callId);       // Unique identifier
print(call.description);  // Optional description
print(call.startedAt);    // Start timestamp
print(call.isCompleted);  // Whether ended/failed
```

### Using CallCallback

```dart
final call = await operation.startCall<Result>(
  callback: CallCallback(
    // Called when cleanup is needed (crash detected)
    onCleanup: () async {
      await releaseResources();
    },
    
    // Called when call completes successfully
    onCompletion: (result) async {
      await notifySuccess(result);
    },
    
    // Called if the call crashes - return fallback value
    onCallCrashed: () async {
      return Result.empty();  // Fallback
    },
    
    // Called if operation fails during this call
    onOperationFailed: (info) async {
      await handleFailure(info);
    },
  ),
);
```

---

## Spawned Calls and Workers

### The SpawnedCall Pattern

For asynchronous work that runs in the background:

```dart
// Spawn a call - returns immediately
final call = operation.spawnCall<int>(
  work: () async {
    await Future.delayed(Duration(seconds: 5));
    return 42;
  },
  description: 'Background computation',
);

// callId is available immediately
print('Started: ${call.callId}');

// Wait for completion later
await call.future;
print('Result: ${call.result}');
```

### Sync Multiple Calls

Wait for multiple spawned calls:

```dart
final call1 = operation.spawnCall<int>(work: () async => 1);
final call2 = operation.spawnCall<int>(work: () async => 2);
final call3 = operation.spawnCall<int>(work: () async => 3);

final result = await operation.sync(
  [call1, call2, call3],
  onOperationFailed: (info) async {
    print('Operation failed: ${info.reason}');
  },
);

if (result.allSucceeded) {
  print('All done: ${call1.result}, ${call2.result}, ${call3.result}');
} else {
  print('Failed: ${result.failedCalls.length}');
}
```

### Process Workers

Spawn external processes as tracked calls:

```dart
// Worker that writes result to file
final worker = operation.execFileResultWorker<Map>(
  executable: 'dart',
  arguments: ['run', 'worker.dart', '--output', resultPath],
  resultFilePath: resultPath,
  onExit: (code) => print('Worker exited: $code'),
);

await worker.future;
print('Result: ${worker.result}');
```

```dart
// Worker that outputs to stdout
final worker = operation.execStdioWorker<WorkerResult>(
  executable: 'dart',
  arguments: ['run', 'processor.dart'],
  deserializer: (stdout) => WorkerResult.fromJson(jsonDecode(stdout)),
);

final result = await worker.await_();
```

### Contained Crashes

For calls that shouldn't fail the entire operation:

```dart
final optionalCall = operation.spawnCall<int>(
  work: () async {
    // This might crash
    return await riskyOperation();
  },
  failOnCrash: false,  // Don't fail operation if this crashes
  callback: CallCallback(
    onCallCrashed: () async => -1,  // Fallback value
  ),
);

await optionalCall.future;
if (optionalCall.isSuccess) {
  print('Got: ${optionalCall.result}');
} else {
  print('Using fallback: ${optionalCall.result}');
}
```

---

## Heartbeats and Crash Detection

### How Heartbeats Work

Each participant periodically updates a timestamp in the ledger. If a participant's heartbeat becomes stale (exceeds the threshold), it's considered crashed.

```dart
final ledger = await Ledger.connect(
  basePath: '/tmp/ledger',
  participantId: 'worker',
  heartbeatInterval: Duration(seconds: 5),  // How often to update
  staleThreshold: Duration(seconds: 15),    // When to consider crashed
);
```

### Monitoring Heartbeats

```dart
final operation = await ledger.createOperation(
  callback: OperationCallback(
    onHeartbeatSuccess: (op, result) {
      print('Heartbeat OK - ${result.participants.length} participants');
      if (result.staleParticipants.isNotEmpty) {
        print('Warning: stale participants: ${result.staleParticipants}');
      }
    },
    onHeartbeatError: (op, error) {
      switch (error.type) {
        case HeartbeatErrorType.abortFlagSet:
          print('Operation aborted!');
          break;
        case HeartbeatErrorType.heartbeatStale:
          print('Stale heartbeat: ${error.message}');
          break;
        default:
          print('Heartbeat error: ${error.message}');
      }
    },
  ),
);
```

### Abort Detection

Check for abort in long-running work:

```dart
Future<void> processItems(Operation operation, List<Item> items) async {
  for (final item in items) {
    // Check if we should abort
    if (await operation.checkAbort()) {
      print('Abort detected, stopping');
      return;
    }
    
    await processItem(item);
  }
}
```

### Triggering Abort

Signal other participants to stop:

```dart
// Set the abort flag in the ledger
await operation.setAbortFlag(true);

// Or trigger local abort immediately
operation.triggerAbort();
```

---

## Error Handling

### Operation Failure

Handle operation failures gracefully:

```dart
try {
  final result = await operation.waitForCompletion<int>(
    () async => await doWork(),
    onOperationFailed: (info) async {
      print('Operation failed: ${info.reason}');
      await cleanup();
    },
    onError: (error, stackTrace) async {
      print('Work error: $error');
      return -1;  // Fallback value
    },
  );
  print('Result: $result');
} on OperationFailedException catch (e) {
  print('Could not complete: ${e.info.reason}');
}
```

### Remote Errors

Handle remote ledger errors:

```dart
try {
  final operation = await client.joinOperation(operationId: opId);
  // ...
} on RemoteLedgerException catch (e) {
  if (e.statusCode == 404) {
    print('Operation not found');
  } else {
    print('Server error: ${e.message}');
  }
}
```

### Cleanup on Crash

Register cleanup handlers:

```dart
final call = await operation.startCall<void>(
  callback: CallCallback(
    onCleanup: () async {
      // Called if crash is detected during this call
      await file.delete();
      await connection.close();
    },
  ),
);
```

---

## Best Practices

### 1. Always Use Try-Finally for Calls

```dart
final call = await operation.startCall<void>();
try {
  await doWork();
  await call.end();
} catch (e, st) {
  await call.fail(e, st);
  rethrow;
}
```

### 2. Register Cleanup for Resources

Temporary resources are automatically tracked locally for signal-based cleanup (SIGINT/SIGTERM). Even if your process is killed, registered temp resources will be cleaned up:

```dart
final tempFile = File('temp.txt');
await operation.registerTempResource(path: tempFile.path);

try {
  await tempFile.writeAsString(data);
  // ... use file ...
  // If process is killed here, temp file will be cleaned up automatically
} finally {
  await operation.unregisterTempResource(path: tempFile.path);
  await tempFile.delete();
}
```

### 3. Signal-Based Cleanup

Both local and remote operations automatically register with `CleanupHandler` for graceful shutdown. When your process receives SIGINT (Ctrl+C) or SIGTERM (kill), all registered temporary resources are cleaned up.

This happens automatically - you don't need to do anything special. The cleanup:
- Runs all registered cleanup callbacks
- Deletes all registered temporary files and directories  
- Silently ignores missing files (may have been cleaned by other participants)

For custom cleanup needs, you can register your own callbacks:

```dart
final id = CleanupHandler.instance.register(() async {
  await releaseExternalResources();
});

// Later, when no longer needed:
CleanupHandler.instance.unregister(id);
```

### 3. Use Descriptions for Debugging

```dart
final call = await operation.startCall<void>(
  description: 'Process document: ${doc.name}',
);

final worker = operation.execFileResultWorker<Map>(
  description: 'Worker for ${item.id}',
  // ...
);
```

### 4. Handle Heartbeat Errors

```dart
callback: OperationCallback(
  onHeartbeatError: (op, error) {
    if (error.type == HeartbeatErrorType.abortFlagSet) {
      // Graceful shutdown
      cancelAllWork();
    }
  },
),
```

### 5. Use Appropriate failOnCrash

```dart
// Critical work - crash should fail operation
final critical = operation.spawnCall<void>(
  work: () async => await mustSucceed(),
  failOnCrash: true,  // Default
);

// Optional work - crash should be contained
final optional = operation.spawnCall<void>(
  work: () async => await niceToHave(),
  failOnCrash: false,
);
```

### 6. Dispose Ledgers and Clients

```dart
final ledger = await Ledger.connect(
  basePath: '/tmp/ledger',
  participantId: 'example',
);
if (ledger == null) return;

try {
  await doWork(ledger);
} finally {
  ledger.dispose();
}
```

---

*Generated from tom_dist_ledger v2.0 implementation*
