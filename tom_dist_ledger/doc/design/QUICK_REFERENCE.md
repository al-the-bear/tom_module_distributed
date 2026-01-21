# Cleanup Mechanism Simplification - Quick Reference

## Summary

The supervision and cleanup design has been dramatically simplified with four fundamental rules that create an automatic, self-healing cleanup system. No manual ordering, no complex orchestration, just state-driven behavior.

## The Four Rules

### Rule 1: Every Live Frame Cleans Itself
```
When: operation.state transitions to "cleanup"
Who: Every active participant
What: 
  1. Detect cleanup state via heartbeat
  2. Cleanup internal resources
  3. Request frame removal from stack
```

### Rule 2: Ledger Cleans Unsupervised Crashed Frames
```
When: Next Ledger heartbeat after state → cleanup
Who: Ledger (automatic)
What:
  1. For each crashed frame with NO supervisor
  2. Delete temp files/folders
  3. Mark frame as "cleanedUp"
  (Frame stays in stack until its caller removes itself)
```

### Rule 3: Supervisor Cleans Its Crashed Calls
```
When: Supervisor's next heartbeat after state → cleanup
Who: Supervisor (notified by Ledger)
What:
  1. Ledger detects crashed calls in supervisor's domain
  2. Ledger calls onCallCrashed callback with supervisorHandle
  3. Supervisor cleans internal state
  4. Ledger marks frame as "cleanedUp"
```

### Rule 4: Remove Frames with Dead Supervisor
```
When: Supervisor dies during cleanup (stale heartbeat)
Who: Any alive participant
What:
  1. Detect supervisor is dead
  2. Remove crashed frames that belonged to dead supervisor
  3. (No callback needed, supervisor is gone)
```

## Stack-Aware Frame Removal

When a frame requests removal, Ledger is smart about cleanup:

```
Stack: [CLI:active] → [Bridge:crashed] → [VSCode:crashed]

When CLI requests removal:
  - Check frames above CLI: Bridge(crashed), VSCode(crashed)
  - VSCode is the last frame, Bridge is crashed
  - Remove all three together
  - Stack becomes empty

Stack: [CLI:active] → [Bridge:active] → [VSCode:crashed]

When Bridge requests removal:
  - Check frames above Bridge: VSCode(crashed)
  - VSCode is crashed, remove it too
  - Remove Bridge and VSCode together
  - Stack becomes: [CLI:active]
```

## Operation Completion Timeline

```
T+0   Crash detected
      state = "cleanup"

T+X   All frames cleaned, stack becomes empty
      state = "failed"
      heartbeat_counter = 0

T+X+1 Heartbeat continues
      state = "failed"
      heartbeat_counter = 1

T+X+2 Heartbeat continues
      state = "failed"
      heartbeat_counter = 2

T+X+3 Delete operation file
      Stop heartbeats
```

## Calling Another Participant Safely

When you call another participant and need to know if it crashes:

### Simple: Listen to State Changes
```dart
operation.stateChanges.listen((event) {
  if (event.newState == OperationState.cleanup) {
    print('Callee entered cleanup (likely crashed)');
  }
});

final result = await call();
```

### With Timeout: Wait for Cleanup
```dart
try {
  return await Future.any([
    call(),
    operation.waitForCleanup()
        .timeout(Duration(seconds: 30)),
  ]);
} on TimeoutException {
  print('Callee failed to respond');
}
```

### Complex: Full Safety Net
```dart
try {
  return await Future.any([
    call().timeout(Duration(seconds: 5)),  // Call timeout
    operation.waitForCleanup()
        .then((_) => throw CalleeFailedException()),
    Future.delayed(Duration(seconds: 30)),  // Overall timeout
  ]);
} on CalleeFailedException {
  print('Callee failed');
} on TimeoutException {
  print('Timeout');
}
```

See `doc/examples/failure_notification_patterns.dart` for all 6 patterns with working code.

## Supervisor Association

Each stack frame can optionally have a supervisor:

```dart
class StackFrame {
  String participantId;
  String callId;
  int pid;
  
  // NEW:
  String? supervisorId;        // "bridge", "vscode-extension", etc
  String? supervisorHandle;    // Opaque handle for supervisor's use
  FrameState state;            // active, crashed, cleanedUp
}
```

Example in operation file:
```json
{
  "stack": [
    {
      "participantId": "cli",
      "callId": "cli-main",
      "supervisorId": null,
      "state": "active"
    },
    {
      "participantId": "bridge",
      "callId": "bridge-process",
      "supervisorId": "bridge",
      "supervisorHandle": "channel_42",
      "state": "active"
    }
  ]
}
```

## Supervisor API

### Initialize Supervisor Ledger

Called ONCE at startup by the supervisor:

```dart
Ledger.initSupervisorLedger(
  supervisorId: 'bridge',
  ledgerPath: '/path/to/ledger',
  heartbeatInterval: Duration(milliseconds: 4500),
  stalenessThreshold: Duration(seconds: 10),
  onCallCrashed: (handle, info) async {
    // Clean up resources for supervisorHandle
  },
  onCallStarted: (handle, info) async {
    // Optional: track call start
  },
  onCallEnded: (handle, info) async {
    // Optional: track normal completion
  },
);
```

### Ledger Detects Supervisor Automatically

When a call adds its frame with supervisor info:
```dart
await operation.startCallExecution(
  callId: 'call-123',
  supervisorHandle: 'opaque_handle_for_supervisor',
);
// Ledger automatically gets supervisorId from Ledger.instance
// Frame created with: supervisorId = 'bridge', supervisorHandle = 'opaque_handle_for_supervisor'
```

## Orchestrator Two-File Structure

### {groupId}.orchestrator.json
Orchestrator state (one per group):
```json
{
  "orchestrationGroupId": "tom-workspace",
  "orchestratorPid": 5000,
  "orchestratorHeartbeat": "2026-01-21T...",
  "state": "running"
}
```

### {groupId}.supervisors.json
All supervisors in group:
```json
{
  "supervisors": {
    "bridge": {
      "supervisorId": "bridge",
      "startInfo": {
        "command": "/usr/bin/tom-bridge",
        "args": ["--workspace", "/path"],
        "workingDirectory": "/path",
        "restartPolicy": {
          "maxAttempts": 5,
          "backoffIntervalsMs": [0, 1000, 5000, 15000, 60000]
        }
      },
      "restartable": true,
      "state": "running",
      "pid": 12345,
      "lastHeartbeat": "2026-01-21T...",
      "dependencies": []
    },
    "vscode-extension": {
      "supervisorId": "vscode-extension",
      "startInfo": null,              // Not restartable (user starts it)
      "restartable": false,
      "state": "running",
      "pid": 23456,
      "dependencies": ["bridge"]       // Depends on Bridge
    }
  }
}
```

## Key Benefits

| Feature | Benefit |
|---------|---------|
| **Four simple rules** | Easy to understand and implement |
| **Self-healing** | Automatic recovery without manual intervention |
| **No ordering** | All frames cleanup independently, no deadlocks |
| **State-driven** | Everything follows operation state |
| **Passive ledger** | Ledger just helps, doesn't orchestrate |
| **Stream-based failure detection** | No polling, efficient Dart async |
| **Stack-aware removal** | Automatically cleans stacked crashed frames |
| **Optional supervisor** | Works with or without supervisor |
| **Preserves registrations** | Orchestrator remembers healthy supervisors |

## Implementation Order

1. **Frame State Machine** - Add `FrameState` enum and `state` field to StackFrame
2. **Supervisor Association** - Add `supervisorId` and `supervisorHandle` to StackFrame
3. **Cleanup Detection** - Participants detect `state = cleanup` via heartbeat
4. **Rule 1 + Rule 4** - Frame removal and dead supervisor detection
5. **Rule 2** - Unsupervised frame cleanup
6. **Rule 3** - Supervisor notification and cleanup
7. **State Notifications** - Add `stateChanges` stream to Operation
8. **Tests** - Update and add tests for all rules
