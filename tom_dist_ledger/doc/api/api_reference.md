# Distributed Ledger API Reference

Comprehensive API reference for the `tom_dist_ledger` package.

---

## Table of Contents

1. [Ledger Class](#ledger-class)
2. [Operation Class](#operation-class)
3. [Call Class](#call-class)
4. [SpawnedCall Class](#spawnedcall-class)
5. [SyncResult Class](#syncresult-class)
6. [OperationHelper Class](#operationhelper-class)
7. [Data Classes](#data-classes)
8. [Enums](#enums)
9. [Type Definitions](#type-definitions)
10. [Usage Examples](#usage-examples)

---

## Ledger Class

Main entry point for the distributed ledger system.

```dart
class Ledger
```

### Constructor

```dart
Ledger({
  required String basePath,
  String? participantId,
  int? participantPid,
  void Function(String)? onBackupCreated,
  void Function(String)? onLogLine,
  HeartbeatErrorCallback? onGlobalHeartbeatError,
  int maxBackups = 20,
  Duration heartbeatInterval = const Duration(seconds: 5),
  Duration staleThreshold = const Duration(seconds: 15),
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `basePath` | `String` | required | Directory path for ledger files |
| `participantId` | `String?` | `null` | Default participant ID for operations |
| `participantPid` | `int?` | current PID | Default process ID for this participant |
| `onBackupCreated` | `void Function(String)?` | `null` | Callback when backup is created |
| `onLogLine` | `void Function(String)?` | `null` | Callback for log lines |
| `onGlobalHeartbeatError` | `HeartbeatErrorCallback?` | `null` | Callback for heartbeat errors |
| `maxBackups` | `int` | `20` | Maximum backup operations to retain |
| `heartbeatInterval` | `Duration` | 5 seconds | Interval between heartbeats |
| `staleThreshold` | `Duration` | 15 seconds | Threshold for detecting stale participants |

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `operations` | `Map<String, Operation>` | All active operations (unmodifiable) |

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

**Returns:** `Operation` - The new operation with heartbeat auto-started.

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

**Returns:** `Operation` - Handle to the joined operation with heartbeat auto-started.

**Note:** Heartbeat is automatically started on first join. If the same operation
is joined multiple times, the join count is incremented and the same Operation
object is returned. Each join should be matched with a `leave()` call.

#### getOperation

Get an operation by ID.

```dart
Operation? getOperation(String operationId)
```

#### dispose

Dispose the ledger and stop all heartbeats.

```dart
Future<void> dispose()
```

---

## Operation Class

Represents a running operation. Each participant gets their own Operation object.

```dart
class Operation
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
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
| `joinCount` | `int` | Number of times this operation has been joined |

### Call Management Methods

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

Throws `StateError` if:
- Join count is already 0
- There are still active spawned calls (must be ended or cancelled first)

```dart
void leave()
```

**Note:** This is for participants who joined an operation. Initiators
should call `complete()` instead.

**Example:**
```dart
// First call joins the operation
final op = await ledger.joinOperation(operationId: opId);
// ... do work for first call ...
op.leave(); // join count: 1 -> 0, heartbeat stops
```

For multiple joins:
```dart
final op1 = await ledger.joinOperation(operationId: opId);
final op2 = await ledger.joinOperation(operationId: opId); // Same op
// join count is now 2
op1.leave(); // join count: 2 -> 1, heartbeat continues
op2.leave(); // join count: 1 -> 0, heartbeat stops
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

## Call Class

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

## SpawnedCall Class

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

### OperationCallback Class

Callback structure for operation-level events (heartbeat monitoring).

```dart
class OperationCallback {
  final void Function(Operation operation, HeartbeatResult result)? onHeartbeatSuccess;
  final void Function(Operation operation, HeartbeatError error)? onHeartbeatError;

  const OperationCallback({
    this.onHeartbeatSuccess,
    this.onHeartbeatError,
  });
  
  factory OperationCallback.onError(
    void Function(Operation operation, HeartbeatError error) onError,
  );
}
```

| Property | Type | Description |
|----------|------|-------------|
| `onHeartbeatSuccess` | `void Function(Operation, HeartbeatResult)?` | Called on each successful heartbeat |
| `onHeartbeatError` | `void Function(Operation, HeartbeatError)?` | Called when heartbeat detects a failure |

**Example:**
```dart
final op = await ledger.createOperation(
  callback: OperationCallback(
    onHeartbeatSuccess: (op, result) => print('♥ OK: ${result.stackDepth} frames'),
    onHeartbeatError: (op, error) => print('Failure: ${error.message}'),
  ),
);
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
| `stack` | `List<StackFrame>` | Active call stack frames |
| `tempResources` | `List<TempResource>` | Registered temporary resources |
| `operationState` | `OperationState` | Current operation state |
| `detectionTimestamp` | `DateTime?` | When cleanup detection occurred |
| `removalTimestamp` | `DateTime?` | When frame removal occurred |
| `isEmpty` | `bool` | True if no stack frames and no temp resources |

### StackFrame Class

A stack frame in the operation.

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
| `stackDepth` | `int` | Number of stack frames |
| `tempResourceCount` | `int` | Number of temp resources |
| `heartbeatAgeMs` | `int` | Global heartbeat age in ms |
| `isStale` | `bool` | Whether any participant is stale |
| `stackParticipants` | `List<String>` | Participant IDs in stack |
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
