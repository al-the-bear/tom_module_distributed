# Supervisor Orchestration Design

## Overview

This document describes the design for supervisor orchestration in the Distributed Process Ledger (DPL) system. It addresses:

1. How cleanup happens when participants crash (detailed sequence)
2. How supervisors track calls via the Supervisor API
3. How supervisors get notified of crashes in their domain
4. The Supervisor Orchestrator Daemon architecture

## Design Principles

1. **Supervisors are self-aware**: Each supervisor must detect and handle cleanup of orphaned calls/operations independently.
2. **One Ledger per isolate**: A Dart isolate has exactly one Ledger instance (supervisor-created or implicit).
3. **Frames know their supervisor**: Each stack frame has an optional `supervisorId` field.
4. **File-based orchestration**: All orchestration state is persisted to files for durability and restart recovery.
5. **Caller cleans up callee**: Failed calls are cleaned up by their caller (or supervisor if supervised).

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     SUPERVISOR ORCHESTRATOR DAEMON                       │
│                                                                         │
│  Monitors: {groupId}.orchestrator.json                                  │
│  Manages:  {groupId}.supervisors.json                                   │
│                                                                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │
│  │  Supervisor A   │  │  Supervisor B   │  │  Supervisor C   │         │
│  │  (Bridge)       │  │  (VSCode Ext)   │  │  (Other)        │         │
│  │  restartable    │  │  NOT restartable│  │  restartable    │         │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘         │
│           │                    │                    │                   │
│           ▼                    ▼                    ▼                   │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │              SUPERVISOR API (in-memory, per-isolate)             │   │
│  │  - Supervised call registry (Dart datastructure)                │   │
│  │  - Callbacks for call lifecycle events                          │   │
│  │  - Creates and owns the Ledger instance                         │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘

                                    │
                                    ▼

┌─────────────────────────────────────────────────────────────────────────┐
│                         OPERATION LEDGER FILE                           │
│                                                                         │
│  - Stack frames with:                                                   │
│    - participantId, callId, pid, lastHeartbeat                         │
│    - supervisorId (optional) - links frame to supervisor               │
│    - supervisorHandle (optional) - opaque handle for supervisor        │
│  - Supervisor heartbeats (supervisorId → status + lastHeartbeat)       │
│  - Operation state (running, aborted, cleanup, completed, failed)      │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Part 1: Cleanup Mechanism (Detailed)

### States

An operation progresses through these states:

```dart
enum OperationState {
  /// Operation is running normally.
  running,
  
  /// Abort has been requested (e.g., user Ctrl+C or failure detected).
  /// All live participants must mark their frames as aborted.
  aborted,
  
  /// All frames except failed ones are marked aborted.
  /// Cleanup phase begins - participants clean up and remove frames.
  cleanup,
  
  /// Operation completed successfully.
  completed,
  
  /// Operation failed (cleanup complete, failure recorded).
  failed,
}

enum FrameState {
  /// Frame is active and processing.
  active,
  
  /// Frame acknowledged abort, waiting to clean up.
  aborted,
  
  /// Frame is performing cleanup.
  cleaningUp,
  
  /// Frame detected as crashed (stale heartbeat).
  crashed,
  
  /// Frame has been cleaned up and can be removed.
  cleanedUp,
}
```

### Simplified Cleanup Sequence

The cleanup mechanism is automated and self-healing:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    SIMPLIFIED CLEANUP SEQUENCE                           │
└──────────────────────────────────────────────────────────────────────────┘

PHASE 1: FAILURE DETECTION
─────────────────────────────────────────────────────────────────────────────
1. Participant detects stale heartbeat of another participant
2. Detecting participant sets operation state to "cleanup"
3. Detecting participant marks the crashed frame(s) as "crashed"

PHASE 2: AUTOMATIC CLEANUP (Parallel, No Ordering)
─────────────────────────────────────────────────────────────────────────────

RULE 1: EVERY LIVE FRAME CLEANS ITSELF
   ┌─────────────────────────────────────────────────────────────────────┐
   │ When operation state = "cleanup":                                    │
   │                                                                     │
   │ 1. Each live frame detects cleanup state on next heartbeat          │
   │ 2. Frame performs internal cleanup:                                 │
   │    - Release resources                                              │
   │    - Close connections                                              │
   │    - Gracefully shutdown                                            │
   │ 3. Frame requests its own removal from the stack                    │
   │ 4. Ledger processes the removal (see below)                         │
   └─────────────────────────────────────────────────────────────────────┘

RULE 2: FIRST LEDGER HEARTBEAT CLEANS UNSUPERVISED CRASHED FRAMES
   ┌─────────────────────────────────────────────────────────────────────┐
   │ When operation state = "cleanup":                                    │
   │                                                                     │
   │ For each crashed frame with NO live supervisor:                      │
   │ 1. Ledger detects unsupervised crashed frame                        │
   │ 2. Ledger deletes temp resources (files/folders)                    │
   │ 3. Ledger marks frame as "cleanedUp"                                │
   │ 4. (Frame removal happens when caller removes itself)               │
   │                                                                     │
   │ Note: Does NOT remove the frame from stack yet.                     │
   │ The frame remains until the caller is cleaned up.                   │
   └─────────────────────────────────────────────────────────────────────┘

RULE 3: SUPERVISOR HEARTBEAT CLEANS ITS CRASHED CALLS
   ┌─────────────────────────────────────────────────────────────────────┐
   │ When operation state = "cleanup":                                    │
   │                                                                     │
   │ For each crashed frame under this supervisor:                        │
   │ 1. Supervisor heartbeat detects crashed calls                        │
   │ 2. Ledger notifies supervisor via callback with supervisorHandle    │
   │ 3. Supervisor performs internal cleanup                              │
   │ 4. Ledger marks frame as "cleanedUp"                                │
   │ 5. (Frame removal happens when caller removes itself)               │
   │                                                                     │
   │ Note: Supervisor is responsible for cleanup.                        │
   │ The Ledger only marks the frame for removal.                        │
   └─────────────────────────────────────────────────────────────────────┘

RULE 4: REMOVE CRASHED FRAMES WITH DEAD SUPERVISOR
   ┌─────────────────────────────────────────────────────────────────────┐
   │ When operation state = "cleanup" AND:                                │
   │ - Crashed frame has a supervisor AND supervisor is now dead:        │
   │                                                                     │
   │ 1. Any live participant detects this situation                       │
   │ 2. Ledger removes the crashed frame from the stack                   │
   │ 3. No callback needed (supervisor is gone)                           │
   └─────────────────────────────────────────────────────────────────────┘

PHASE 3: FRAME REMOVAL (Stacked Cleanup)
─────────────────────────────────────────────────────────────────────────────
When a live frame requests removal from the stack:

   ┌─────────────────────────────────────────────────────────────────────┐
   │ LEDGER REMOVAL ALGORITHM                                             │
   │                                                                     │
   │ 1. Find the frame being removed (at index i)                        │
   │                                                                     │
   │ 2. Check all frames above it (i+1 to end):                          │
   │    - If any are crashed or cleanedUp, remove them too               │
   │    - Stop when hitting the first non-crashed, non-cleanedUp frame   │
   │                                                                     │
   │ 3. Remove the frame at index i                                      │
   │                                                                     │
   │ Example:                                                             │
   │   Stack: [CLI(active)] → [Bridge(crashed)] → [VSCode(crashed)]      │
   │   When CLI removes itself:                                          │
   │   → Ledger sees [Bridge(crashed), VSCode(crashed)] above            │
   │   → Removes all three frames together                               │
   │   → Stack becomes empty                                             │
   │                                                                     │
   │   Stack: [CLI(active)] → [Bridge(active)] → [VSCode(crashed)]       │
   │   When Bridge removes itself:                                       │
   │   → Ledger sees [VSCode(crashed)] above                             │
   │   → Removes Bridge and VSCode together                              │
   │   → Stack: [CLI(active)]                                            │
   └─────────────────────────────────────────────────────────────────────┘

PHASE 4: OPERATION COMPLETION
─────────────────────────────────────────────────────────────────────────────
When stack becomes empty:

1. Operation transitions to "failed" state
2. Heartbeats continue for 2 more cycles
3. On the 3rd heartbeat after failure:
   - Delete operation file
   - Move to backup location for debugging (optional)
4. Heartbeats stop
```

### Cleanup Responsibility Matrix (Simplified)

| Frame State | Has Supervisor? | Action | Who Does It? |
|-------------|-----------------|--------|-------------|
| **active** | any | Cleanup self on detecting "cleanup" state, remove self from stack | Frame's participant |
| **crashed** | alive | Notify supervisor via callback, mark as "cleanedUp" | Supervisor (via heartbeat) |
| **crashed** | dead | Delete temp resources, mark as "cleanedUp" | Ledger (first heartbeat) |
| **cleanedUp** | any | Remove from stack (when caller removes itself) | Ledger |

### Ledger-Assisted Cleanup

When the Ledger performs heartbeat operations:

```dart
/// Automatic cleanup during heartbeat.
/// Called on every Ledger heartbeat when operation is in "cleanup" state.
Future<void> _performCleanupDuringHeartbeat(LedgerData data) async {
  // RULE 2: Clean up unsupervised crashed frames
  for (final frame in data.stack) {
    if (frame.state == FrameState.crashed && frame.supervisorId == null) {
      // No supervisor, so Ledger cleans up resources
      await _deleteTempResources(
        operationId: data.operationId,
        callId: frame.callId,
      );
      frame.state = FrameState.cleanedUp;
    }
    
    if (frame.state == FrameState.crashed &&
        frame.supervisorId != null &&
        _isSupervisorDead(data, frame.supervisorId!)) {
      // RULE 4: Supervisor died during cleanup
      frame.state = FrameState.cleanedUp;
    }
  }
}

/// When a supervisor's heartbeat runs.
/// Notifies supervisor of crashed calls in its domain.
Future<void> _performSupervisorHeartbeat(
  String supervisorId,
  LedgerData data,
) async {
  // Update supervisor heartbeat
  data.supervisorHeartbeats[supervisorId] = SupervisorHeartbeat(
    supervisorId: supervisorId,
    pid: getCurrentPid(),
    lastHeartbeat: DateTime.now(),
    status: SupervisorStatus.alive,
  );
  
  // RULE 3: Check for crashed calls under this supervisor
  if (data.state == OperationState.cleanup) {
    for (final frame in data.stack) {
      if (frame.state == FrameState.crashed &&
          frame.supervisorId == supervisorId) {
        // Notify supervisor of crashed call
        await _onCallCrashed?.call(
          frame.supervisorHandle!,
          CrashedCallInfo(
            operationId: data.operationId,
            callId: frame.callId,
            participantId: frame.participantId,
            staleFor: DateTime.now().difference(frame.lastHeartbeat),
            previousState: FrameState.active,
          ),
        );
        
        // Mark as cleaned up (supervisor has been notified)
        frame.state = FrameState.cleanedUp;
      }
    }
  }
}
```

### Example: Bridge Crashes During Copilot Call

```
INITIAL STATE:
  Stack: [CLI:cli-main] → [Bridge:bridge-process] → [VSCode:vscode-copilot]
  All frames: active, operation: running

T+0: Bridge crashes (stops heartbeat)

T+2: CLI detects Bridge is stale
  - CLI sets operation.state = aborted
  - CLI marks Bridge frame as "crashed"
  
T+3: VSCode detects abort on heartbeat
  - VSCode marks own frame as "aborted"
  
T+3.1: CLI marks own frame as "aborted"

T+4: All non-crashed frames are aborted
  - Operation transitions to "cleanup" state
  
T+5: Cleanup starts from last frame (VSCode)
  - VSCode has a supervisor (VSCode Extension)
  - Supervisor is alive (VSCode Extension process is running)
  - Supervisor receives callback with supervisorHandle
  - Supervisor cleans up internal state (webview, etc.)
  - Supervisor marks VSCode frame as "cleanedUp"
  - VSCode frame removed from stack
  
T+6: Next frame to clean: Bridge (crashed)
  - Bridge had a supervisor (Bridge process) - but it's dead
  - Caller (CLI) is alive
  - CLI cleans up Bridge frame:
    - Ledger deletes Bridge's temp resources
    - CLI removes Bridge frame from stack
    
T+7: Last frame: CLI
  - CLI cleans up itself
  - CLI marks own frame as "cleanedUp"  
  - CLI removes own frame from stack
  
T+8: Stack is empty
  - Operation marked as "failed"
  - Final ledger archived to trail
```

---

## Part 2: Stack Frame with Supervisor Association

### Enhanced Stack Frame

Each stack frame now includes optional supervisor information:

```dart
class StackFrame {
  /// Unique participant ID.
  final String participantId;
  
  /// Call ID within this operation.
  final String callId;
  
  /// Process ID of the participant.
  final int pid;
  
  /// When this frame was created.
  final DateTime startTime;
  
  /// Last heartbeat from this participant.
  DateTime lastHeartbeat;
  
  /// Current state of this frame.
  FrameState state;
  
  /// Optional: Which supervisor oversees this call.
  /// If null, this is an unsupervised call.
  final String? supervisorId;
  
  /// Optional: Opaque handle for the supervisor's internal tracking.
  /// Passed by the call when adding the frame to the operation.
  final String? supervisorHandle;
}
```

### JSON Structure

```json
{
  "operationId": "op_123",
  "state": "running",
  "lastHeartbeat": "2026-01-20T10:30:00Z",
  "aborted": false,
  
  "stack": [
    {
      "participantId": "cli",
      "callId": "cli-main",
      "pid": 1000,
      "startTime": "2026-01-20T10:30:00Z",
      "lastHeartbeat": "2026-01-20T10:30:00Z",
      "state": "active",
      "supervisorId": null,
      "supervisorHandle": null
    },
    {
      "participantId": "bridge",
      "callId": "bridge-process",
      "pid": 1001,
      "startTime": "2026-01-20T10:30:01Z",
      "lastHeartbeat": "2026-01-20T10:30:05Z",
      "state": "active",
      "supervisorId": "bridge",
      "supervisorHandle": "channel_42"
    },
    {
      "participantId": "vscode",
      "callId": "vscode-copilot",
      "pid": 1002,
      "startTime": "2026-01-20T10:30:02Z",
      "lastHeartbeat": "2026-01-20T10:30:05Z",
      "state": "active",
      "supervisorId": "vscode-extension",
      "supervisorHandle": "webview_panel_7"
    }
  ],
  
  "supervisorHeartbeats": {
    "bridge": {
      "supervisorId": "bridge",
      "pid": 1001,
      "lastHeartbeat": "2026-01-20T10:30:05Z",
      "status": "alive"
    },
    "vscode-extension": {
      "supervisorId": "vscode-extension",
      "pid": 1002,
      "lastHeartbeat": "2026-01-20T10:30:05Z",
      "status": "alive"
    }
  }
}
```

---

## Part 3a: Failure Notification in Dart Code

### Problem

When a participant makes a call and waits for the result, it needs to know if the callee crashed. Since the operation state is persisted in a file, the caller (a Dart program) must somehow detect when its callee fails.

### Solution: Stream-Based State Notification

The `Operation` class provides stream-based notifications so callers can react to operation failures without polling:

```dart
/// Operation state change event.
class OperationStateEvent {
  /// The new state.
  final OperationState newState;
  
  /// The previous state.
  final OperationState previousState;
  
  /// When this change occurred.
  final DateTime timestamp;
  
  /// Which participant detected this change.
  final String detectedBy;
  
  OperationStateEvent({
    required this.newState,
    required this.previousState,
    required this.timestamp,
    required this.detectedBy,
  });
}

/// Enhanced Operation API with state notifications.
class Operation {
  /// Stream of operation state changes.
  /// 
  /// Emits:
  /// - running → cleanup (failure detected)
  /// - cleanup → failed (operation cleanup complete)
  /// - running → completed (success)
  /// 
  /// Listen to this stream to detect when a callee fails:
  /// ```dart
  /// operation.stateChanges.listen((event) {
  ///   if (event.newState == OperationState.cleanup) {
  ///     // Callee crashed, abort and cleanup
  ///   } else if (event.newState == OperationState.failed) {
  ///     // Operation failed and cleanup is complete
  ///   }
  /// });
  /// ```
  Stream<OperationStateEvent> get stateChanges {
    return _stateController.stream;
  }
  
  /// Current operation state.
  OperationState get state => _data.state;
  
  /// Wait for the operation to reach a terminal state.
  /// 
  /// Returns the terminal state (failed or completed).
  /// Completes when no more frames remain in the operation.
  /// 
  /// Useful for callers that spawn a call and want to wait for completion:
  /// ```dart
  /// Future<Result> callAndWait() async {
  ///   final operation = startOperation(...);
  ///   final state = await operation.waitForTerminal();
  ///   
  ///   if (state == OperationState.failed) {
  ///     // Failure detected, operation cleaned up
  ///     return Result.failure();
  ///   } else {
  ///     // Completed successfully
  ///     return Result.success();
  ///   }
  /// }
  /// ```
  Future<OperationState> waitForTerminal() async {
    return _terminalCompleter.future;
  }
  
  /// Wait for cleanup to start.
  /// 
  /// Completes when operation transitions to cleanup state.
  /// Useful for abandoning processing and cleaning up early.
  Future<void> waitForCleanup() async {
    if (state == OperationState.cleanup ||
        state == OperationState.failed ||
        state == OperationState.completed) {
      return;
    }
    
    return _cleanupCompleter.future;
  }
}
```

### Caller Pattern: Safe Wait with Timeout

When a participant calls another and wants to wait for the result:

```dart
/// Safe pattern for calling another participant and waiting for result.
class SafeCallPattern {
  /// Call another participant and wait for result or timeout.
  /// 
  /// [call] - The async call to make
  /// [onSuccess] - Called when call completes normally
  /// [onTimeout] - Called if call takes too long
  /// [onCrash] - Called if callee crashes (detected via operation state)
  /// 
  /// Returns the result of [onSuccess], [onTimeout], or [onCrash].
  static Future<T> callWithFailureDetection<T>({
    required Future<T> Function() call,
    required T Function() onSuccess,
    required T Function() onTimeout,
    required T Function(OperationState reason) onCrash,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final operation = Ledger.instance.currentOperation;
    
    // Listen for operation failure in parallel with the call
    final failureDetected = operation.waitForCleanup();
    
    // Race three things:
    // 1. The actual call
    // 2. Operation cleanup (failure detected)
    // 3. Timeout
    try {
      return await Future.any([
        call().then((_) => _CallResult<T>.success(onSuccess())),
        failureDetected.then(
          (_) => _CallResult<T>.crash(onCrash(OperationState.cleanup)),
        ),
        Future.delayed(timeout).then(
          (_) => _CallResult<T>.timeout(onTimeout()),
        ),
      ]).then((result) => result.value);
    } catch (e) {
      // Handle any unexpected errors
      return onCrash(operation.state);
    }
  }
  
  static Future<T> callWithStateMonitoring<T>({
    required Future<T> Function() call,
    required Operation operation,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    // Option 2: Monitor state changes actively
    OperationState? failureState;
    
    late StreamSubscription subscription;
    subscription = operation.stateChanges.listen((event) {
      if (event.newState == OperationState.cleanup) {
        failureState = OperationState.cleanup;
      } else if (event.newState == OperationState.failed) {
        failureState = OperationState.failed;
      }
    });
    
    try {
      return await call().timeout(timeout);
    } on TimeoutException {
      throw CallTimeoutException('Call exceeded $timeout');
    } finally {
      await subscription.cancel();
    }
  }
}

class _CallResult<T> {
  final T value;
  final _ResultType type;
  
  _CallResult._(this.value, this.type);
  
  factory _CallResult.success(T value) => _CallResult._(value, _ResultType.success);
  factory _CallResult.crash(T value) => _CallResult._(value, _ResultType.crash);
  factory _CallResult.timeout(T value) => _CallResult._(value, _ResultType.timeout);
}

enum _ResultType { success, crash, timeout }

class CallTimeoutException implements Exception {
  final String message;
  CallTimeoutException(this.message);
  
  @override
  String toString() => 'CallTimeoutException: $message';
}
```

### Example: Bridge Calls VSCode and Waits

```dart
/// Bridge supervisor making a call to VSCode and handling failure.
Future<void> bridgeCallsVSCode() async {
  final operation = Ledger.instance.currentOperation!;
  
  final result = await SafeCallPattern.callWithFailureDetection<String>(
    call: () async {
      // Make the actual call to VSCode
      return await _vsCodeBridge.sendRequest('get-completion');
    },
    
    onSuccess: () {
      print('VSCode completed successfully');
      return 'success';
    },
    
    onTimeout: () {
      print('VSCode call timed out');
      return 'timeout';
    },
    
    onCrash: (reason) {
      print('VSCode crashed (reason: $reason)');
      
      // Cleanup any VSCode-related resources
      _vsCodeBridge.cleanup();
      
      // Maybe retry with another instance
      return 'crashed_and_handled';
    },
    
    timeout: Duration(seconds: 30),
  );
  
  print('Call result: $result');
}
```

### Alternative: Manual State Polling

For simpler cases or when using reactive patterns:

```dart
/// Manual polling approach for failure detection.
Future<bool> detectCalleeCrash(Operation operation) async {
  // Poll operation state every 1 second
  const pollInterval = Duration(milliseconds: 500);
  
  while (operation.state == OperationState.running) {
    await Future.delayed(pollInterval);
  }
  
  // Check final state
  return operation.state == OperationState.cleanup ||
      operation.state == OperationState.failed;
}

/// With timeout safety net
Future<T?> callWithSafety<T>({
  required Future<T> Function() call,
  required Duration timeout,
  required Operation operation,
}) async {
  try {
    // Start the call
    final callFuture = call();
    
    // Monitor for failure in parallel
    final failureCheck = operation
        .waitForCleanup()
        .timeout(timeout)
        .then((_) => throw CalleeFailedException('Callee crashed'));
    
    // Return first to complete
    return await Future.any([callFuture, failureCheck]);
  } on CalleeFailedException {
    // Handle failure
    return null;
  } on TimeoutException {
    // Handle timeout
    return null;
  }
}

class CalleeFailedException implements Exception {
  final String message;
  CalleeFailedException(this.message);
  
  @override
  String toString() => 'CalleeFailedException: $message';
}
```

### Best Practice Checklist

When writing code that calls another participant:

- [ ] **Always use a timeout** - Don't wait indefinitely
- [ ] **Listen to operation state changes** - Detect failures quickly
- [ ] **Handle the cleanup state** - Respond when callee enters cleanup
- [ ] **Clean up resources** - When call fails, clean up your own state
- [ ] **Avoid polling** - Use streams/futures instead of periodic checks
- [ ] **Log failures** - Track why calls failed for debugging
- [ ] **Test failure paths** - Use the concurrent scenario framework


### Overview

The Supervisor API is a **Dart-only, in-memory API** that supervisors use to:
1. Create and own the Ledger instance for their isolate
2. Register callbacks for call lifecycle events
3. Track supervised calls (in-memory, not in the operation file)

### Key Principle: One Ledger Per Isolate

```dart
/// A Dart isolate can have exactly ONE Ledger instance.
/// 
/// Creation options:
/// 1. Supervisor creates it via Ledger.initSupervisorLedger()
/// 2. First call creates it implicitly via Ledger.instance
/// 
/// If a supervisor creates the Ledger, it receives callbacks
/// for all call lifecycle events within that isolate.
```

### Supervisor Ledger Initialization

```dart
/// Static configuration for supervisor-mode Ledger.
class Ledger {
  static Ledger? _instance;
  
  /// Get the singleton Ledger instance.
  /// 
  /// If not initialized, creates an implicit (non-supervisor) Ledger.
  static Ledger get instance {
    _instance ??= Ledger._implicit();
    return _instance!;
  }
  
  /// Initialize the Ledger in supervisor mode.
  /// 
  /// MUST be called before any other Ledger access.
  /// Throws if Ledger was already initialized.
  /// 
  /// [supervisorId] - Unique identifier for this supervisor.
  /// [ledgerPath] - Path to the ledger directory.
  /// [heartbeatInterval] - How often to send heartbeats.
  /// [stalenessThreshold] - When to consider a participant stale.
  /// [onCallCrashed] - Called when a supervised call crashes.
  /// [onCallStarted] - Called when a supervised call starts.
  /// [onCallEnded] - Called when a supervised call ends normally.
  /// [onError] - Called on heartbeat errors.
  static void initSupervisorLedger({
    required String supervisorId,
    required String ledgerPath,
    Duration heartbeatInterval = const Duration(milliseconds: 4500),
    Duration stalenessThreshold = const Duration(seconds: 10),
    int jitterMs = 500,
    CrashedCallCallback? onCallCrashed,
    CallLifecycleCallback? onCallStarted,
    CallLifecycleCallback? onCallEnded,
    HeartbeatErrorCallback? onError,
    HeartbeatSuccessCallback? onSuccess,
  }) {
    if (_instance != null) {
      throw StateError('Ledger already initialized. '
          'initSupervisorLedger must be called before any Ledger access.');
    }
    
    _instance = Ledger._supervisor(
      supervisorId: supervisorId,
      ledgerPath: ledgerPath,
      heartbeatInterval: heartbeatInterval,
      stalenessThreshold: stalenessThreshold,
      jitterMs: jitterMs,
      onCallCrashed: onCallCrashed,
      onCallStarted: onCallStarted,
      onCallEnded: onCallEnded,
      onError: onError,
      onSuccess: onSuccess,
    );
  }
  
  /// Check if a supervisor is present for this Ledger.
  bool get hasSupervisor => _supervisorId != null;
  
  /// Get the supervisor ID if this is a supervisor Ledger.
  String? get supervisorId => _supervisorId;
}
```

### Callback Types

```dart
/// Called when a supervised call crashes (detected via stale heartbeat).
/// 
/// [supervisorHandle] - The handle passed when the call was started.
/// [callInfo] - Information about the crashed call.
typedef CrashedCallCallback = Future<void> Function(
  String supervisorHandle,
  CrashedCallInfo callInfo,
);

/// Information about a crashed call.
class CrashedCallInfo {
  /// The operation ID.
  final String operationId;
  
  /// The call ID within the operation.
  final String callId;
  
  /// The participant ID.
  final String participantId;
  
  /// How long the heartbeat was stale.
  final Duration staleFor;
  
  /// The frame state when crash was detected.
  final FrameState previousState;
}

/// Called when a supervised call starts or ends.
/// 
/// [supervisorHandle] - The handle passed when the call was started.
/// [callInfo] - Information about the call.
typedef CallLifecycleCallback = Future<void> Function(
  String supervisorHandle,
  CallInfo callInfo,
);

/// Information about a call lifecycle event.
class CallInfo {
  /// The operation ID.
  final String operationId;
  
  /// The call ID within the operation.
  final String callId;
  
  /// The participant ID.
  final String participantId;
  
  /// When the event occurred.
  final DateTime timestamp;
}
```

### Supervised Call Registration

When a call adds its frame to an operation, it can specify supervisor info:

```dart
extension SupervisedCallExtension on Operation {
  /// Start call execution with supervisor tracking.
  /// 
  /// [callId] - The call identifier.
  /// [supervisorHandle] - Opaque handle for the supervisor's use.
  ///   This is passed to supervisor callbacks on crash/start/end.
  /// 
  /// If the Ledger has a supervisor, the supervisor's [supervisorId]
  /// is automatically associated with this frame.
  Future<void> startCallExecution({
    required String callId,
    String? supervisorHandle,
  }) async {
    final ledger = Ledger.instance;
    
    await _ledger._modifyOperation(
      operationId: operationId,
      elapsedFormatted: elapsedFormatted,
      updater: (data) {
        final frame = StackFrame(
          participantId: participantId,
          callId: callId,
          pid: pid,
          startTime: DateTime.now(),
          lastHeartbeat: DateTime.now(),
          state: FrameState.active,
          supervisorId: ledger.supervisorId,
          supervisorHandle: supervisorHandle,
        );
        data.stack.add(frame);
        data.lastHeartbeat = DateTime.now();
        return data;
      },
    );
    
    // Notify supervisor of call start
    if (ledger.hasSupervisor && supervisorHandle != null) {
      ledger._onCallStarted?.call(supervisorHandle, CallInfo(
        operationId: operationId,
        callId: callId,
        participantId: participantId,
        timestamp: DateTime.now(),
      ));
    }
  }
}
```

### In-Memory Supervised Call Registry

The supervisor tracks calls in memory (not in the file):

```dart
/// In-memory registry of supervised calls.
/// 
/// This is maintained by the Supervisor API, NOT in the operation file.
/// It allows the supervisor to quickly look up call state by handle.
class SupervisedCallRegistry {
  final Map<String, SupervisedCallEntry> _byHandle = {};
  final Map<String, SupervisedCallEntry> _byCallId = {};
  
  /// Register a new supervised call.
  void register({
    required String supervisorHandle,
    required String operationId,
    required String callId,
    required String participantId,
  }) {
    final entry = SupervisedCallEntry(
      supervisorHandle: supervisorHandle,
      operationId: operationId,
      callId: callId,
      participantId: participantId,
      startTime: DateTime.now(),
    );
    _byHandle[supervisorHandle] = entry;
    _byCallId['$operationId:$callId'] = entry;
  }
  
  /// Unregister a call (on normal completion).
  void unregister(String supervisorHandle) {
    final entry = _byHandle.remove(supervisorHandle);
    if (entry != null) {
      _byCallId.remove('${entry.operationId}:${entry.callId}');
    }
  }
  
  /// Get call info by handle.
  SupervisedCallEntry? getByHandle(String handle) => _byHandle[handle];
  
  /// Get all active calls for an operation.
  List<SupervisedCallEntry> getForOperation(String operationId) {
    return _byHandle.values
        .where((e) => e.operationId == operationId)
        .toList();
  }
}

class SupervisedCallEntry {
  final String supervisorHandle;
  final String operationId;
  final String callId;
  final String participantId;
  final DateTime startTime;
  
  SupervisedCallEntry({
    required this.supervisorHandle,
    required this.operationId,
    required this.callId,
    required this.participantId,
    required this.startTime,
  });
}
```

---

## Part 4: Supervisor Heartbeats in Operation File

### Simplified Supervisor Heartbeat

The operation file tracks supervisor heartbeats to distinguish between:
- "A call under this supervisor crashed" (call heartbeat stale, supervisor heartbeat fresh)
- "The supervisor itself died" (supervisor heartbeat stale)

### Simplified Supervisor Heartbeat

The operation file tracks supervisor heartbeats to distinguish between:
- "A call under this supervisor crashed" (call heartbeat stale, supervisor heartbeat fresh)
- "The supervisor itself died" (supervisor heartbeat stale)

```dart
/// Supervisor heartbeat in the operation file.
class SupervisorHeartbeat {
  /// Unique supervisor ID.
  final String supervisorId;
  
  /// Process ID of the supervisor.
  final int pid;
  
  /// Last heartbeat timestamp.
  DateTime lastHeartbeat;
  
  /// Supervisor status.
  SupervisorStatus status;
}

enum SupervisorStatus {
  /// Supervisor is alive and healthy.
  alive,
  
  /// Supervisor is detected as dead (stale heartbeat).
  dead,
}
```

### JSON Structure (Simplified)

```json
{
  "supervisorHeartbeats": {
    "bridge": {
      "supervisorId": "bridge",
      "pid": 12345,
      "lastHeartbeat": "2026-01-20T10:30:00Z",
      "status": "alive"
    },
    "vscode-extension": {
      "supervisorId": "vscode-extension",
      "pid": 23456,
      "lastHeartbeat": "2026-01-20T10:30:00Z",
      "status": "alive"
    }
  }
}
```

### Supervisor Heartbeat Update

When a supervisor's Ledger performs a heartbeat:

```dart
Future<void> _updateSupervisorHeartbeat(LedgerData data) async {
  if (_supervisorId == null) return;
  
  data.supervisorHeartbeats[_supervisorId!] = SupervisorHeartbeat(
    supervisorId: _supervisorId!,
    pid: pid,
    lastHeartbeat: DateTime.now(),
    status: SupervisorStatus.alive,
  );
}
```

### Detecting Supervisor Death

During heartbeat checks:

```dart
void _checkSupervisorHealth(LedgerData data) {
  final now = DateTime.now();
  
  for (final entry in data.supervisorHeartbeats.entries) {
    final supervisor = entry.value;
    final age = now.difference(supervisor.lastHeartbeat);
    
    if (age > _stalenessThreshold && 
        supervisor.status == SupervisorStatus.alive) {
      // Supervisor has died
      supervisor.status = SupervisorStatus.dead;
      
      // Mark all frames under this supervisor as requiring cleanup
      for (final frame in data.stack) {
        if (frame.supervisorId == supervisor.supervisorId &&
            frame.state == FrameState.active) {
          frame.state = FrameState.crashed;
        }
      }
    }
  }
}
```

---

## Part 5: Heartbeat Continuation

### Heartbeat Lifecycle

Heartbeats continue automatically throughout the operation lifecycle:

```dart
class Operation {
  /// Start periodic heartbeats for this operation.
  /// 
  /// Heartbeats continue until operation reaches terminal state:
  /// - OperationState.completed (successful completion)
  /// - OperationState.failed (cleanup finished)
  /// 
  /// Cannot be manually stopped. Use operation state to detect terminal.
  void startHeartbeat({
    Duration interval = const Duration(milliseconds: 1500),
    int jitterMs = 200,
  }) {
    _heartbeatTimer = Timer.periodic(interval + _randomJitter(), (_) {
      _performHeartbeat();
    });
  }
  
  /// Internal heartbeat logic.
  /// 
  /// Continues running until one of these conditions:
  /// 1. Operation reaches OperationState.failed or OperationState.completed
  /// 2. Heartbeat counter reaches max (cleanup completion phase)
  /// 3. Process receives SIGTERM/SIGKILL
  Future<void> _performHeartbeat() async {
    if (_heartbeatsSinceTerminal >= 2) {
      // Operation has been failed for 2 heartbeats
      // Next heartbeat will clean up the operation file
      _cleanupOperationFile();
      _heartbeatTimer.cancel();
      return;
    }
    
    // ... standard heartbeat logic ...
    
    if (state == OperationState.failed ||
        state == OperationState.completed) {
      _heartbeatsSinceTerminal++;
    }
  }
}
```

### Heartbeat Behavior During Cleanup

When operation transitions to cleanup state, heartbeats:

1. **Continue normal schedule** - No pause or speed change
2. **Perform cleanup actions** (via rules in cleanup mechanism)
3. **Check for terminal state** - When stack becomes empty
4. **Transition to failed** - Set `state = OperationState.failed`
5. **Continue for 2 more cycles** - Allow other participants to notice
6. **Delete operation file** - On the 3rd cycle after becoming terminal

### Important Properties

- **No manual stop**: Cannot stop heartbeats programmatically
- **Self-terminating**: Heartbeat loop exits only when operation file is deleted
- **State-driven**: Behavior changes based on operation state
- **Automatic cleanup**: File cleanup is automatic after 2 cycles

---

## Part 6: Supervisor Orchestrator

### Overview

The Supervisor Orchestrator is a daemon that:
1. Gets started by the first supervisor to come online
2. Manages supervisor lifecycle (start, restart, shutdown)
3. Monitors supervisor heartbeats in the supervisors file
4. Supports supervisor dependencies

### File Structure

```
{ledgerPath}/
├── {groupId}.orchestrator.json    # Orchestrator state
├── {groupId}.supervisors.json     # Registered supervisors
└── operations/
    └── {operationId}.json         # Operation files
```

### Orchestration Group

```dart
/// The orchestrator state file: {groupId}.orchestrator.json
class OrchestrationGroup {
  /// Unique identifier for this orchestration group.
  final String orchestrationGroupId;
  
  /// Process ID of the orchestrator daemon.
  int? orchestratorPid;
  
  /// Orchestrator's heartbeat timestamp.
  DateTime? orchestratorHeartbeat;
  
  /// Current state of the orchestrator.
  OrchestratorState state;
  
  /// Heartbeat interval in milliseconds.
  final int heartbeatIntervalMs;
  
  /// Staleness threshold in milliseconds.
  final int stalenessThresholdMs;
}

enum OrchestratorState {
  /// Orchestrator is starting up.
  starting,
  
  /// Orchestrator is running normally.
  running,
  
  /// Orchestrator is shutting down.
  shuttingDown,
  
  /// Orchestrator has stopped.
  stopped,
}
```

### Registered Supervisors File

```dart
/// The supervisors file: {groupId}.supervisors.json
class SupervisorsRegistry {
  /// All registered supervisors.
  Map<String, RegisteredSupervisor> supervisors;
}

class RegisteredSupervisor {
  /// Unique supervisor ID.
  final String supervisorId;
  
  /// How to start this supervisor (null = not restartable).
  final SupervisorStartInfo? startInfo;
  
  /// Whether the orchestrator can restart this supervisor.
  final bool restartable;
  
  /// Current state.
  SupervisorState state;
  
  /// Process ID when running.
  int? pid;
  
  /// Last heartbeat timestamp.
  DateTime? lastHeartbeat;
  
  /// Supervisors that this supervisor depends on.
  /// These must be started before this supervisor.
  List<String> dependencies;
  
  /// Restart attempt counter (resets after successful run).
  int restartAttempts;
  
  /// When the last restart attempt occurred.
  DateTime? lastRestartAttempt;
}

enum SupervisorState {
  /// Registered but not yet started.
  registered,
  
  /// Waiting for dependencies to be ready.
  waitingForDependencies,
  
  /// Running and healthy.
  running,
  
  /// Detected as failed (stale heartbeat).
  failed,
  
  /// Restart scheduled (waiting for backoff).
  restartScheduled,
  
  /// Permanently failed (max restarts exceeded or not restartable).
  dead,
  
  /// Shutting down.
  shuttingDown,
  
  /// Stopped.
  stopped,
}

class SupervisorStartInfo {
  /// Command to execute.
  final String command;
  
  /// Command arguments.
  final List<String> args;
  
  /// Working directory.
  final String workingDirectory;
  
  /// Environment variables.
  final Map<String, String> environment;
  
  /// Restart policy.
  final RestartPolicy restartPolicy;
}

class RestartPolicy {
  /// Maximum restart attempts before marking as dead.
  final int maxAttempts;
  
  /// Backoff intervals in milliseconds: [0, 1000, 5000, 15000, 60000]
  /// Uses last value if attempts exceed list length.
  final List<int> backoffIntervalsMs;
  
  /// Reset restart counter after this duration of healthy running.
  final Duration resetAfter;
  
  static const defaultPolicy = RestartPolicy(
    maxAttempts: 5,
    backoffIntervalsMs: [0, 1000, 5000, 15000, 60000],
    resetAfter: Duration(minutes: 5),
  );
}
```

### JSON Structure: orchestrator.json

```json
{
  "orchestrationGroupId": "tom-workspace",
  "orchestratorPid": 5000,
  "orchestratorHeartbeat": "2026-01-20T10:30:00Z",
  "state": "running",
  "heartbeatIntervalMs": 2000,
  "stalenessThresholdMs": 10000
}
```

### JSON Structure: supervisors.json

```json
{
  "supervisors": {
    "bridge": {
      "supervisorId": "bridge",
      "startInfo": {
        "command": "/usr/local/bin/tom-bridge",
        "args": ["--workspace", "/home/user/project"],
        "workingDirectory": "/home/user/project",
        "environment": {},
        "restartPolicy": {
          "maxAttempts": 5,
          "backoffIntervalsMs": [0, 1000, 5000, 15000, 60000],
          "resetAfterMs": 300000
        }
      },
      "restartable": true,
      "state": "running",
      "pid": 12345,
      "lastHeartbeat": "2026-01-20T10:30:00Z",
      "dependencies": [],
      "restartAttempts": 0,
      "lastRestartAttempt": null
    },
    "vscode-extension": {
      "supervisorId": "vscode-extension",
      "startInfo": null,
      "restartable": false,
      "state": "running",
      "pid": 23456,
      "lastHeartbeat": "2026-01-20T10:30:00Z",
      "dependencies": ["bridge"],
      "restartAttempts": 0,
      "lastRestartAttempt": null
    }
  }
}
```

### Orchestrator API

```dart
/// API for supervisors to interact with the orchestrator.
class Orchestrator {
  /// Path to the orchestration files.
  final String ledgerPath;
  
  /// Orchestration group ID.
  final String groupId;
  
  Orchestrator._({required this.ledgerPath, required this.groupId});
  
  /// Connect to or start the orchestrator.
  /// 
  /// If orchestrator.json doesn't exist, creates it and starts orchestrator.
  /// If orchestrator exists but heartbeat is stale, takes over.
  /// If orchestrator is healthy, connects to it.
  static Future<Orchestrator> connect({
    required String ledgerPath,
    required String groupId,
  });
  
  /// Register this supervisor with the orchestrator.
  /// 
  /// [supervisorId] - Unique identifier.
  /// [startInfo] - How to start this supervisor (null = not restartable).
  /// [dependencies] - Supervisors that must be running first.
  Future<void> registerSupervisor({
    required String supervisorId,
    SupervisorStartInfo? startInfo,
    List<String> dependencies = const [],
  });
  
  /// Request the orchestrator to start a dependency supervisor.
  /// 
  /// This adds the dependency to the supervisors file with the given
  /// start info. The orchestrator will start it on the next heartbeat.
  Future<void> requestSupervisorStart({
    required String supervisorId,
    required SupervisorStartInfo startInfo,
    List<String> dependencies = const [],
  });
  
  /// Update heartbeat for this supervisor.
  Future<void> heartbeat(String supervisorId);
  
  /// Get the current state of a supervisor.
  Future<SupervisorState?> getSupervisorState(String supervisorId);
  
  /// Check if a dependency is ready.
  Future<bool> isDependencyReady(String supervisorId);
  
  /// Wait for dependencies to be ready.
  Future<void> waitForDependencies(List<String> dependencies, {
    Duration timeout = const Duration(seconds: 30),
  });
  
  /// Request graceful shutdown.
  Future<void> requestShutdown(String supervisorId);
  
  /// Optional callback for external alerting.
  ExternalAlertCallback? onExternalAlert;
}

/// Callback for external alerting (webhooks, etc.)
typedef ExternalAlertCallback = Future<void> Function(
  OrchestratorAlert alert,
);

class OrchestratorAlert {
  final AlertType type;
  final String supervisorId;
  final String message;
  final DateTime timestamp;
}

enum AlertType {
  supervisorFailed,
  supervisorRestarted,
  supervisorDead,
  orchestratorTakeover,
}
```

### Orchestrator Startup Flow

```
┌──────────────────────────────────────────────────────────────────────────┐
│                     ORCHESTRATOR STARTUP FLOW                            │
└──────────────────────────────────────────────────────────────────────────┘

1. SUPERVISOR A WANTS TO START
   │
   ├─► Check {groupId}.orchestrator.json exists?
   │   │
   │   ├─► NO: Create new orchestration group
   │   │       - Create orchestrator.json with self as orchestrator
   │   │       - Create supervisors.json (empty)
   │   │       - Start orchestrator heartbeat loop
   │   │       - Register self in supervisors.json
   │   │
   │   └─► YES: Check orchestrator heartbeat
   │       │
   │       ├─► FRESH: Orchestrator is alive
   │       │   └─► Just register self in supervisors.json
   │       │
   │       └─► STALE: Orchestrator has died
   │           │
   │           └─► Check supervisors.json for existing supervisors
   │               │
   │               ├─► All supervisors have stale heartbeats?
   │               │   └─► Fresh start: clear supervisors.json
   │               │
   │               └─► Some supervisors alive?
   │                   └─► Preserve their registrations
   │                       Take over as new orchestrator
   │
   └─► 2. REGISTER SELF
       │
       ├─► Add entry to supervisors.json
       ├─► Set state = "running"
       ├─► Start supervisor heartbeat
       │
       └─► 3. START ORCHESTRATOR LOOP (if orchestrator)
           │
           └─► Every heartbeatInterval:
               ├─► Update orchestratorHeartbeat
               ├─► Check all supervisor heartbeats
               ├─► Detect failures, trigger restarts
               └─► Process pending start requests
```

### Orchestrator Heartbeat Loop

```dart
Future<void> _orchestratorLoop() async {
  while (_running) {
    await _updateOrchestratorHeartbeat();
    
    final supervisors = await _readSupervisors();
    
    for (final supervisor in supervisors.values) {
      await _checkSupervisor(supervisor);
    }
    
    await _processPendingStartRequests();
    
    await Future.delayed(_heartbeatInterval);
  }
}

Future<void> _checkSupervisor(RegisteredSupervisor supervisor) async {
  final now = DateTime.now();
  
  switch (supervisor.state) {
    case SupervisorState.running:
      // Check for stale heartbeat
      if (supervisor.lastHeartbeat != null) {
        final age = now.difference(supervisor.lastHeartbeat!);
        if (age > _stalenessThreshold) {
          await _handleSupervisorFailure(supervisor);
        }
      }
      
      // Check if restart counter should reset
      if (supervisor.restartAttempts > 0 &&
          supervisor.lastRestartAttempt != null) {
        final sinceRestart = now.difference(supervisor.lastRestartAttempt!);
        if (sinceRestart > supervisor.startInfo!.restartPolicy.resetAfter) {
          supervisor.restartAttempts = 0;
        }
      }
      break;
      
    case SupervisorState.failed:
    case SupervisorState.restartScheduled:
      if (supervisor.restartable && supervisor.startInfo != null) {
        await _attemptRestart(supervisor);
      } else {
        supervisor.state = SupervisorState.dead;
        _onExternalAlert?.call(OrchestratorAlert(
          type: AlertType.supervisorDead,
          supervisorId: supervisor.supervisorId,
          message: 'Supervisor cannot be restarted',
          timestamp: now,
        ));
      }
      break;
      
    case SupervisorState.waitingForDependencies:
      if (await _areDependenciesReady(supervisor.dependencies)) {
        await _startSupervisor(supervisor);
      }
      break;
      
    default:
      break;
  }
}

Future<void> _handleSupervisorFailure(RegisteredSupervisor supervisor) async {
  supervisor.state = SupervisorState.failed;
  
  _onExternalAlert?.call(OrchestratorAlert(
    type: AlertType.supervisorFailed,
    supervisorId: supervisor.supervisorId,
    message: 'Supervisor heartbeat stale',
    timestamp: DateTime.now(),
  ));
  
  await _writeSupervisors();
}

Future<void> _attemptRestart(RegisteredSupervisor supervisor) async {
  final policy = supervisor.startInfo!.restartPolicy;
  
  if (supervisor.restartAttempts >= policy.maxAttempts) {
    supervisor.state = SupervisorState.dead;
    _onExternalAlert?.call(OrchestratorAlert(
      type: AlertType.supervisorDead,
      supervisorId: supervisor.supervisorId,
      message: 'Max restart attempts exceeded',
      timestamp: DateTime.now(),
    ));
    await _writeSupervisors();
    return;
  }
  
  // Calculate backoff
  final backoffIndex = supervisor.restartAttempts.clamp(
    0, 
    policy.backoffIntervalsMs.length - 1,
  );
  final backoffMs = policy.backoffIntervalsMs[backoffIndex];
  
  final timeSinceFailure = DateTime.now().difference(
    supervisor.lastRestartAttempt ?? DateTime.now(),
  );
  
  if (timeSinceFailure.inMilliseconds < backoffMs) {
    supervisor.state = SupervisorState.restartScheduled;
    return;
  }
  
  // Attempt restart
  supervisor.restartAttempts++;
  supervisor.lastRestartAttempt = DateTime.now();
  
  await _startSupervisor(supervisor);
  
  _onExternalAlert?.call(OrchestratorAlert(
    type: AlertType.supervisorRestarted,
    supervisorId: supervisor.supervisorId,
    message: 'Restart attempt ${supervisor.restartAttempts}',
    timestamp: DateTime.now(),
  ));
}

Future<void> _startSupervisor(RegisteredSupervisor supervisor) async {
  if (supervisor.startInfo == null) return;
  
  final info = supervisor.startInfo!;
  
  try {
    final process = await Process.start(
      info.command,
      info.args,
      workingDirectory: info.workingDirectory,
      environment: info.environment,
    );
    
    supervisor.pid = process.pid;
    supervisor.state = SupervisorState.running;
    supervisor.lastHeartbeat = DateTime.now();
    
    await _writeSupervisors();
  } catch (e) {
    supervisor.state = SupervisorState.failed;
    await _writeSupervisors();
  }
}
```

### Supervisor Dependency Flow

```
┌──────────────────────────────────────────────────────────────────────────┐
│                     SUPERVISOR DEPENDENCY FLOW                           │
└──────────────────────────────────────────────────────────────────────────┘

SCENARIO: VSCode Extension depends on Bridge

1. BRIDGE STARTS FIRST
   │
   ├─► Connects to orchestrator
   ├─► Registers: supervisorId="bridge", dependencies=[]
   ├─► Orchestrator starts Bridge (or Bridge starts itself)
   └─► Bridge state = "running"

2. VSCODE EXTENSION STARTS
   │
   ├─► Connects to orchestrator
   ├─► Registers: supervisorId="vscode-extension", dependencies=["bridge"]
   ├─► Checks if Bridge is running → YES
   └─► VSCode state = "running"

ALTERNATIVE: VSCODE STARTS FIRST

1. VSCODE EXTENSION STARTS
   │
   ├─► Connects to orchestrator
   ├─► Registers: supervisorId="vscode-extension", dependencies=["bridge"]
   ├─► Bridge not registered or not running
   └─► VSCode state = "waitingForDependencies"

2. VSCODE REQUESTS BRIDGE START
   │
   ├─► orchestrator.requestSupervisorStart(
   │     supervisorId: "bridge",
   │     startInfo: SupervisorStartInfo(...),
   │   )
   ├─► Bridge added to supervisors.json
   └─► Bridge state = "registered"

3. ORCHESTRATOR NEXT HEARTBEAT
   │
   ├─► Sees Bridge is "registered"
   ├─► Bridge has no dependencies
   ├─► Orchestrator starts Bridge
   └─► Bridge state = "running"

4. ORCHESTRATOR NEXT HEARTBEAT
   │
   ├─► Sees VSCode is "waitingForDependencies"
   ├─► Checks dependencies: Bridge = "running" ✓
   ├─► VSCode dependencies satisfied
   └─► VSCode state = "running"
```

---

## Part 7: Integrated Flow Example

### Scenario: Bridge Crashes During a Call Chain

```
Time  Event
──────────────────────────────────────────────────────────────────────────

T+0   CLI starts operation
      Stack: [CLI:active]
      State: running

T+1   CLI calls Bridge
      Stack: [CLI:active] → [Bridge:active]
      Bridge registers supervised call with handle "channel_42"

T+2   Bridge calls VSCode
      Stack: [CLI:active] → [Bridge:active] → [VSCode:active]
      VSCode has supervisor "vscode-extension" with handle "webview_7"

T+3   VSCode processing Copilot request...

T+4   ⚠️ BRIDGE CRASHES ⚠️
      Bridge process dies, heartbeat stops updating

T+4.5 NEXT LEDGER HEARTBEAT (Bridge)
      Detects Bridge.lastHeartbeat is stale (after staleness threshold)
      Action:
      1. Set operation.state = "cleanup"
      2. Mark Bridge frame as "crashed"

T+5   NEXT CLI HEARTBEAT
      Detects operation.state = "cleanup"
      Action:
      1. CLI cleans up internal state
      2. Requests removal of CLI frame from stack
      3. Ledger processes removal:
         → Find crashed frames above CLI: [Bridge:crashed, VSCode:active]
         → VSCode is active (not crashed), stop here
         → Remove only CLI frame
         → Stack becomes: [Bridge:crashed] → [VSCode:active]

T+5.5 NEXT VSCODE EXTENSION HEARTBEAT
      (VSCode Extension is the supervisor in VSCode process)
      Detects operation.state = "cleanup"
      Detects VSCode frame is still active
      Action:
      1. VSCode cleans up internal state (webview, etc)
      2. Requests removal of VSCode frame
      3. Ledger processes removal:
         → Find crashed frames above VSCode: none (VSCode is at end)
         → Remove VSCode frame
         → Stack becomes: [Bridge:crashed]

T+6   NEXT VSCODE HEARTBEAT (Bridge's supervisor)
      Detects operation.state = "cleanup"
      Detects crashed calls under supervisor "bridge":
      → Frame "channel_42" with handle "channel_42" is crashed
      Action:
      1. Ledger notifies supervisor via onCallCrashed callback
      2. Supervisor cleans up handle "channel_42" internally
      3. Ledger marks Bridge frame as "cleanedUp"

T+6.5 NEXT LEDGER HEARTBEAT
      Checks for unsupervised crashed frames:
      → Bridge has supervisor (but supervisor is dead now)
      → Skip (Rule 2 is for unsupervised)
      
      Check for crashed frames with dead supervisor:
      → Bridge supervisor is dead (no heartbeat for 5+ seconds)
      → Mark Bridge frame as "cleanedUp"

T+7   NEXT LEDGER HEARTBEAT
      Stack is empty
      Action:
      1. Set operation.state = "failed"
      2. Count = 0 of "heartbeats since terminal"

T+7.5 NEXT LEDGER HEARTBEAT
      State = "failed", count = 0 → increment to 1
      Still perform heartbeat

T+8   NEXT LEDGER HEARTBEAT
      State = "failed", count = 1 → increment to 2
      Still perform heartbeat

T+8.5 NEXT LEDGER HEARTBEAT
      State = "failed", count = 2 → increment to 3
      3 >= 2, so:
      1. Delete operation file
      2. Move to backup location
      3. Stop heartbeats

T+9   Operation cleaned up
      No operation file exists
      All participants can detect completion
```

### What Made This Simpler

1. **No ordered cleanup** - Participants clean themselves up independently
2. **Ledger is passive** - Just cleans resources, doesn't orchestrate
3. **Supervisors are notified** - Callback happens once during supervisor heartbeat
4. **Stack-aware removal** - Ledger removes stacked crashed frames when caller removes
5. **Automatic operation completion** - No manual marking needed
6. **No polling** - State changes propagate via heartbeat mechanism

---

## Part 8: API Summary

### Types in Operation File

| Type | Location | Purpose |
|------|----------|---------|
| `StackFrame.supervisorId` | Stack frame | Links frame to supervisor |
| `StackFrame.supervisorHandle` | Stack frame | Opaque handle for supervisor |
| `StackFrame.state` | Stack frame | Frame lifecycle state |
| `SupervisorHeartbeat` | supervisorHeartbeats map | Supervisor health tracking |
| `OperationState` | Operation root | Operation lifecycle state |

### Types in Supervisor API (In-Memory)

| Type | Purpose |
|------|---------|
| `SupervisedCallRegistry` | In-memory call tracking |
| `SupervisedCallEntry` | Single call registration |
| `CrashedCallCallback` | Notifies supervisor of crash |
| `CallLifecycleCallback` | Notifies supervisor of start/end |

### Types in Orchestration Files

| Type | File | Purpose |
|------|------|---------|
| `OrchestrationGroup` | {groupId}.orchestrator.json | Orchestrator state |
| `SupervisorsRegistry` | {groupId}.supervisors.json | All supervisors |
| `RegisteredSupervisor` | supervisors.json | Single supervisor |
| `SupervisorStartInfo` | supervisors.json | How to start a supervisor |
| `RestartPolicy` | supervisors.json | Restart configuration |

### Key Methods

| API | Method | Purpose |
|-----|--------|---------|
| Ledger | `initSupervisorLedger()` | Initialize supervisor-mode Ledger |
| Operation | `startCallExecution(supervisorHandle:)` | Start supervised call |
| Operation | `cleanupCrashedFrame()` | Clean up crashed callee |
| Orchestrator | `registerSupervisor()` | Register with orchestrator |
| Orchestrator | `requestSupervisorStart()` | Request dependency start |
| Orchestrator | `heartbeat()` | Update supervisor heartbeat |

---

## Implementation Phases

### Phase 1: Enhanced Stack Frames
- Add `supervisorId`, `supervisorHandle`, `state` to StackFrame
- Add `OperationState` to LedgerData
- Update serialization/deserialization

### Phase 2: Supervisor Heartbeats
- Add `SupervisorHeartbeat` to operation file
- Add supervisor heartbeat update logic
- Add supervisor death detection

### Phase 3: Supervisor API
- Implement `Ledger.initSupervisorLedger()`
- Implement in-memory `SupervisedCallRegistry`
- Implement callbacks for crash/start/end

### Phase 4: Cleanup Mechanism
- Implement cleanup state machine
- Implement `cleanupCrashedFrame()`
- Implement cleanup responsibility chain

### Phase 5: Orchestrator Core
- Implement orchestrator file management
- Implement supervisor registration
- Implement heartbeat monitoring

### Phase 6: Restart Logic
- Implement failure detection
- Implement backoff strategy
- Implement process restart

### Phase 7: Dependencies
- Implement dependency registration
- Implement dependency checking
- Implement pending start processing

### Phase 8: External Alerts
- Implement alert callback
- (Future: webhook support)
