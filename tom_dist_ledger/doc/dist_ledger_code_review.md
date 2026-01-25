# Tom Dist Ledger - Code Review

**Reviewed:** 25 January 2026  
**Version:** 0.1.0  
**Reviewer:** GitHub Copilot (Claude Opus 4.5)

---

## Executive Summary

The `tom_dist_ledger` package implements a **Distributed Processing Ledger (DPL)** for coordinating multi-process operations with crash detection, cleanup, and recovery. It's a sophisticated file-based coordination mechanism designed for scenarios where multiple processes (CLI, Bridge, VS Code Extension, Copilot) collaborate on operations that must be reliably tracked and cleaned up.

**Overall Assessment:** ⭐⭐⭐⭐ (4/5) - Well-designed architecture with comprehensive crash detection, but needs documentation improvements and test coverage expansion.

---

## Architecture Overview

### Core Components

| Component | File | Lines | Purpose |
|-----------|------|-------|---------|
| Ledger API | [ledger_api.dart](../lib/src/ledger_api/ledger_api.dart) | 3153 | Core ledger, operations, call management |
| Ledger Server | [ledger_server.dart](../lib/src/ledger_api/ledger_server.dart) | 568 | HTTP server for remote access |
| File Ledger | [file_ledger.dart](../lib/src/ledger_local/file_ledger.dart) | 303 | Data structures (LedgerData, CallFrame, etc.) |
| Remote Client | [remote_ledger_client.dart](../lib/src/ledger_client/remote_ledger_client.dart) | 1064 | HTTP client for remote ledger access |
| Simulator | [async_dpl_simulator.dart](../lib/src/simulator/async_dpl_simulator.dart) | 289 | Testing/simulation framework |
| Scenarios | [scenarios.dart](../lib/src/simulator/scenarios.dart) | 626 | Predefined test scenarios |

### Design Patterns

1. **File-based Locking**: Uses `.lock` files with participant/PID tracking for crash detection
2. **Heartbeat Monitoring**: Per-participant heartbeats for staleness detection
3. **Session Tracking**: Multiple joins to same operation tracked with session IDs
4. **Trail Snapshots**: Per-modification JSON snapshots for debugging
5. **Callback-based Events**: Structured callbacks for abort, failure, and heartbeat events

---

## Strengths

### 1. Comprehensive Crash Detection ✅

The heartbeat and staleness detection is well-implemented:

```dart
// Per-participant heartbeat tracking
for (final frame in data.callFrames) {
  final age = frame.heartbeatAgeMs;
  participantAges[frame.participantId] = age;
  if (age > stalenessThresholdMs) {
    staleParticipants.add(frame.participantId);
  }
}
```

- Each participant maintains its own heartbeat timestamp
- Stale lock detection with PID verification
- Automatic crash notification via callbacks

### 2. Clean API Design ✅

The public API is intuitive and well-structured:

```dart
// Clear lifecycle: create -> work -> complete
final op = await ledger.createOperation();
final call = await op.startCall<int>();
await call.end(result);
await op.complete();
```

- `Operation` wraps internal `_LedgerOperation` for clean encapsulation
- Session-based call tracking with automatic cleanup
- `SpawnedCall<T>` for async operations with typed results

### 3. Flexible Worker Execution ✅

The `exec*Worker` methods provide excellent abstractions:

- `execFileResultWorker` - For processes that write results to files
- `execStdioWorker` - For processes that output JSON to stdout
- `execServerRequest` - For requests to already-running servers
- Automatic process attachment for kill/cancel support

### 4. Robust Backup and Trail System ✅

Every modification creates a trail snapshot:

```dart
Future<String> _createTrailSnapshot(String operationId, String elapsedFormatted) async {
  final snapshotPath = _trailSnapshotPath(operationId, elapsedFormatted);
  await sourceFile.copy(snapshotPath);
  return snapshotPath;
}
```

- Chronological snapshots for debugging
- Automatic backup cleanup with configurable retention
- Per-operation backup folders

### 5. Excellent Simulation Framework ✅

The simulator provides comprehensive testing capabilities:

- Predefined scenarios covering success and various failure modes
- Configurable timing for realistic heartbeat testing
- Participant abstraction (CLI, Bridge, VSCode, Copilot)
- Failure injection at different phases

---

## Areas for Improvement

### 1. Single Large File (High Priority) ⚠️

[ledger_api.dart](../lib/src/ledger_api/ledger_api.dart) at **3153 lines** is too large for maintainability.

**Recommendation:** Split into focused files:
- `operation.dart` - Operation and _LedgerOperation classes
- `ledger.dart` - Ledger class
- `call.dart` - Call, SpawnedCall, CallCallback
- `sync.dart` - SyncResult, sync operations
- `helpers.dart` - OperationHelper utilities
- `callbacks.dart` - All callback types

### 2. Missing Documentation in pubspec.yaml (Medium Priority) ⚠️

The pubspec.yaml has no runtime dependencies but also lacks:
- `description` field
- `repository` URL
- `homepage` URL
- `issue_tracker` URL

**Current:**
```yaml
name: tom_dist_ledger
version: 0.1.0

environment:
  sdk: ^3.10.4

dev_dependencies:
  lints: ^5.0.0
  test: ^1.24.0
```

**Recommendation:** Add metadata for better discoverability.

### 3. Limited Test Coverage (Medium Priority) ⚠️

While [ledger_test.dart](../test/ledger_test.dart) is comprehensive at 3242 lines, some areas need more testing:

**Current test files:**
- `ledger_test.dart` - Core ledger tests
- `scenario_test.dart` - Simulation scenario tests
- `concurrent_scenario_test.dart` - Concurrent execution tests
- `isolate_scenario_test.dart` - Isolate-based tests
- `remote_ledger_test.dart` - Remote client tests
- `tom_dist_ledger_test.dart` - Basic library tests

**Missing coverage:**
- Error edge cases in `_handleStaleLock`
- Race conditions in concurrent lock acquisition
- Network failure scenarios in remote client
- Timeout handling in `pollFile`

### 4. Hardcoded Timing Constants (Low Priority) ⚠️

Several timing values are hardcoded:

```dart
static const _lockTimeout = Duration(seconds: 2);
static const _lockRetryInterval = Duration(milliseconds: 50);
// ...
Duration pollInterval = const Duration(milliseconds: 100),
```

**Recommendation:** Make these configurable via constructor or configuration object.

### 5. Error Message Localization (Low Priority) ⚠️

Error messages are hardcoded in English:

```dart
throw StateError('Cannot leave operation - join count is already 0');
throw StateError('Only the initiator can complete an operation');
```

**Recommendation:** Consider an error code system for easier localization and programmatic handling.

### 6. Missing API Documentation in README (Medium Priority) ⚠️

The [README.md](../README.md) is well-structured but could benefit from:
- More complete API reference section
- Error handling examples
- Migration guide from previous versions
- Performance considerations

---

## Code Quality Metrics

| Metric | Value | Assessment |
|--------|-------|------------|
| Total Dart Files | 20 | Good modularization except ledger_api.dart |
| Largest File | 3153 lines | Too large - split recommended |
| Test Files | 6 | Good coverage |
| Documentation | README complete | Missing API docs in code |
| Dependencies | 0 runtime | Excellent - self-contained |
| SDK Version | ^3.10.4 | Recent |

---

## Security Considerations

### 1. File Permissions ⚠️

Lock files and operation files are created without explicit permissions:

```dart
await lockFile.create(exclusive: true);
await lockFile.writeAsString(/* ... */);
```

**Recommendation:** Consider setting restrictive permissions (0600) for sensitive operation data.

### 2. Path Traversal Risk ⚠️

The `operationId` is used directly in file paths:

```dart
String _operationPath(String operationId) =>
    '$basePath/$operationId.operation.json';
```

While `operationId` is generated internally, if it could ever come from external input, path traversal would be possible.

**Recommendation:** Validate/sanitize `operationId` to prevent `../` sequences.

### 3. JSON Parsing ✅

JSON parsing uses proper try-catch handling and doesn't execute arbitrary code.

---

## Performance Considerations

### 1. Lock Contention

File locking with retry loops can cause contention under high load:

```dart
while (true) {
  try {
    if (lockFile.existsSync()) {
      // Retry loop with 50ms intervals
      await Future.delayed(_lockRetryInterval);
      continue;
    }
    // ...
  }
}
```

**Recommendation:** Consider exponential backoff for high-contention scenarios.

### 2. Trail Snapshot Growth

Every modification creates a trail snapshot. For long-running operations with many modifications:

```dart
await _createTrailSnapshot(operationId, elapsedFormatted);
```

**Recommendation:** Add configurable trail retention or size limits.

### 3. Global Heartbeat Overhead

The global heartbeat checks all operations periodically:

```dart
_globalHeartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
  _checkAllOperations(staleThreshold);
});
```

For ledgers with many operations, this could become expensive.

---

## Recommendations Summary

### High Priority
1. **Split ledger_api.dart** into multiple focused files
2. **Add more edge-case tests** for lock handling and race conditions

### Medium Priority
3. **Complete pubspec.yaml metadata** (description, URLs)
4. **Expand README** with API reference and error handling
5. **Add integration tests** for remote client failure scenarios

### Low Priority
6. **Make timing constants configurable**
7. **Consider error code system** for programmatic handling
8. **Add file permission handling** for sensitive data

---

## Conclusion

The `tom_dist_ledger` package is a well-designed distributed coordination system with:

- ✅ Robust crash detection and cleanup
- ✅ Clean, intuitive API
- ✅ Comprehensive simulation framework
- ✅ Good test coverage foundation

The main improvement areas are code organization (splitting the large ledger_api.dart file) and documentation (API docs, error handling examples). The architecture is sound and suitable for production use in multi-process coordination scenarios.

**Recommended for:** Production use with the suggested improvements for maintainability.
