# Distributed Ledger API Reference

Comprehensive API reference for the `tom_dist_ledger` package.

---

## Table of Contents

1. [Abstract Base Classes](#abstract-base-classes)
   - [LedgerBase](#ledgerbase)
   - [OperationBase](#operationbase)
2. [Local Ledger Classes](#local-ledger-classes)
   - [Ledger Class](#ledger-class)
   - [Operation Class](#operation-class)
3. [Remote Ledger Classes](#remote-ledger-classes)
   - [LedgerServer](#ledgerserver)
   - [RemoteLedgerClient](#remoteledgerclient)
   - [RemoteOperation](#remoteoperation)
   - [RemoteLedgerException](#remoteledgerexception)
4. [Call Classes](#call-classes)
   - [Call Class](#call-class)
   - [SpawnedCall Class](#spawnedcall-class)
5. [SyncResult Class](#syncresult-class)
6. [OperationHelper Class](#operationhelper-class)
7. [Data Classes](#data-classes)
8. [Enums](#enums)
9. [Type Definitions](#type-definitions)
10. [Usage Examples](#usage-examples)

---

## Abstract Base Classes

### LedgerBase

Abstract base class for ledger implementations. Both `Ledger` (local) and `RemoteLedgerClient` (remote) extend this class.

```dart
abstract class LedgerBase
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `participantId` | `String` | Unique identifier for this ledger instance |
| `participantPid` | `int` | Process ID for this participant |
| `maxBackups` | `int` | Maximum backup operations to retain |
| `heartbeatInterval` | `Duration` | Interval between heartbeats |
| `staleThreshold` | `Duration` | Threshold for detecting stale participants |

#### Methods

| Method | Description |
|--------|-------------|
| `dispose()` | Dispose of the ledger and stop all heartbeats |

### OperationBase

Abstract base class for operation handles. Both `Operation` (local) and `RemoteOperation` (remote) implement this interface.

```dart
abstract class OperationBase
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `operationId` | `String` | The operation ID |
| `participantId` | `String` | The participant ID |
| `isInitiator` | `bool` | Whether this is the initiator |
| `sessionId` | `int` | The session ID for this handle |
| `startTime` | `DateTime` | When this operation was started |
| `isAborted` | `bool` | Whether this participant is aborted |
| `onAbort` | `Future<void>` | Future that completes when abort is signaled |

#### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `leave({bool cancelPendingCalls})` | `FutureOr<void>` | Leave this session |
| `log(String message, {LogLevel level})` | `Future<void>` | Write to operation log |
| `complete()` | `Future<void>` | Complete operation (initiator only) |
| `setAbortFlag(bool value)` | `Future<void>` | Set abort flag |
| `checkAbort()` | `Future<bool>` | Check if operation is aborted |
| `triggerAbort()` | `void` | Trigger local abort |

---

## Local Ledger Classes

### Ledger Class

Main entry point for the distributed ledger system.

```dart
class Ledger
```

### Constructor

```dart
Ledger({
  required String basePath,
  required String participantId,
  int? participantPid,
  LedgerCallback? callback,
  int maxBackups = 20,
  Duration heartbeatInterval = const Duration(seconds: 5),
  Duration staleThreshold = const Duration(seconds: 15),
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `basePath` | `String` | required | Directory path for ledger files |
| `participantId` | `String` | required | Participant ID for operations |
| `participantPid` | `int?` | current PID | Process ID for this participant |
| `callback` | `LedgerCallback?` | `null` | Grouped callbacks (backup, log, heartbeat) |
| `maxBackups` | `int` | `20` | Maximum backup operations to retain |
| `heartbeatInterval` | `Duration` | 5 seconds | Interval between heartbeats |
| `staleThreshold` | `Duration` | 15 seconds | Threshold for detecting stale participants |

**Example:**
```dart
final ledger = Ledger(
  basePath: '/tmp/ledger',
  participantId: 'cli',
  callback: LedgerCallback(
    onBackupCreated: (path) => print('Backup: $path'),
    onLogLine: (line) => print('Log: $line'),
  ),
);
```

### Methods

#### createOperation

Create a new operation (initiator).

```dart
Future<Operation> createOperation({
  String? description,
  OperationCallback? callback,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `description` | `String?` | `null` | Optional description |
| `callback` | `OperationCallback?` | `null` | Heartbeat success/error callbacks |

**Returns:** `Operation` - A session-specific operation for interacting with the ledger, with heartbeat auto-started.

**Note:** Heartbeat is automatically started when the operation is created.
Call `Operation.complete()` to stop heartbeat and archive the operation.

#### joinOperation

Join an existing operation (participant).

```dart
Future<Operation> joinOperation({
  required String operationId,
  OperationCallback? callback,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `operationId` | `String` | required | The operation to join |
| `callback` | `OperationCallback?` | `null` | Heartbeat success/error callbacks |

**Returns:** `Operation` - A session-specific operation for the joined operation.

**Note:** Each call to `joinOperation` returns a new `Operation` with its own
session ID for tracking calls. This allows multiple joins to the same operation
to track their calls independently. Heartbeat is automatically started on first
join and stopped when the last session calls `leave()`.

#### dispose

Dispose the ledger and stop all heartbeats.

```dart
Future<void> dispose()
```

---

### Operation Class

Represents a running operation for a specific join session.

Each call to `Ledger.createOperation()` or `Ledger.joinOperation()` returns
a new `Operation` with its own session. This allows tracking which calls
belong to which join, and ensures `leave()` only checks calls created
through this operation.

```dart
class Operation
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `sessionId` | `int` | Unique session identifier for this operation |
| `operationId` | `String` | Unique operation identifier |
| `participantId` | `String` | ID of this participant |
| `pid` | `int` | Process ID of this participant |
| `isInitiator` | `bool` | Whether this participant started the operation |
| `startTime` | `DateTime` | When operation was started/joined |
| `elapsedDuration` | `Duration` | Time since operation start |
| `elapsedFormatted` | `String` | Elapsed time as "SSS.mmm" |
| `startTimeIso` | `String` | Start time as ISO 8601 string |
| `startTimeMs` | `int` | Start time as milliseconds since epoch |
| `cachedData` | `LedgerData?` | Cached operation data |
| `isAborted` | `bool` | Whether this participant is aborted |
| `onAbort` | `Future<void>` | Completes when abort is signaled |
| `onFailure` | `Future<OperationFailedInfo>` | Completes when operation fails |
| `stalenessThresholdMs` | `int` | Staleness threshold in milliseconds |
| `pendingCallCount` | `int` | Number of pending calls for this session |

### Session-Specific Call Tracking

#### hasPendingCalls

Check if this session has any pending calls.

Returns true if there are any calls (regular or spawned) that were
started through this operation and have not yet completed.

```dart
bool hasPendingCalls()
```

**Returns:** `true` if there are pending calls, `false` otherwise.

#### getPendingSpawnedCalls

Get a list of pending spawned calls for this session.

Returns the `SpawnedCall` objects that were started via this operation and
have not yet completed.

```dart
List<SpawnedCall> getPendingSpawnedCalls()
```

**Returns:** List of `SpawnedCall` objects that are still pending for this session.

**Example:**
```dart
final operation = await ledger.joinOperation(operationId: opId);
final call1 = operation.spawnCall(work: () async => doWork1());
final call2 = operation.spawnCall(work: () async => doWork2());

print(operation.hasPendingCalls()); // true
print(operation.getPendingSpawnedCalls()); // [call1, call2]

await call1.future;
print(operation.getPendingSpawnedCalls()); // [call2]
```

#### getPendingCalls

Get a list of pending regular calls for this session.

Returns the `Call` objects that were started via `startCall()` through this
operation and have not yet completed.

```dart
List<Call<dynamic>> getPendingCalls()
```

**Returns:** List of `Call` objects that are still pending for this session.

**Note:** For spawned calls, use `getPendingSpawnedCalls()` instead.

#### leave

Leave the operation for this session.

Decrements the join count. When the count reaches 0, heartbeat is stopped
and the operation is unregistered from this participant's ledger.

```dart
void leave({bool cancelPendingCalls = false})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `cancelPendingCalls` | `bool` | `false` | If true, automatically cancel all pending calls for this session before leaving |

**Throws:** `StateError` if there are pending calls and `cancelPendingCalls` is false.

**Example:**
```dart
final operation = await ledger.joinOperation(operationId: opId);
final call = await operation.startCall<void>();

// Option 1: End calls manually before leaving
await call.end(null);
operation.leave();

// Option 2: Auto-cancel pending calls
operation.leave(cancelPendingCalls: true);
```

### Call Management Methods

| Method | Description |
|--------|-------------|
| `startCall<T>()` | Start a call tracked to this session |
| `spawnCall<T>()` | Spawn an async call tracked to this session |
| `sync()` | Wait for spawned calls to complete |
| `awaitCall()` | Wait for a single spawned call |
| `waitForCompletion()` | Execute work while monitoring operation state |
| `complete()` | Complete the operation (initiator only) |
| `log()` | Write to operation log |
| `logMessage()` | Log formatted message with timestamp |
| `checkAbort()` | Check if operation is aborted |
| `triggerAbort()` | Trigger local abort |
| `setAbortFlag()` | Set abort flag in ledger |
| `startHeartbeat()` | Start/reconfigure heartbeat |
| `stopHeartbeat()` | Stop heartbeat |
| `heartbeat()` | Perform single heartbeat |

#### startCall

Start a call and return a `Call<T>` object for lifecycle management.

```dart
Future<Call<T>> startCall<T>({
  CallCallback<T>? callback,
  String? description,
  bool failOnCrash = true,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `callback` | `CallCallback<T>?` | `null` | Callbacks for cleanup/completion |
| `description` | `String?` | `null` | Optional description |
| `failOnCrash` | `bool` | `true` | Whether crash fails entire operation |

**Returns:** `Call<T>` - Object with `end()` and `fail()` methods.

**Example:**

```dart
final call = await operation.startCall<int>(
  callback: CallCallback(onCleanup: () async => releaseResources()),
);

try {
  final result = await performWork();
  await call.end(result);  // End successfully with result
} catch (e, st) {
  await call.fail(e, st);  // Fail with error
}
```

#### spawnCall

Spawn a call that runs asynchronously.

```dart
SpawnedCall<T> spawnCall<T>({
  Future<T> Function()? work,
  Future<T> Function(SpawnedCall<T> call)? workWithCall,
  CallCallback<T>? callback,
  String? description,
  bool failOnCrash = true,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `work` | `Future<T> Function()?` | `null` | Async work function |
| `workWithCall` | `Future<T> Function(SpawnedCall<T>)?` | `null` | Work with access to call |
| `callback` | `CallCallback<T>?` | `null` | Optional callbacks |
| `description` | `String?` | `null` | Optional description |
| `failOnCrash` | `bool` | `true` | Whether crash fails operation |

**Note:** Either `work` or `workWithCall` must be provided. Use `workWithCall` when you need to attach a process to the call for cancel/kill support.

**Returns:** `SpawnedCall<T>` - Returns immediately. Await `.future` for result.

**Example:**

```dart
final call = operation.spawnCall<int>(
  work: () async => await computeExpensiveValue(),
  callback: CallCallback(
    onCompletion: (result) async => print('Got: $result'),
    onCallCrashed: () async => 0, // Fallback value
  ),
);

// Access callId immediately
print('Call started: ${call.callId}');

// Wait for result later
await call.future;
print('Result: ${call.result}');
```

#### sync

Wait for spawned calls to complete.

```dart
Future<SyncResult> sync(
  List<SpawnedCall> calls, {
  Future<void> Function(OperationFailedInfo info)? onOperationFailed,
  Future<void> Function()? onCompletion,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `calls` | `List<SpawnedCall>` | required | Calls to wait for |
| `onOperationFailed` | `Function(OperationFailedInfo)?` | `null` | Called if operation fails |
| `onCompletion` | `Function()?` | `null` | Called when all complete |

**Returns:** `SyncResult` - Status of all calls.

#### awaitCall

Wait for a single spawned call to complete.

```dart
Future<SyncResult> awaitCall<T>(
  SpawnedCall<T> call, {
  Future<void> Function(OperationFailedInfo info)? onOperationFailed,
  Future<void> Function()? onCompletion,
})
```

**Returns:** `SyncResult` - Status of the call.

#### waitForCompletion

Execute work while monitoring operation state.

```dart
Future<T> waitForCompletion<T>(
  Future<T> Function() work, {
  Future<void> Function(OperationFailedInfo info)? onOperationFailed,
  Future<T> Function(Object error, StackTrace stackTrace)? onError,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `work` | `Future<T> Function()` | required | Async work function |
| `onOperationFailed` | `Function(OperationFailedInfo)?` | `null` | Called if operation fails |
| `onError` | `Function(Object, StackTrace)?` | `null` | Error handler, can return fallback |

**Returns:** Result of work function. Throws `OperationFailedException` if operation fails.

**Example:**

```dart
final result = await operation.waitForCompletion<int>(
  () async => await computeValue(),
  onOperationFailed: (info) async => print('Operation failed!'),
  onError: (error, stackTrace) async {
    print('Error: $error');
    return -1; // Fallback value
  },
);
```

### Exec Helper Methods

#### execFileResultWorker

Spawn a process that writes result to a file.

```dart
SpawnedCall<T> execFileResultWorker<T>({
  required String executable,
  required List<String> arguments,
  required String resultFilePath,
  String? workingDirectory,
  String? description,
  T Function(String content)? deserializer,
  bool deleteResultFile = true,
  Duration pollInterval = const Duration(milliseconds: 100),
  Duration? timeout,
  void Function(String line)? onStdout,
  void Function(String line)? onStderr,
  void Function(int exitCode)? onExit,
  bool failOnCrash = true,
  CallCallback<T>? callback,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `executable` | `String` | required | Executable path |
| `arguments` | `List<String>` | required | Command arguments |
| `resultFilePath` | `String` | required | Path for result file |
| `workingDirectory` | `String?` | current dir | Working directory |
| `description` | `String?` | "File result worker" | Description |
| `deserializer` | `T Function(String)?` | auto | Parse file content |
| `deleteResultFile` | `bool` | `true` | Delete file after read |
| `pollInterval` | `Duration` | 100ms | File poll interval |
| `timeout` | `Duration?` | `null` | Operation timeout |
| `onStdout` | `void Function(String)?` | `null` | Stdout callback |
| `onStderr` | `void Function(String)?` | `null` | Stderr callback |
| `onExit` | `void Function(int)?` | `null` | Exit code callback |
| `failOnCrash` | `bool` | `true` | Fail operation on crash |
| `callback` | `CallCallback<T>?` | `null` | Additional callbacks |

**Returns:** `SpawnedCall<T>` - Immediately returns. Await `.future` for result.

**Example:**

```dart
final worker = operation.execFileResultWorker<Map>(
  executable: 'dart',
  arguments: ['run', 'worker.dart', '--output', resultPath],
  resultFilePath: resultPath,
  onExit: (exitCode) => print('Worker exited: $exitCode'),
);

print('Started: ${worker.callId}');
await worker.future;
print('Result: ${worker.result}');
```

#### execStdioWorker

Spawn a process that outputs result to stdout.

```dart
SpawnedCall<T> execStdioWorker<T>({
  required String executable,
  required List<String> arguments,
  required T Function(String stdout) deserializer,
  String? workingDirectory,
  String? description,
  void Function(int exitCode)? onExit,
  bool failOnCrash = true,
  CallCallback<T>? callback,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `executable` | `String` | required | Executable path |
| `arguments` | `List<String>` | required | Command arguments |
| `deserializer` | `T Function(String)` | required | Parse stdout |
| `workingDirectory` | `String?` | current dir | Working directory |
| `description` | `String?` | "Stdio worker" | Description |
| `onExit` | `void Function(int)?` | `null` | Exit code callback |
| `failOnCrash` | `bool` | `true` | Fail operation on crash |
| `callback` | `CallCallback<T>?` | `null` | Additional callbacks |

**Returns:** `SpawnedCall<T>` - Immediately returns. Await `.future` for result.

#### execServerRequest

Spawn a typed call for an HTTP request.

```dart
SpawnedCall<T> execServerRequest<T>({
  required Future<T> Function() work,
  String? description,
  Duration? timeout,
  bool failOnCrash = true,
  CallCallback<T>? callback,
})
```

**Returns:** `SpawnedCall<T>` - Immediately returns.

### Logging Methods

#### log

Write an entry to the operation log.

```dart
Future<void> log(String message, {LogLevel level = LogLevel.info})
```

#### debugLog

Write to debug log (internal use only).

```dart
Future<void> debugLog(String message)
```

#### logMessage

Log a formatted message with timestamp and participant.

```dart
Future<void> logMessage({
  required int depth,
  required String message,
})
```

### State Methods

#### complete

Complete the operation (initiator only).

```dart
Future<void> complete()
```

#### getOperationState

Get the current operation state.

```dart
Future<OperationState> getOperationState()
```

#### checkAbort

Check if the operation is aborted.

```dart
Future<bool> checkAbort()
```

#### triggerAbort

Trigger local abort for this participant.

```dart
void triggerAbort()
```

### Heartbeat Methods

#### startHeartbeat

Start or reconfigure heartbeat for this participant.

**Note:** Heartbeat is automatically started when an operation is created
or joined. This method is primarily useful for:
- Restarting heartbeat with different settings
- Adding custom callbacks (onError, onSuccess)

If heartbeat is already running, it will be stopped and restarted with the new settings.

```dart
void startHeartbeat({
  Duration interval = const Duration(milliseconds: 4500),
  int jitterMs = 500,
  HeartbeatErrorCallback? onError,
  HeartbeatSuccessCallback? onSuccess,
})
```

#### stopHeartbeat

Stop heartbeat for this participant.

```dart
void stopHeartbeat()
```

#### heartbeat

Perform a single heartbeat.

```dart
Future<HeartbeatResult?> heartbeat()
```

### Operation Lifecycle Methods

#### leave

Leave the operation (decrements the join count).

A participant may join the same operation multiple times when handling
multiple calls. Each join increments the join count, and each leave
decrements it. When the join count reaches 0, the heartbeat is automatically
stopped and the operation is unregistered from this participant's ledger.

```dart
void leave({bool cancelPendingCalls = false})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `cancelPendingCalls` | `bool` | `false` | If true, cancel all pending calls for the session before leaving |

**Throws:** `StateError` if there are pending calls and `cancelPendingCalls` is false.

**Example:**
```dart
final operation = await ledger.joinOperation(operationId: opId);
// ... do work ...
operation.leave(cancelPendingCalls: true);
```

#### complete

Complete the operation (for initiator only).

This stops the heartbeat, logs completion, moves files to backup,
and unregisters the operation.

```dart
Future<void> complete()
```

**Note:** Throws `StateError` if called by non-initiator.

### Resource Methods

#### registerTempResource

Register a temporary resource for cleanup.

```dart
Future<void> registerTempResource({required String path})
```

#### unregisterTempResource

Unregister a temporary resource.

```dart
Future<void> unregisterTempResource({required String path})
```

---

## Remote Ledger Classes

### LedgerServer

HTTP server that provides remote access to the distributed ledger.

```dart
class LedgerServer
```

#### Factory Method

##### start

Start the ledger server.

```dart
static Future<LedgerServer> start({
  required String basePath,
  int port = 8765,
  InternetAddress? address,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `basePath` | `String` | required | Directory for ledger files |
| `port` | `int` | `8765` | Port to listen on |
| `address` | `InternetAddress?` | loopback | Address to bind to |

**Returns:** `LedgerServer` - Running server instance.

**Example:**

```dart
final server = await LedgerServer.start(
  basePath: '/tmp/ledger',
  port: 8765,
);
print('Server listening on http://localhost:${server.port}');
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `port` | `int` | Port the server is listening on |
| `basePath` | `String` | Base path for ledger files |

#### Methods

##### stop

Stop the server.

```dart
Future<void> stop()
```

**Example:**

```dart
await server.stop();
```

#### HTTP Endpoints

| Endpoint | Method | Request Body | Description |
|----------|--------|--------------|-------------|
| `/health` | GET | - | Health check |
| `/operation/create` | POST | `{participantId, description?, participantPid?}` | Create operation |
| `/operation/join` | POST | `{operationId, participantId, participantPid?}` | Join operation |
| `/operation/leave` | POST | `{operationId, cancelPendingCalls?}` | Leave operation |
| `/operation/complete` | POST | `{operationId}` | Complete operation |
| `/operation/heartbeat` | POST | `{operationId}` | Send heartbeat |
| `/operation/abort` | POST | `{operationId, value}` | Set abort flag |
| `/operation/state` | POST | `{operationId}` | Get operation state |
| `/operation/log` | POST | `{operationId, message, level?}` | Write log entry |
| `/call/start` | POST | `{operationId, sessionId, description?, failOnCrash?}` | Start call |
| `/call/end` | POST | `{operationId, callId}` | End call successfully |
| `/call/fail` | POST | `{operationId, callId, error}` | Fail call with error |

---

### RemoteLedgerClient

HTTP client for remote ledger access. Provides the same API as `Ledger` but communicates with a remote `LedgerServer`.

```dart
class RemoteLedgerClient extends LedgerBase
```

#### Constructor

```dart
RemoteLedgerClient({
  required String serverUrl,
  required String participantId,
  int? participantPid,
  int maxBackups = 20,
  Duration heartbeatInterval = const Duration(seconds: 5),
  Duration staleThreshold = const Duration(seconds: 15),
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `serverUrl` | `String` | required | URL of the ledger server |
| `participantId` | `String` | required | Unique identifier for this client |
| `participantPid` | `int?` | current PID | Process ID |
| `maxBackups` | `int` | `20` | Maximum backups to retain |
| `heartbeatInterval` | `Duration` | 5 seconds | Heartbeat interval |
| `staleThreshold` | `Duration` | 15 seconds | Staleness threshold |

**Example:**

```dart
final client = RemoteLedgerClient(
  serverUrl: 'http://localhost:8765',
  participantId: 'remote_worker',
);
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `serverUrl` | `String` | URL of the ledger server |
| `participantId` | `String` | This client's participant ID |
| `participantPid` | `int` | This client's process ID |
| `maxBackups` | `int` | Maximum backups to retain |
| `heartbeatInterval` | `Duration` | Heartbeat interval |
| `staleThreshold` | `Duration` | Staleness threshold |

#### Methods

##### createOperation

Create a new operation on the remote server.

```dart
Future<RemoteOperation> createOperation({
  String? description,
  OperationCallback? callback,
})
```

**Returns:** `RemoteOperation` - Remote operation handle with heartbeat auto-started.

##### joinOperation

Join an existing operation on the remote server.

```dart
Future<RemoteOperation> joinOperation({
  required String operationId,
  OperationCallback? callback,
})
```

**Returns:** `RemoteOperation` - Remote operation handle.

##### dispose

Dispose of the client and stop all heartbeats.

```dart
void dispose()
```

---

### RemoteOperation

Remote operation handle with session tracking. Implements `OperationBase` and provides the **same unified API** as `Operation` but communicates with a remote server.

**Unified API**: `RemoteOperation` has the same typed API as `Operation`:
- `startCall<T>()` returns `Call<T>` (same as local)
- `spawnCall<T>()` returns `SpawnedCall<T>` (same as local)
- Full `CallCallback<T>` support (callbacks execute client-side)
- Full session call tracking

```dart
class RemoteOperation implements OperationBase
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `operationId` | `String` | The operation ID |
| `participantId` | `String` | The participant ID |
| `pid` | `int` | Process ID |
| `isInitiator` | `bool` | Whether this is the initiator |
| `sessionId` | `int` | Session ID for this handle |
| `startTime` | `DateTime` | When operation was started |
| `isAborted` | `bool` | Whether this participant is aborted |
| `onAbort` | `Future<void>` | Completes when abort is signaled |
| `onFailure` | `Future<OperationFailedInfo>` | Completes when operation fails |
| `elapsedFormatted` | `String` | Elapsed time as "SSS.mmm" |
| `elapsedDuration` | `Duration` | Elapsed duration since start |
| `startTimeIso` | `String` | Start time as ISO 8601 string |
| `startTimeMs` | `int` | Start time in milliseconds since epoch |

#### Methods

##### startCall

Start a typed call tracked to this session. Returns `Call<T>` with full callback support.

```dart
Future<Call<T>> startCall<T>({
  CallCallback<T>? callback,
  String? description,
  bool failOnCrash = true,
})
```

**Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `callback` | `CallCallback<T>?` | `null` | Callbacks for completion, cleanup, crash |
| `description` | `String?` | `null` | Human-readable call description |
| `failOnCrash` | `bool` | `true` | Whether crash fails entire operation |

**Returns:** `Call<T>` - Typed call handle (same as local `Operation.startCall<T>()`).

##### spawnCall

Spawn a typed call that runs work asynchronously.

```dart
SpawnedCall<T> spawnCall<T>({
  Future<T> Function()? work,
  Future<T> Function(SpawnedCall<T>)? workWithCall,
  CallCallback<T>? callback,
  String? description,
  bool failOnCrash = true,
})
```

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `work` | `Future<T> Function()?` | Async work function |
| `workWithCall` | `Future<T> Function(SpawnedCall<T>)?` | Work with call access |
| `callback` | `CallCallback<T>?` | Callbacks for completion, cleanup, crash |
| `description` | `String?` | Human-readable call description |
| `failOnCrash` | `bool` | Whether crash fails entire operation |

**Returns:** `SpawnedCall<T>` - Typed spawned call handle (same as local).

##### Session Call Tracking

```dart
/// Whether there are pending calls in this session
bool hasPendingCalls()

/// Get list of pending call IDs
List<String> getPendingCalls()

/// Get list of pending spawned calls
List<SpawnedCall> getPendingSpawnedCalls()
```

##### sync

Wait for multiple spawned calls to complete.

```dart
Future<SyncResult> sync(
  List<SpawnedCall> calls, {
  Future<void> Function(OperationFailedInfo)? onOperationFailed,
})
```

##### awaitCall

Wait for a spawned call and get its result.

```dart
Future<T> awaitCall<T>(SpawnedCall<T> call)
```

##### waitForCompletion

Execute work and wait for completion with operation failure handling.

```dart
Future<T> waitForCompletion<T>(
  Future<T> Function() work, {
  Future<void> Function(OperationFailedInfo)? onOperationFailed,
  Future<T> Function(Object, StackTrace)? onError,
})
```

##### leave

Leave this session of the operation.

```dart
Future<void> leave({bool cancelPendingCalls = false})
```

##### log

Write an entry to the operation log.

```dart
Future<void> log(String message, {LogLevel level = LogLevel.info})
```

##### complete

Complete the operation (for initiator only).

```dart
Future<void> complete()
```

##### setAbortFlag

Set the abort flag on the operation.

```dart
Future<void> setAbortFlag(bool value)
```

##### checkAbort

Check if the operation is aborted.

```dart
Future<bool> checkAbort()
```

##### triggerAbort

Trigger local abort for this participant.

```dart
void triggerAbort()
```

##### startHeartbeat

Start the client-side heartbeat.

```dart
void startHeartbeat({
  Duration interval = const Duration(milliseconds: 4500),
  int jitterMs = 500,
  HeartbeatErrorCallback? onError,
  HeartbeatSuccessCallback? onSuccess,
})
```

##### stopHeartbeat

Stop the heartbeat.

```dart
void stopHeartbeat()
```

##### heartbeat

Perform a single heartbeat.

```dart
Future<HeartbeatResult?> heartbeat()
```

---

### RemoteLedgerException

Exception thrown by remote ledger operations.

```dart
class RemoteLedgerException implements Exception
```

#### Constructor

```dart
RemoteLedgerException(String message, {int? statusCode})
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `message` | `String` | Error message from server |
| `statusCode` | `int?` | HTTP status code |

**Example:**

```dart
try {
  final op = await client.joinOperation(operationId: 'invalid');
} on RemoteLedgerException catch (e) {
  print('Error: ${e.message} (status: ${e.statusCode})');
}
```

---

## Call Classes

### Call Class

Represents an active synchronous call. Returned by `Operation.startCall()`.

```dart
class Call<T>
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `callId` | `String` | Unique call identifier |
| `description` | `String?` | Optional description |
| `startedAt` | `DateTime` | When the call started |
| `isCompleted` | `bool` | Whether call has been ended/failed |

### Methods

#### end

End the call successfully with an optional result.

```dart
Future<void> end([T? result])
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `result` | `T?` | `null` | Optional result value |

**Throws:** `StateError` if call already completed.

**Example:**

```dart
final call = await operation.startCall<int>();
// ... do work ...
await call.end(42);  // End with result
```

#### fail

Fail the call with an error.

```dart
Future<void> fail(Object error, [StackTrace? stackTrace])
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `error` | `Object` | required | The error |
| `stackTrace` | `StackTrace?` | `null` | Optional stack trace |

**Throws:** `StateError` if call already completed.

**Example:**

```dart
try {
  await doWork();
  await call.end();
} catch (e, st) {
  await call.fail(e, st);
}
```

---

### SpawnedCall Class

Represents a call that was spawned asynchronously.

```dart
class SpawnedCall<T>
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `callId` | `String` | Unique call identifier (available immediately) |
| `description` | `String?` | Optional description |
| `isCompleted` | `bool` | Whether call has completed |
| `isSuccess` | `bool` | Whether call completed successfully |
| `isFailed` | `bool` | Whether call failed/crashed |
| `isCancelled` | `bool` | Whether cancellation was requested |
| `result` | `T` | Result value (throws if not completed or failed) |
| `resultOrNull` | `T?` | Result if successful, null otherwise |
| `error` | `Object?` | Error if failed |
| `stackTrace` | `StackTrace?` | Stack trace if failed |
| `future` | `Future<void>` | Completes when call finishes |

### Methods

#### cancel

Request cancellation of this call.

```dart
Future<void> cancel()
```

Sets `isCancelled` to true and invokes the cancellation callback. Work functions should check `isCancelled` periodically and exit gracefully.

**Example:**

```dart
final call = operation.spawnCall<int>(
  workWithCall: (c) async {
    for (var i = 0; i < 100; i++) {
      if (c.isCancelled) return -1;  // Check cancellation
      await doChunk(i);
    }
    return 100;
  },
);

// Later...
await call.cancel();  // Request cancellation
```

#### kill

Forcefully terminate the associated process.

```dart
bool kill([ProcessSignal signal = ProcessSignal.sigterm])
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `signal` | `ProcessSignal` | `SIGTERM` | Signal to send |

**Returns:** `true` if process was killed, `false` if no process attached.

**Example:**

```dart
final worker = operation.execStdioWorker<Map>(...);
// Later, if we need to force stop:
worker.kill();
```

#### await_

Wait for the call to complete and return the result.

```dart
Future<T> await_()
```

**Returns:** The result of type `T`.

**Throws:** `StateError` if call failed.

**Example:**

```dart
final call = operation.spawnCall<int>(work: () async => 42);
final value = await call.await_();  // Returns 42
print('Got: $value');
```

#### resultOr

Get result if successful, or provided default value.

```dart
T resultOr(T defaultValue)
```

---

## SyncResult Class

Result of an `Operation.sync()` call.

```dart
class SyncResult
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `successfulCalls` | `List<SpawnedCall>` | Calls that completed successfully |
| `failedCalls` | `List<SpawnedCall>` | Calls that failed/crashed |
| `unknownCalls` | `List<SpawnedCall>` | Calls with unknown outcome |
| `operationFailed` | `bool` | Whether the operation itself failed |
| `allSucceeded` | `bool` | True if no failures and no unknowns |
| `hasFailed` | `bool` | True if any calls failed |
| `allResolved` | `bool` | True if no unknown calls |

---

## OperationHelper Class

Static helper methods for common operation patterns.

```dart
class OperationHelper
```

### pollFile

Create a function that polls for a file to appear.

```dart
static Future<T> Function() pollFile<T>({
  required String path,
  bool delete = false,
  T Function(String content)? deserializer,
  Duration pollInterval = const Duration(milliseconds: 100),
  Duration? timeout,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `path` | `String` | required | Absolute path to file |
| `delete` | `bool` | `false` | Delete file after reading |
| `deserializer` | `T Function(String)?` | `null` | Parse content |
| `pollInterval` | `Duration` | 100ms | Poll frequency |
| `timeout` | `Duration?` | `null` | Optional timeout |

**Default behavior:** If no deserializer and `T` is `String`, returns raw content. If `T` is `Map<String, dynamic>`, uses `jsonDecode`.

**Returns:** A function suitable for `waitForCompletion()`.

### pollUntil

Create a function that polls until condition returns non-null.

```dart
static Future<T> Function() pollUntil<T>({
  required Future<T?> Function() check,
  Duration pollInterval = const Duration(milliseconds: 100),
  Duration? timeout,
})
```

### pollFiles

Create a function that waits for multiple files.

```dart
static Future<List<T>> Function() pollFiles<T>({
  required List<String> paths,
  bool delete = false,
  T Function(String content)? deserializer,
  Duration pollInterval = const Duration(milliseconds: 100),
  Duration? timeout,
})
```

---

## Data Classes

### LedgerCallback Class

Callback structure for ledger-level events.

```dart
class LedgerCallback {
  final void Function(String path)? onBackupCreated;
  final void Function(String line)? onLogLine;
  final HeartbeatErrorCallback? onGlobalHeartbeatError;

  const LedgerCallback({
    this.onBackupCreated,
    this.onLogLine,
    this.onGlobalHeartbeatError,
  });
}
```

| Property | Type | Description |
|----------|------|-------------|
| `onBackupCreated` | `void Function(String)?` | Called when a backup file is created |
| `onLogLine` | `void Function(String)?` | Called for each log line during backup/restore |
| `onGlobalHeartbeatError` | `HeartbeatErrorCallback?` | Called when any operation's heartbeat detects a failure |

**Example:**
```dart
final ledger = Ledger(
  basePath: '/tmp/ledger',
  participantId: 'cli',
  callback: LedgerCallback(
    onBackupCreated: (path) => print('Backup created: $path'),
    onLogLine: (line) => print('Ledger: $line'),
    onGlobalHeartbeatError: (op, error) => print('Heartbeat error: ${error.message}'),
  ),
);
```

### OperationCallback Class

Callback structure for operation-level events (heartbeat monitoring, abort, failure).

```dart
class OperationCallback {
  final void Function(Operation operation, HeartbeatResult result)? onHeartbeatSuccess;
  final void Function(Operation operation, HeartbeatError error)? onHeartbeatError;
  final void Function(Operation operation)? onAbort;
  final void Function(Operation operation, OperationFailedInfo info)? onFailure;

  const OperationCallback({
    this.onHeartbeatSuccess,
    this.onHeartbeatError,
    this.onAbort,
    this.onFailure,
  });
  
  factory OperationCallback.onError(
    void Function(Operation operation, HeartbeatError error) onError,
  );
  
  factory OperationCallback.onFailure(
    void Function(Operation operation, OperationFailedInfo info) onFailure,
  );
}
```

| Property | Type | Description |
|----------|------|-------------|
| `onHeartbeatSuccess` | `void Function(Operation, HeartbeatResult)?` | Called on each successful heartbeat |
| `onHeartbeatError` | `void Function(Operation, HeartbeatError)?` | Called when heartbeat detects a failure |
| `onAbort` | `void Function(Operation)?` | Called when operation is aborted |
| `onFailure` | `void Function(Operation, OperationFailedInfo)?` | Called when operation fails |

**Callback vs Future pattern:** `onAbort` and `onFailure` are alternatives to the `Operation.onAbort` and `Operation.onFailure` futures. Both approaches are valid:
- Use **callbacks** for a reactive, event-driven style
- Use **futures** for racing with other work or async/await patterns

**Example:**
```dart
final op = await ledger.createOperation(
  callback: OperationCallback(
    onHeartbeatSuccess: (op, result) => print('♥ OK: ${result.callFrameCount} frames'),
    onHeartbeatError: (op, error) => print('Failure: ${error.message}'),
    onAbort: (op) => print('Operation aborted!'),
    onFailure: (op, info) => print('Operation failed: ${info.reason}'),
  ),
);

// Alternative: Use futures for racing
await Future.any([
  doWork(),
  op.onFailure.then((info) => throw OperationFailedException(info)),
]);
```

### CallCallback Class

Callback structure for call operations.

```dart
class CallCallback<T> {
  final Future<void> Function()? onCleanup;
  final Future<void> Function(T result)? onCompletion;
  final Future<T?> Function()? onCallCrashed;
  final Future<void> Function(OperationFailedInfo info)? onOperationFailed;

  CallCallback({...});
  
  factory CallCallback.cleanup(Future<void> Function() onCleanup);
}
```

| Property | Type | Description |
|----------|------|-------------|
| `onCleanup` | `Future<void> Function()?` | Called during cleanup |
| `onCompletion` | `Future<void> Function(T)?` | Called on success with result |
| `onCallCrashed` | `Future<T?> Function()?` | Return fallback or null on crash |
| `onOperationFailed` | `Future<void> Function(OperationFailedInfo)?` | Called when operation fails |

### OperationFailedInfo Class

Information about an operation failure.

```dart
class OperationFailedInfo {
  final String operationId;
  final DateTime failedAt;
  final String? reason;
  final List<String> crashedCallIds;
}
```

### OperationFailedException Class

Exception thrown when operation fails during `waitForCompletion`.

```dart
class OperationFailedException implements Exception {
  final OperationFailedInfo info;
  
  OperationFailedException(this.info);
}
```

### LedgerData Class

Operation ledger data structure (serialized to JSON file).

| Property | Type | Description |
|----------|------|-------------|
| `operationId` | `String` | Unique operation identifier |
| `initiatorId` | `String` | ID of participant that created operation |
| `startTime` | `DateTime` | When operation was created |
| `aborted` | `bool` | Whether abort flag is set |
| `lastHeartbeat` | `DateTime` | Global last heartbeat timestamp |
| `callFrames` | `List<CallFrame>` | Active call frames |
| `tempResources` | `List<TempResource>` | Registered temporary resources |
| `operationState` | `OperationState` | Current operation state |
| `detectionTimestamp` | `DateTime?` | When cleanup detection occurred |
| `removalTimestamp` | `DateTime?` | When frame removal occurred |
| `isEmpty` | `bool` | True if no call frames and no temp resources |

### CallFrame Class

A call frame in the operation.

| Property | Type | Description |
|----------|------|-------------|
| `participantId` | `String` | Participant that owns this frame |
| `callId` | `String` | Unique call identifier |
| `pid` | `int` | Process ID |
| `startTime` | `DateTime` | When call started |
| `lastHeartbeat` | `DateTime` | Last heartbeat for this participant |
| `state` | `FrameState` | Frame state during cleanup |
| `description` | `String?` | Optional description |
| `resources` | `List<String>` | Temporary resources for this call |
| `failOnCrash` | `bool` | Whether crash fails entire operation |
| `heartbeatAgeMs` | `int` | Age of heartbeat in milliseconds |

### HeartbeatResult Class

Result of heartbeat checks.

| Property | Type | Description |
|----------|------|-------------|
| `abortFlag` | `bool` | Whether abort flag is set |
| `ledgerExists` | `bool` | Whether ledger file exists |
| `heartbeatUpdated` | `bool` | Whether heartbeat was updated |
| `callFrameCount` | `int` | Number of call frames |
| `tempResourceCount` | `int` | Number of temp resources |
| `heartbeatAgeMs` | `int` | Global heartbeat age in ms |
| `isStale` | `bool` | Whether any participant is stale |
| `participants` | `List<String>` | Participant IDs in call frames |
| `participantHeartbeatAges` | `Map<String, int>` | Per-participant heartbeat ages |
| `staleParticipants` | `List<String>` | Participants with stale heartbeats |
| `hasStaleChildren` | `bool` | Whether any child is stale |
| `dataBefore` | `LedgerData?` | Ledger data before heartbeat update |
| `dataAfter` | `LedgerData?` | Ledger data after heartbeat update |

---

## Enums

### OperationState

Operation state during cleanup process.

| Value | Description |
|-------|-------------|
| `running` | Operation is running normally |
| `cleanup` | Failure detected, cleanup in progress |
| `failed` | Cleanup complete, operation failed |
| `completed` | Operation completed successfully |

### FrameState

Frame state during cleanup process.

| Value | Description |
|-------|-------------|
| `active` | Frame is executing normally |
| `crashed` | Frame's participant has crashed |
| `cleaningUp` | Frame marked as cleanup coordinator |
| `cleanedUp` | Frame has completed cleanup |

### LogLevel

Log levels for operation logging.

| Value | Description |
|-------|-------------|
| `debug` | Debug messages |
| `info` | Informational messages |
| `warning` | Warning messages |
| `error` | Error messages |

### HeartbeatErrorType

Heartbeat error types.

| Value | Description |
|-------|-------------|
| `ledgerNotFound` | Operation file not found |
| `lockFailed` | Failed to acquire lock |
| `abortFlagSet` | Abort flag is set |
| `heartbeatStale` | Heartbeat is stale |
| `ioError` | I/O error occurred |

---

## Type Definitions

### HeartbeatErrorCallback

```dart
typedef HeartbeatErrorCallback = void Function(
  Operation operation,
  HeartbeatError error,
);
```

### HeartbeatSuccessCallback

```dart
typedef HeartbeatSuccessCallback = void Function(
  Operation operation,
  HeartbeatResult result,
);
```

---

## Usage Examples

### Basic Operation with Call<T>

```dart
// Create ledger with default participant
final ledger = Ledger(
  basePath: '/tmp/ledger',
  participantId: 'main',
);

// Create operation (initiator)
final operation = await ledger.createOperation();

// Start heartbeat
operation.startHeartbeat();

// Start a call - returns Call<T> object
final call = await operation.startCall<void>(
  callback: CallCallback(
    onCleanup: () async => print('Cleaning up'),
  ),
);

try {
  await doSomeWork();
  await call.end();  // End successfully
} catch (e, st) {
  await call.fail(e, st);  // Fail with error
}

// Complete operation
await operation.complete();
await ledger.dispose();
```

### Spawned Calls with Typed Results

```dart
// Spawn multiple async calls - returns immediately!
final call1 = operation.spawnCall<int>(
  work: () async {
    await Future.delayed(Duration(seconds: 2));
    return 42;
  },
  callback: CallCallback(
    onCallCrashed: () async => -1,  // Fallback on crash
  ),
);

final call2 = operation.spawnCall<String>(
  work: () async {
    await Future.delayed(Duration(seconds: 1));
    return 'hello';
  },
);

// callIds are available immediately
print('Started: ${call1.callId}, ${call2.callId}');

// Wait for all calls
final result = await operation.sync([call1, call2]);

if (result.allSucceeded) {
  print('Call 1: ${call1.result}');  // 42
  print('Call 2: ${call2.result}');  // 'hello'
}
```

### Worker Process with Control Methods

```dart
// Spawn worker with access to SpawnedCall for cancellation
final worker = operation.execFileResultWorker<Map<String, dynamic>>(
  executable: 'dart',
  arguments: ['run', 'worker.dart', '--output', resultPath],
  resultFilePath: resultPath,
  onExit: (code) => print('Worker exited: $code'),
);

// callId available immediately
print('Worker started: ${worker.callId}');

// Can cancel or kill if needed
// await worker.cancel();  // Cooperative cancellation
// worker.kill();          // Force kill process

// Wait for result
try {
  final result = await worker.await_();
  print('Worker result: $result');
} catch (e) {
  print('Worker failed: ${worker.error}');
}
```

### Error Handling with waitForCompletion

```dart
try {
  final result = await operation.waitForCompletion<int>(
    () async => await riskyComputation(),
    onOperationFailed: (info) async {
      print('Operation failed: ${info.reason}');
    },
    onError: (error, stackTrace) async {
      print('Error in work: $error');
      return -1;  // Fallback value
    },
  );
  print('Result: $result');
} on OperationFailedException catch (e) {
  print('Operation failed before work completed: ${e.info.reason}');
}
```

---

*Generated from tom_dist_ledger v2.0 implementation*
