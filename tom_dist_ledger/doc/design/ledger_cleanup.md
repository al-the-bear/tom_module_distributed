# Ledger Cleanup Mechanism (Simplified)

## Overview

The cleanup mechanism is **ultra-simple**: one component detects the crash and coordinates cleanup:

1. **Detection** - Detects stale heartbeat, marks crashed frame, signals others to cleanup
2. **Self-Cleanup Window** - Other participants get one heartbeat to cleanup themselves
3. **Final Frame Removal** - After 2 heartbeats, coordinator removes all remaining frames
4. **File Deletion** - After 2 more heartbeats, coordinator deletes operation file

No complex ordering, no multiple rules, no simultaneous independent processes - just sequential phases with clear ownership.

---

## Operation States

```dart
enum OperationState {
  /// Operation is running normally.
  running,
  
  /// Failure detected, cleanup in progress.
  cleanup,
  
  /// Cleanup complete, operation failed.
  failed,
  
  /// Operation completed successfully.
  completed,
}
```

---

## Frame States

```dart
enum FrameState {
  /// Frame is executing normally.
  active,
  
  /// Frame's participant process has crashed.
  crashed,
  
  /// Frame is being cleaned up.
  cleaningUp,
  
  /// Frame is cleaned and can be removed.
  cleanedUp,
  
  /// Frame has been processed by supervisor after crash
  dead,
}
```

## Cleanup Methods

The cleanup mechanism uses cleanup operations at different levels:

- **`frame.cleanup()`** - Ledger API method that cleans up all resources associated with the frame (connections, temp files, allocated memory). Called on any frame being removed.
- **`call.performLocalCleanup()`** - Application callback on the call object. Handles the call's internal cleanup (release resources, close connections, etc.). Must be implemented by the application.
- **`supervisor.onCallCleanup(info)`** - Supervisor callback. Handles supervisor's internal cleanup for a specific supervised call (close supervisor resources). Must be implemented by the application.

Both `call.performLocalCleanup()` and `supervisor.onCallCleanup()` are responsible for notifying any internal housekeeping systems and coordinating cleanup with their own internal structures.

---

## The Simplified Cleanup Sequence

### Crash at T(crash)

### Phase 1: Detection (Single Heartbeat) at T(crash) + 2

**What happens:**
A call heartbeat detects a stale heartbeat from a crashed participant. This call becomes the "cleanup coordinator."

**Cleanup coordinator (call detecting the crash):**
1. Marks the crashed frame as `crashed` (if supervised) or `cleanedUp` (if unsupervised)
2. Calls `frame.cleanup()` on unsupervised crashed frames (cleans their resources)
3. Marks ALL other frames in the stack as `cleanup` (not crashed, just "need cleanup")
4. Sets `operation.state = OperationState.cleanup`
5. **Still holds the operation file lock**
6. Performs its own cleanup via `call.performLocalCleanup()` (releases resources, closes connections, etc.)
7. Calls `frame.cleanup()` on its own frame
8. Transitions itself to `cleaningUp` state
9. **Releases the operation file lock**
10. Goes to sleep for two heartbeats (gives others a chance to detect, cleanup and stop their heartbeats)

**Note:** Only call heartbeats detect crashes. Supervisors are NOT notified and do not detect crashes themselves - they will passively react to the cleanup state in their own heartbeat (Phase 2).

**Code sketch:**
```dart
var data = await operation.retrieveAndLockOperation();
if (data == null) {
  // Failed to acquire lock
  return;
}

var foundCrash = false;
var myFrameIndex = /* our index in stack */;

// find stale frames  
for (var i = 0; i < data.stack.length; i++) {
  var frame = data.stack[i];
  if (frame.isStale(timeoutMs: operation.stalenessThresholdMs)) {
    if (frame.supervisorId == null) {
      // Unsupervised crashed frame - we clean it
      await frame.cleanup();
      frame.state = FrameState.cleanedUp;
    } else {
      // Supervised crashed frame - mark for supervisor to handle
      frame.state = FrameState.crashed;
    }
    foundCrash = true;
  } else if (i != myFrameIndex) {
    // Other frames need cleanup too
    frame.state = FrameState.cleanup;
  }
}

if (foundCrash) {
  // Still holding lock, perform local cleanup
  await call.performLocalCleanup();
  
  // Cleanup own frame
  await data.stack[myFrameIndex].cleanup();
  // mark as coordinator, this is like cleanedUp, but for the coordinator
  data.stack[myFrameIndex].state = FrameState.cleaningUp;
  
  // Set operation to cleanup state
  operation.operationState = OperationState.cleanup;
  data.detectionTimestamp = DateTime.now();
  
  // write and release lock
  await operation.writeAndUnlockOperation(data);
}
```

**Note:** This cleanup detection only runs during a call heartbeat when a stale frame is detected. When the operation is running normally, this `if (foundCrash)` block is skipped and the normal heartbeat logic continues.

### Phase 2: Self-Cleanup Window (One Heartbeat Interval) at T(crash) + 2/3

**What happens:**
All participants react to the cleanup state set by the coordinator.

**Call heartbeats (non-coordinator calls):**
1. Detect `operationState = cleanup` 
2. Perform their own internal cleanup via `call.performLocalCleanup()`
3. Call `frame.cleanup()` on their own frame
4. Mark frame as `cleanedUp`
5. Stop heartbeating

**Supervisor heartbeats:**
1. Detect `operationState = cleanup`
2. Scan the stack for crashed and cleanedUp frames with their supervisor ID
3. For each frame they manage:
   - Call `supervisor.onCallCleanup(info)` for internal cleanup
   - Mark frame as `dead`
   - Call `supervisor.onCallCrashed(info)` to notify supervisor
4. Wait one heartbeat, then do final cleanup pass for any remaining frames
5. Stop heartbeating

**Code in call heartbeat:**  
  
This also runs in the coordinator, so we must distinguish standard call heartbeat from coordinator call heart beat

```dart
final result = await operation.heartbeat();

if (operation.cachedData?.operationState == OperationState.cleanup) {
  // This cleanup block only runs when operation is in cleanup state.
  // When operation is running normally, this entire if-block is skipped
  // and the normal heartbeat logic continues below.
  
  final data = await operation.retrieveAndLockOperation();
  if (data != null) {
    final myFrameIndex = data.stack.indexWhere(
      (f) => f.participantId == operation.participantId
    );
    
    if (myFrameIndex >= 0 ) {    
      if( data.stack[myFrameIndex].state != FrameState.cleaningUp) {
        // We're in cleanup - do our cleanup
        await call.performLocalCleanup();
        await data.stack[myFrameIndex].cleanup();
        data.stack[myFrameIndex].state = FrameState.cleanedUp;
        await operation.writeAndUnlockOperation(data);    
        // Stop heartbeating
        operation.stopHeartbeat();
      }else{
        // coordinator handling here
      }
    }
  }else{
    // Stop heartbeating, it has already been removed for unknown reasons
    operation.stopHeartbeat();
  }
  
  return;
}

// ... normal heartbeat logic continues ...
```

**Code in supervisor heartbeat:**
```dart
final result = await operation.heartbeat();

if (operation.cachedData?.operationState == OperationState.cleanup) {
  // This cleanup block only runs when operation is in cleanup state.
  // When operation is running normally, this entire if-block is skipped
  // and the normal heartbeat logic continues below.
  
  // React to cleanup state - scan for our frames
  final data = await operation.retrieveAndLockOperation();
  if (data != null) {
    for (final frame in data.stack) {
      if ((frame.state == FrameState.crashed || 
           frame.state == FrameState.cleanedUp) &&
          frame.supervisorId == ourSupervisorId) {
        // Our call is in cleanup - handle supervisor cleanup
        if( frame.state == FrameState.crashed ) {
          frame.cleanup();
        }
        frame.state = FrameState.dead;
        // Supervisor's call-specific internal cleanup
        final cleanupInfo = CallCleanupInfo.fromFrame(frame);
        await supervisor.onCallCleanup(cleanupInfo);
        // Notify supervisor of crash
        final crashedInfo = CrashedCallInfo.fromFrame(frame);
        await supervisor.onCallCrashed(crashedInfo);
      }
    }
    
    // Stop heartbeating after one heartbeat to give calls time to cleanup
    if (result != null && 
        operation.cachedData?.detectionTimestamp != null &&
        DateTime.now().difference(operation.cachedData!.detectionTimestamp!) >=
            Duration(milliseconds: heartbeatIntervalMs)) {
      
      // Final cleanup pass for any remaining frames
      for (var frame in data.stack) {
        if (frame.supervisorId == ourSupervisorId && 
            frame.state != FrameState.dead) {
          frame.cleanup();  
          // Supervisor's call-specific internal cleanup
          final cleanupInfo = CallCleanupInfo.fromFrame(frame);
          await supervisor.onCallCleanup(cleanupInfo);
          // Notify supervisor of crash
          final crashedInfo = CrashedCallInfo.fromFrame(frame);
          await supervisor.onCallCrashed(crashedInfo);
          frame.state = FrameState.dead;
        }
      }
      
      await operation.writeAndUnlockOperation(data);
      operation.stopSupervisorHeartbeat();
    } else {
      await operation.unlockOperation();
    }
  }else{ // data == null, no more operation file
    operation.stopSupervisorHeartbeat();
  }
  return;
}

// ... normal heartbeat logic continues ...
```

### Phase 3: Final Frame Removal at T(crash) + 4

**What happens:**
Coordinator waits 2 heartbeats to give all participants a chance to cleanup, then removes remaining frames. (already mentioned in Phase 1).

**Cleanup coordinator - Frame removal phase:**
1. Waits until 2 heartbeats have passed since detection (detectionTimestamp + 2x heartbeatInterval)
2. Removes all remaining frames from stack, performs any pending cleanup for those frames
3. Sets `operation.state = failed`
4. Notes timestamp for next phase

**Code sketch:**
```dart

final data = await operation.retrieveAndLockOperation();
if (data == null) {
  // no more operation file. Let's just stop.
  operation.stopHeartBeat();
  return;
}

// In coordinator heartbeat, check if 2 more heartbeats have passed
// This block only runs when operation is in cleanup state.
// When operation is running normally, this entire if-block is skipped
// and the normal heartbeat logic continues.
if (data.operationState == OperationState.cleanup &&
    data.detectionTimestamp != null &&
    DateTime.now().difference(data.detectionTimestamp!) >= 
        Duration(milliseconds: 2 * heartbeatIntervalMs)) {
  
  // Clean up all frames that are still in cleanup or crashed state
  for (var frame in data.stack) {
    if (frame.state != FrameState.cleaningUp && 
        frame.state != FrameState.dead && 
        frame.state != FrameState.cleanedUp ) {
      await frame.cleanup();
    }
  }
  
  // Remove all frames from stack
  data.stack.clear();
  
  // Mark operation as failed
  data.operationState = OperationState.failed;
  data.removalTimestamp = DateTime.now();
  
  await operation.writeAndUnlockOperation(data);
} else {
  await operation.unlockOperation();
}
```

### Phase 4: File Deletion (After 2 More Heartbeats) at T(crash) + 6

**What happens:**
Coordinator waits 2 more heartbeats to give participants time to detect failure state and cleanup situation in case they are still heartbeating, then deletes operation file.

**Purpose:**
- Gives other participants time to detect `state = failed`
- Gives supervisors time to react to final state
- Increases chance of file durability before deletion

**Cleanup coordinator - File deletion phase:**
1. Waits until 2 heartbeats have passed since frame removal
2. Deletes the operation file (or moves to backup location)
3. Stops heartbeating

**Code in Operation heartbeat:**
```dart
final data = await operation.retrieveAndLockOperation();
if (data == null) {
  // no more operation file. Let's just stop.
  operation.stopHeartBeat();
  return;
}

if (data.operationState == OperationState.failed &&
    data.removalTimestamp != null &&
    DateTime.now().difference(data.removalTimestamp!) >= 
        Duration(milliseconds: 2 * heartbeatIntervalMs)) {
  // Delete the operation file or backup
  await operation._ledger._deleteOperation(operationId);
  // Stop heartbeating
  operation.stopHeartbeat();
  return;
}

await operation.unlockOperation();
```


---

## Complete Timeline Example: Bridge Crashes

### T+0: Bridge Process Crashes
  
This happens without any notification, but the heartbeat of the call stops.  

## Coordinator Timeline (Call Detecting the Crash)

### T+2: Detection + Self-Cleanup (Phase 1)

```
Action (A call detects stale heartbeat and becomes coordinator):
  1. Call detects stale heartbeat for another participant
  2. If unsupervised crashed frame: call frame.cleanup() and mark cleanedUp
  3. If supervised crashed frame: just mark crashed (supervisor will handle cleanup)
  4. Mark all other frames as cleanup
  5. Perform coordinator's own cleanup via call.performLocalCleanup()
  6. Call frame.cleanup() on own frame
  7. Mark own frame as cleaningUp
  8. Set operation.operationState = cleanup
  9. Release lock
  10. Note detectionTimestamp = T+2

Stack: [CLI:cleaningUp] → [Bridge:crashed] → [VSCode:cleanup, Other:cleanup]
State: cleanup
```

---

### T+3: Wait Heartbeat

```
Coordinator waits for condition check:
  now() - detectionTimestamp >= 2*heartbeatInterval
```

---

### T+4: Frame Removal (Phase 3)
```
Action:
  1. Time condition met
  2. For all frames still in cleaningUp or crashed state: call frame.cleanup()
  3. Remove all frames from stack
  4. Set state = failed
  5. Note removalTimestamp = T+4

Stack: []
State: failed
```

---

### T+5: Wait Heartbeat
```
Coordinator waits for condition check:
  now() - removalTimestamp >= 2*heartbeatInterval
```

---

### T+6: File Deletion (Phase 4) → Stop Heartbeat
```
Action:
  1. Time condition met
  2. Delete operation file (or backup)
  3. Stop heartbeating

File deleted
Coordinator stops 
```

---

## Other Participants Timeline (CLI, VSCode, Supervisors)

### T+0: Crash Happens

### T+2 or T+3: Detect Cleanup State (Phase 2: Self-Cleanup) → Stop Heartbeat
```
Somewhere in this time window, each participant detects state = cleanup:

During call heartbeat
  - Performs cleanup for its own frame via performLocalCleanup()
  - Calls frame.cleanup() on own frame
  - Sets frame state to cleanedUp
  - Stops heartbeating

During supervisor heartbeat:
  - Scans for calls with supervisorId == self.id
  - If frame.state == crashed OR cleanedUp (call might have cleaned itself):
    - Performs supervisor cleanup via onCallCleanup(info)
    - Marks frame state as dead
    - Notifies supervisor via onCallCrashed(info)
  - Waits one heartbeat then cleans up calls not yet cleaned up and 
    stops heartbeating.

All participants except coordinator: STOPPED (before T+4 Frame Removal)
```

---

## Coordinator Continues Alone

### T+4: Frame Removal (Phase 3)

Coordinator (now alone) performs cleanup on any frames still in `cleaningUp` or `crashed` state, removes all frames from stack, and sets operation to `failed`.

No other participants are heartbeating at this point.

---

## Key Simplifications vs. Previous Design

| Aspect | Before | Now |
|--------|--------|-----|
| **Rules** | 4 independent rules | Sequential 4-phase process |
| **Ownership** | Distributed across components | Single coordinator |
| **Cleanup window** | Varies per rule | One fixed heartbeat |
| **Final removal** | After each frame self-removes | Single batch cleanup |
| **Supervisor notification** | Part of heartbeat loop | Part of Phase 1 |
| **Code complexity** | Multiple state machines | Single sequence |

---

## Benefits

✅ **Extremely simple** - 4 phases, sequential, no parallel concerns  
✅ **Single point of ownership** - Coordinator handles everything  
✅ **Fair cleanup window** - Everyone gets exactly one heartbeat  
✅ **No race conditions** - File lock prevents concurrent modifications  
✅ **Clear implementation** - No complex rules to manage  
✅ **Easy to test** - Each phase is testable independently  

---

## Testing Scenarios

### Test 1: Simple Crash
- Setup: CLI → Bridge
- Action: Bridge crashes
- Verify: Both frames cleaned and removed, state becomes failed, file deleted

### Test 2: Supervisor Callback
- Setup: CLI → Bridge (supervised)
- Action: Bridge crashes
- Verify: Supervisor callback invoked during Phase 2 (self-cleanup window)

### Test 3: Stacked Frames
- Setup: CLI → B1 → B2 → B3 (B1 crashes)
- Action: B1 crashes
- Verify: All frames removed in Phase 3 (after 2 heartbeats)

### Test 4: Multiple Supervisors
- Setup: CLI → Bridge (supervised by A) → VSCode (supervised by B)
- Action: Bridge crashes
- Verify: Both supervisors' callbacks invoked, all frames cleaned

### Test 5: Early Frame Detection
- Setup: CLI → Bridge (crashing)
- Action: Bridge crashes while all participants are mid-heartbeat
- Verify: Some detect at T+2, others at T+3, all stop before T+4

---

## Implementation Checklist

- [ ] Add `FrameState` enum to `StackFrame`
- [ ] Add `state` field to `StackFrame`
- [ ] Update `OperationState` enum (add `cleanup`, `failed`)
- [ ] Add `detectionTimestamp` and `removalTimestamp` to Operation data
- [ ] Implement Phase 1 detection in heartbeat (set cleanup, mark frames, release lock)
- [ ] Implement Phase 2 self-cleanup in participant heartbeats (detect cleanup state)
- [ ] Implement Phase 3 frame removal in coordinator (after 2 heartbeats elapsed)
- [ ] Implement Phase 4 file deletion in coordinator (after 2 more heartbeats elapsed)
- [ ] Update operation file JSON serialization for new fields
- [ ] Update heartbeat loop logic for all participants
- [ ] Write tests for each phase
- [ ] Write integration test with all phases and multiple participants
