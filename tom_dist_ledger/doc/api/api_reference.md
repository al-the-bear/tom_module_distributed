# Tom Dist Ledger API Reference

This document provides a comprehensive API reference for the distributed ledger library, based on the actual implementation.

---

## Table of Contents

1. [Core Classes](#core-classes)
   - [Ledger](#ledger-class)
   - [Operation](#operation-class)
   - [SpawnedCall](#spawnedcall-class)
   - [SyncResult](#syncresult-class)
   - [OperationHelper](#operationhelper-class)
2. [Data Classes](#data-classes)
   - [CallCallback](#callcallback-class)
   - [OperationFailedInfo](#operationfailedinfo-class)
   - [LedgerData](#ledgerdata-class)
   - [StackFrame](#stackframe-class)
   - [TempResource](#tempresource-class)
   - [HeartbeatResult](#heartbeatresult-class)
   - [HeartbeatError](#heartbeaterror-class)
3. [Enums](#enums)
   - [OperationState](#operationstate-enum)
   - [FrameState](#framestate-enum)
   - [LogLevel](#loglevel-enum)
   - [HeartbeatErrorType](#heartbeaterrortype-enum)
4. [Type Definitions](#type-definitions)

---

## Core Classes

### Ledger Class

Global ledger that manages all operations.

The Ledger is responsible for:
- Creating and managing operation files
- Maintaining a registry of active operations
- Providing global heartbeat monitoring
- Managing log files for each operation
- Managing backups and backup cleanup

#### Constructor

```dart
Ledger({
  required String basePath,
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
| `basePath` | `String` | required | Base directory for ledger files |
| `onBackupCreated` | `void Function(String)?` | `null` | Callback when backup is created |
| `onLogLine` | `void Function(String)?` | `null` | Callback for each log line |
| `onGlobalHeartbeatError` | `HeartbeatErrorCallback?` | `null` | Callback for global heartbeat errors |
| `maxBackups` | `int` | `20` | Maximum backup operations to retain |
| `heartbeatInterval` | `Duration` | `5 seconds` | Interval for global heartbeat monitoring |
| `staleThreshold` | `Duration` | `15 seconds` | Threshold for detecting stale operations |

**Note:** The global heartbeat is automatically started when the Ledger is created.

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `operations` | `Map<String, Operation>` | Read-only map of active operations |
| `basePath` | `String` | Base directory path |
| `maxBackups` | `int` | Maximum backups to retain |
| `heartbeatInterval` | `Duration` | Global heartbeat interval |
| `staleThreshold` | `Duration` | Staleness threshold for operations |

#### Methods

##### createOperation

Create a new operation (for the initiator).

```dart
Future<Operation> createOperation({
  required String participantId,
  String? operationId,
  int? participantPid,
  String? description,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `participantId` | `String` | required | Unique identifier for this participant |
| `operationId` | `String?` | auto-generated | Optional explicit operation ID (for testing or external coordination) |
| `participantPid` | `int?` | `Platform.pid` | Process ID of the participant (defaults to current process) |
| `description` | `String?` | `null` | Optional operation description |

**Returns:** `Future<Operation>` - The created operation object.

##### joinOperation

Join an existing operation as a participant.

```dart
Future<Operation> joinOperation({
  required String operationId,
  required String participantId,
  int? participantPid,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `operationId` | `String` | required | ID of the operation to join |
| `participantId` | `String` | required | Unique identifier for this participant |
| `participantPid` | `int?` | `Platform.pid` | Process ID of the participant (defaults to current process) |

**Returns:** `Future<Operation>` - The operation object for this participant.

##### getOperation

Get an operation by ID.

```dart
Operation? getOperation(String operationId)
```

##### dispose

Dispose of the ledger and stop all heartbeats.

```dart
void dispose()
```

---

### Operation Class

Represents a running operation.

Each participant gets their own Operation object to interact with the shared operation file and log.

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `operationId` | `String` | Unique ID for this operation |
| `participantId` | `String` | ID of this participant |
| `pid` | `int` | Process ID of this participant |
| `isInitiator` | `bool` | Whether this participant started the operation |
| `isAborted` | `bool` | Whether this participant is aborted |
| `startTime` | `DateTime` | When the operation was started (from operation.json) |
| `elapsedDuration` | `Duration` | Duration since operation start |
| `startTimeIso` | `String` | Start time as ISO 8601 string |
| `startTimeMs` | `int` | Start time as milliseconds since epoch |
| `cachedData` | `LedgerData?` | Cached operation data |
| `lastChangeTimestamp` | `DateTime?` | Last change timestamp |
| `elapsedFormatted` | `String` | Current elapsed time formatted as "SSS.mmm" (computed from startTime) |
| `onAbort` | `Future<void>` | Future that completes when abort is signaled |
| `onFailure` | `Future<OperationFailedInfo>` | Future that completes when operation fails |
| `stalenessThresholdMs` | `int` | Staleness threshold in milliseconds (default: 10000) |

#### Call Management Methods

##### startCall

Start a tracked call with callback.

```dart
Future<String> startCall({
  required CallCallback callback,
  String? description,
  bool failOnCrash = true,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `callback` | `CallCallback` | required | Callback for cleanup and crash handling |
| `description` | `String?` | `null` | Optional description |
| `failOnCrash` | `bool` | `true` | Whether crash should fail entire operation |

**Returns:** `Future<String>` - Ledger-generated call ID.

##### endCall

End a tracked call successfully.

```dart
Future<void> endCall({required String callId})
```

##### failCall

Fail a call due to an error. Removes the stack frame, logs failure, and calls cleanup.

```dart
Future<void> failCall({
  required String callId,
  required Object error,
  StackTrace? stackTrace,
})
```

##### spawnCall

Spawn a typed call that runs asynchronously and returns a result.

**Returns immediately** - the call executes in the background. Access `callId` immediately, await `.future` for the result.

```dart
SpawnedCall<T> spawnCall<T>({
  required Future<T> Function() work,
  CallCallback<T>? callback,
  String? description,
  bool failOnCrash = true,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `work` | `Future<T> Function()` | required | The async work to execute |
| `callback` | `CallCallback<T>?` | `null` | Optional callbacks for completion/crash/cleanup |
| `description` | `String?` | `null` | Optional description |
| `failOnCrash` | `bool` | `true` | Whether crash should fail entire operation |

**Returns:** `SpawnedCall<T>` - Handle to track the call. Access `callId` immediately.

**Example:**

```dart
final call = operation.spawnCall<int>(
  work: () async => await computeExpensiveValue(),
  callback: CallCallback<int>(
    onCompletion: (result) async => print('Got: $result'),
    onCallCrashed: () async => 0, // Fallback value
    onOperationFailed: (info) async => print('Op failed!'),
  ),
);

// callId is available immediately
print('Started call: ${call.callId}');

// Wait for result when needed
await call.future;
print('Result: ${call.result}');
```

##### sync

Wait for spawned calls to complete and get a SyncResult.

```dart
Future<SyncResult> sync(
  List<SpawnedCall> calls, {
  Future<void> Function(OperationFailedInfo info)? onOperationFailed,
  Future<void> Function()? onCompletion,
})
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `calls` | `List<SpawnedCall>` | List of spawned calls to wait for |
| `onOperationFailed` | `Function?` | Called if operation fails during sync |
| `onCompletion` | `Function?` | Called when all calls complete |

**Returns:** `Future<SyncResult>` - Result containing successful, failed, and unknown calls.

**Note:** Individual call crash handling is done via the `onCallCrashed` callback provided to `spawnCall()` at spawn time. This method only notifies about operation-level failures.

**Example:**

```dart
final call1 = operation.spawnCall<int>(work: () async => 42);
final call2 = operation.spawnCall<String>(work: () async => 'hello');

final result = await operation.sync([call1, call2]);

if (result.allSucceeded) {
  print('All done: ${call1.result}, ${call2.result}');
}
```

##### awaitCall

Convenience method to wait for a single spawned call.

```dart
Future<SyncResult> awaitCall(
  SpawnedCall call, {
  Future<void> Function(OperationFailedInfo info)? onOperationFailed,
  Future<void> Function()? onCompletion,
})
```

**Returns:** `Future<SyncResult>` - Wraps `sync([call], ...)`.

#### Execution Helper Methods

These convenience methods combine `spawnCall` with process spawning and result collection, reducing boilerplate for common patterns.

**All exec methods return immediately** - they return a `SpawnedCall<T>` that you can track and await when needed.

##### execFileResultWorker

Spawn a process that writes its result to a file. Returns immediately.

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
  bool failOnCrash = true,
  CallCallback<T>? callback,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `executable` | `String` | required | Path to executable (e.g., `'dart'`) |
| `arguments` | `List<String>` | required | Command-line arguments |
| `resultFilePath` | `String` | required | Path where worker writes result |
| `workingDirectory` | `String?` | `null` | Working directory for the process |
| `description` | `String?` | `null` | Optional call description |
| `deserializer` | `T Function(String)?` | `null` | Optional function to parse content |
| `deleteResultFile` | `bool` | `true` | Delete result file after reading |
| `pollInterval` | `Duration` | 100ms | How often to check for result file |
| `timeout` | `Duration?` | `null` | Optional timeout for file polling |
| `onStdout` | `void Function(String)?` | `null` | Callback for stdout lines |
| `onStderr` | `void Function(String)?` | `null` | Callback for stderr lines |
| `failOnCrash` | `bool` | `true` | Whether crash fails operation |
| `callback` | `CallCallback<T>?` | `null` | Optional callbacks |

**Returns:** `SpawnedCall<T>` - Returns immediately. Await `.future` for result.

**Example:**

```dart
final worker = operation.execFileResultWorker<Map<String, dynamic>>(
  executable: 'dart',
  arguments: [
    'run', 'worker.dart',
    '--operation-id=${operation.operationId}',
    '--output=$resultPath',
  ],
  resultFilePath: resultPath,
);

// callId available immediately
print('Started worker: ${worker.callId}');

// Wait for completion when needed
await worker.future;
if (worker.isSuccess) {
  print('Result: ${worker.result}');
}
```

##### execStdioWorker

Spawn a process that outputs its result to stdout as JSON. Returns immediately.

**Worker Requirements:** The worker process MUST:
- Output ONLY the JSON result to stdout (no other content)
- Use stderr for all status messages, progress, and debugging
- Exit with code 0 on success

```dart
SpawnedCall<T> execStdioWorker<T>({
  required String executable,
  required List<String> arguments,
  String? workingDirectory,
  String? description,
  T Function(String content)? deserializer,
  void Function(String line)? onStderr,
  Duration? timeout,
  bool failOnCrash = true,
  CallCallback<T>? callback,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `executable` | `String` | required | Path to executable |
| `arguments` | `List<String>` | required | Command-line arguments (including worker parameters) |
| `workingDirectory` | `String?` | `null` | Working directory for the process |
| `description` | `String?` | `null` | Optional call description |
| `deserializer` | `T Function(String)?` | json.decode | Function to parse stdout content |
| `onStderr` | `void Function(String)?` | `null` | Callback for stderr lines (for progress monitoring) |
| `timeout` | `Duration?` | `null` | Optional timeout |
| `failOnCrash` | `bool` | `true` | Whether crash fails operation |
| `callback` | `CallCallback<T>?` | `null` | Optional callbacks |

**Returns:** `SpawnedCall<T>` - Returns immediately. Await `.future` for result.

**Example Worker:**

```dart
// Worker writes status to stderr, result to stdout
void main(List<String> args) async {
  final param1 = args.firstWhere((a) => a.startsWith('--param1=')).split('=')[1];
  stderr.writeln('Processing...');  // Status to stderr
  await Future.delayed(Duration(seconds: 2));
  stdout.write(jsonEncode({'result': param1}));  // Only JSON to stdout
}
```

**Example Usage:**

```dart
final worker = operation.execStdioWorker<Map<String, dynamic>>(
  executable: 'dart',
  arguments: [
    'run', 'worker.dart',
    '--param1=hello',
    '--param2=world',
  ],
  onStderr: (line) => print('[Worker] $line'),
);

await worker.future;
if (worker.isSuccess) {
  final data = worker.result;  // Parsed JSON
}
```

##### execServerRequest

Execute a request to an already-running server process. Returns immediately.

```dart
SpawnedCall<T> execServerRequest<T>({
  required Future<T> Function() work,
  String? description,
  Duration? timeout,
  bool failOnCrash = true,
  CallCallback<T>? callback,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `work` | `Future<T> Function()` | required | Async function to execute (e.g., HTTP request) |
| `description` | `String?` | `null` | Optional call description |
| `timeout` | `Duration?` | `null` | Optional timeout |
| `failOnCrash` | `bool` | `true` | Whether crash fails operation |
| `callback` | `CallCallback<T>?` | `null` | Optional callbacks |

**Returns:** `SpawnedCall<T>` - Returns immediately. Await `.future` for result.

**Example:**

```dart
final request = operation.execServerRequest<String>(
  work: () async {
    final response = await http.get(Uri.parse('http://localhost:8080/api'));
    return response.body;
  },
);

// callId available immediately
print('Request ID: ${request.callId}');

await request.future;
if (request.isSuccess) {
  print('Response: ${request.result}');
}
```

#### Other Methods

##### log

Write an entry to the operation log.

```dart
Future<void> log(String message, {LogLevel level = LogLevel.info})
```

##### debugLog

Write an entry to the debug log (internal use only).

```dart
Future<void> debugLog(String message)
```

##### logMessage

Log a formatted message with timestamp, depth indentation, and participant.

```dart
Future<void> logMessage({
  required int depth,
  required String message,
})
```

##### waitForCompletion

Execute work while monitoring operation state. Interrupts if operation fails.

```dart
Future<void> waitForCompletion(
  Future<void> Function() work, {
  Future<void> Function(OperationFailedInfo info)? onOperationFailed,
})
```

##### registerTempResource

Register a temporary resource for cleanup tracking.

```dart
Future<void> registerTempResource({required String path})
```

##### unregisterTempResource

Unregister a temporary resource.

```dart
Future<void> unregisterTempResource({required String path})
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

Start the heartbeat for this participant.

```dart
void startHeartbeat({
  Duration interval = const Duration(milliseconds: 4500),
  int jitterMs = 500,
  HeartbeatErrorCallback? onError,
  HeartbeatSuccessCallback? onSuccess,
})
```

##### stopHeartbeat

Stop the heartbeat for this participant.

```dart
void stopHeartbeat()
```

##### heartbeat

Perform a single heartbeat and return the result.

```dart
Future<HeartbeatResult?> heartbeat()
```

##### complete

Complete the operation (initiator only). Moves files to backup.

```dart
Future<void> complete()
```

##### getOperationState

Get the current operation state.

```dart
Future<OperationState> getOperationState()
```

##### setOperationState

Set the operation state.

```dart
Future<void> setOperationState(OperationState state)
```

##### retrieveAndLockOperation

Lock the operation file for exclusive access during cleanup.

```dart
Future<LedgerData?> retrieveAndLockOperation()
```

##### writeAndUnlockOperation

Write operation data back and unlock the operation file.

```dart
Future<void> writeAndUnlockOperation(LedgerData data)
```

##### unlockOperation

Unlock the operation file without writing changes.

```dart
Future<void> unlockOperation()
```

#### Low-level Stack Frame Methods

These methods provide direct control over stack frame management. For most use cases, prefer `startCall`/`endCall` which provide structured call tracking with callbacks.

##### pushStackFrame

Push a stack frame for a call (low-level operation). Use this when you need direct control over stack frame management, testing stack behavior without callback overhead, or implementing custom call patterns.

```dart
Future<void> pushStackFrame({required String callId})
```

##### popStackFrame

Pop a stack frame for a call (low-level operation). Use this when you need direct control over stack frame management, testing stack behavior without callback overhead, or implementing custom call patterns.

```dart
Future<void> popStackFrame({required String callId})
```

---

### SpawnedCall Class

Represents a call that was spawned asynchronously.

```dart
class SpawnedCall<T>
```

#### Constructor

```dart
SpawnedCall({
  required String callId,
  String? description,
})
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `callId` | `String` | Unique identifier for this call (available immediately) |
| `description` | `String?` | Optional description |
| `isCompleted` | `bool` | Whether the call has completed |
| `isSuccess` | `bool` | Whether the call completed successfully |
| `isFailed` | `bool` | Whether the call failed/crashed |
| `result` | `T` | Result value (throws if not completed or failed) |
| `resultOrNull` | `T?` | Result if successful, null otherwise (safe accessor) |
| `error` | `Object?` | Error if failed |
| `stackTrace` | `StackTrace?` | Stack trace if failed |
| `future` | `Future<void>` | Future that completes when call finishes |

#### Methods

##### resultOr

Get result if successful, or provided default value.

```dart
T resultOr(T defaultValue)
```

##### complete

Complete this call successfully with the given result.

```dart
void complete(T result)
```

##### fail

Fail this call with the given error.

```dart
void fail(Object error, [StackTrace? stackTrace])
```

---

### SyncResult Class

Result of an `Operation.sync()` call.

#### Constructor

```dart
SyncResult({
  List<SpawnedCall> successfulCalls = const [],
  List<SpawnedCall> failedCalls = const [],
  List<SpawnedCall> unknownCalls = const [],
  bool operationFailed = false,
})
```

#### Properties

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

### OperationHelper Class

Static helper methods for common operation patterns.

All methods are static; the class cannot be instantiated.

#### pollFile

Creates a wait function that polls for a file to appear.

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
| `path` | `String` | required | Absolute path to file to wait for |
| `delete` | `bool` | `false` | Whether to delete file after reading |
| `deserializer` | `T Function(String)?` | `null` | Optional function to parse content |
| `pollInterval` | `Duration` | 100ms | How often to check for file |
| `timeout` | `Duration?` | `null` | Optional timeout; throws `TimeoutException` |

**Default behavior:**
- If `T` is `String`, returns raw content
- If `T` is `Map<String, dynamic>`, uses `jsonDecode(content)`

**Returns:** A function that when called, polls until file exists and returns content.

#### pollUntil

Creates a wait function that polls until a condition returns non-null.

```dart
static Future<T> Function() pollUntil<T>({
  required Future<T?> Function() check,
  Duration pollInterval = const Duration(milliseconds: 100),
  Duration? timeout,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `check` | `Future<T?> Function()` | required | Returns null to continue, value to complete |
| `pollInterval` | `Duration` | 100ms | How often to check |
| `timeout` | `Duration?` | `null` | Optional timeout |

#### pollFiles

Creates a wait function that waits for multiple files to appear.

```dart
static Future<List<T>> Function() pollFiles<T>({
  required List<String> paths,
  bool delete = false,
  T Function(String content)? deserializer,
  Duration pollInterval = const Duration(milliseconds: 100),
  Duration? timeout,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `paths` | `List<String>` | required | List of file paths to wait for |
| `delete` | `bool` | `false` | Whether to delete files after reading |
| `deserializer` | `T Function(String)?` | `null` | Optional function to parse content |
| `pollInterval` | `Duration` | 100ms | How often to check |
| `timeout` | `Duration?` | `null` | Optional timeout |

**Returns:** Contents in same order as input paths.

---

## Data Classes

### CallCallback Class

Callback structure for call operations.

The type parameter `T` matches the result type of the spawned call.

```dart
class CallCallback<T> {
  final Future<void> Function()? onCleanup;
  final Future<void> Function(T result)? onCompletion;
  final Future<T?> Function()? onCallCrashed;
  final Future<void> Function(OperationFailedInfo info)? onOperationFailed;

  CallCallback({
    this.onCleanup,
    this.onCompletion,
    this.onCallCrashed,
    this.onOperationFailed,
  });
}
```

| Property | Type | Description |
|----------|------|-------------|
| `onCleanup` | `Future<void> Function()?` | Called during cleanup (crash or normal end) |
| `onCompletion` | `Future<void> Function(T)?` | Called when call completes successfully with result |
| `onCallCrashed` | `Future<T?> Function()?` | Called when this call crashes. Return fallback or null |
| `onOperationFailed` | `Future<void> Function(OperationFailedInfo)?` | Called when the operation fails |

#### Factory Constructors

##### cleanup

Create a simple callback with just cleanup logic.

```dart
factory CallCallback.cleanup(Future<void> Function() onCleanup)
```

**Example:**

```dart
// Full callback with all handlers
final callback = CallCallback<int>(
  onCleanup: () async => print('Cleaning up'),
  onCompletion: (result) async => print('Got result: $result'),
  onCallCrashed: () async {
    print('Call crashed, returning fallback');
    return -1; // Fallback value
  },
  onOperationFailed: (info) async => print('Operation failed: ${info.reason}'),
);

// Simple cleanup-only callback
final simple = CallCallback<void>.cleanup(() async => tempFile.deleteSync());
```

---

### OperationFailedInfo Class

Information about an operation failure.

```dart
class OperationFailedInfo {
  final String operationId;
  final DateTime failedAt;
  final String? reason;
  final List<String> crashedCallIds;

  OperationFailedInfo({
    required this.operationId,
    required this.failedAt,
    this.reason,
    this.crashedCallIds = const [],
  });
}
```

| Property | Type | Description |
|----------|------|-------------|
| `operationId` | `String` | Operation that failed |
| `failedAt` | `DateTime` | When failure was detected |
| `reason` | `String?` | Reason for failure |
| `crashedCallIds` | `List<String>` | List of call IDs that crashed |

---

### LedgerData Class

Operation ledger data structure (serialized to JSON file).

| Property | Type | Description |
|----------|------|-------------|
| `operationId` | `String` | Unique operation identifier |
| `initiatorId` | `String` | ID of participant that created operation |
| `aborted` | `bool` | Whether abort flag is set |
| `lastHeartbeat` | `DateTime` | Global last heartbeat timestamp |
| `stack` | `List<StackFrame>` | Active call stack frames |
| `tempResources` | `List<TempResource>` | Registered temporary resources |
| `operationState` | `OperationState` | Current operation state |
| `detectionTimestamp` | `DateTime?` | When cleanup detection occurred |
| `removalTimestamp` | `DateTime?` | When frame removal occurred |
| `isEmpty` | `bool` | True if no stack frames and no temp resources |

---

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

#### Methods

##### isStale

Check if this participant's heartbeat is stale.

```dart
bool isStale({int timeoutMs = 10000})
```

---

### TempResource Class

A temporary resource registered in the ledger.

| Property | Type | Description |
|----------|------|-------------|
| `path` | `String` | Path to the resource |
| `owner` | `int` | Process ID of owner |
| `registeredAt` | `DateTime` | When resource was registered |

---

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
| `isStale` | `bool` | Whether any other participant is stale |
| `stackParticipants` | `List<String>` | List of participant IDs in stack |
| `participantHeartbeatAges` | `Map<String, int>` | Per-participant heartbeat ages |
| `staleParticipants` | `List<String>` | Participants with stale heartbeats |
| `hasStaleChildren` | `bool` | Whether any child is stale |

#### Factory Constructors

##### noLedger

Create a result for when ledger doesn't exist.

```dart
factory HeartbeatResult.noLedger()
```

---

### HeartbeatError Class

Heartbeat error with details.

```dart
class HeartbeatError {
  final HeartbeatErrorType type;
  final String message;
  final Object? cause;

  const HeartbeatError({
    required this.type,
    required this.message,
    this.cause,
  });
}
```

---

## Enums

### OperationState Enum

Operation state during cleanup process.

| Value | Description |
|-------|-------------|
| `running` | Operation is running normally |
| `cleanup` | Failure detected, cleanup in progress |
| `failed` | Cleanup complete, operation failed |
| `completed` | Operation completed successfully |

---

### FrameState Enum

Frame state during cleanup process.

| Value | Description |
|-------|-------------|
| `active` | Frame is executing normally |
| `crashed` | Frame's participant process has crashed |
| `cleaningUp` | Frame marked as cleanup coordinator |
| `cleanedUp` | Frame has completed cleanup |

---

### LogLevel Enum

Log levels for operation logging.

| Value | Description |
|-------|-------------|
| `debug` | Debug messages |
| `info` | Informational messages |
| `warning` | Warning messages |
| `error` | Error messages |

---

### HeartbeatErrorType Enum

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

Callback for heartbeat errors.

```dart
typedef HeartbeatErrorCallback = void Function(
  Operation operation,
  HeartbeatError error,
);
```

### HeartbeatSuccessCallback

Callback for successful heartbeat.

```dart
typedef HeartbeatSuccessCallback = void Function(
  Operation operation,
  HeartbeatResult result,
);
```

---

## Usage Examples

### Basic Operation

```dart
// Create ledger
final ledger = Ledger(basePath: '/tmp/ledger');

// Create operation (initiator)
final operation = await ledger.createOperation(
  participantId: 'main',
);

// Start heartbeat
operation.startHeartbeat();

// Do work with tracked calls
final callId = await operation.startCall(
  callback: CallCallback<void>(
    onCleanup: () async => print('Cleaning up'),
  ),
);

await doSomeWork();

await operation.endCall(callId: callId);

// Complete operation
await operation.complete();
ledger.dispose();
```

### Spawned Calls with Typed Results

```dart
// Spawn multiple async calls - returns immediately!
final call1 = operation.spawnCall<int>(
  work: () async {
    await Future.delayed(Duration(seconds: 2));
    return 42;
  },
  callback: CallCallback<int>(
    onCallCrashed: () async {
      print('Call 1 crashed, returning fallback');
      return -1;
    },
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
  print('Call 1 result: ${call1.result}');
  print('Call 2 result: ${call2.result}');
}
```

### Worker Process with File Result

```dart
// Spawn worker that writes result to file - returns immediately!
final worker = operation.execFileResultWorker<Map<String, dynamic>>(
  executable: 'dart',
  arguments: [
    'run', 'worker.dart',
    '--operation-id=${operation.operationId}',
    '--output=$resultPath',
  ],
  resultFilePath: resultPath,
);

// callId available immediately
print('Worker started: ${worker.callId}');

// Wait for result when needed
await worker.future;
if (worker.isSuccess) {
  print('Worker result: ${worker.result}');
}
```

### Polling for File Results

```dart
// Poll for result file
final waitForResult = OperationHelper.pollFile<Map<String, dynamic>>(
  path: '/tmp/result.json',
  delete: true,
  timeout: Duration(seconds: 30),
);

await operation.waitForCompletion(waitForResult);
```

---

*Generated from tom_dist_ledger implementation*
