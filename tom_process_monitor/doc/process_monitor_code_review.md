# Code Review: tom_process_monitor

**Reviewed:** 25 January 2026  
**Reviewer:** AI Assistant (GitHub Copilot)

## Overview

A well-structured process lifecycle management library with file-based registry, HTTP APIs for monitoring/control, and cross-platform support. The architecture is clean with good separation of concerns.

---

## ✅ Strengths

### 1. Clean Architecture
- Good separation: models, services, client, http, exceptions
- Single responsibility principle followed well
- Main `ProcessMonitor` class orchestrates services without doing low-level work

### 2. Cross-Platform Support
- Windows and Unix implementations in `ProcessControl`
- Platform-specific process spawning and killing logic

### 3. Robust Process Management
- Graceful shutdown with timeout before force kill
- Configurable restart policies with exponential backoff
- Indefinite retry mode for critical processes
- HTTP aliveness checking with configurable thresholds

### 4. File-Based Registry
- Lock mechanism for concurrent access (`RegistryLock`)
- JSON persistence with pretty printing
- `withLock` pattern prevents race conditions

### 5. Good Test Coverage Foundation
- Tests for models (ProcessConfig, RestartPolicy, AlivenessCheck)
- Serialization/deserialization tests

---

## ⚠️ Issues & Recommendations

### 1. README is incomplete (Low Priority)

**Location:** `README.md`

The README still has TODO placeholders. This should be updated with actual documentation including:
- Package description
- Features list
- Getting started guide
- Usage examples

---

### 2. Missing error handling in HTTP client (Medium Priority)

**Location:** `lib/src/services/aliveness_checker.dart` lines 19-26

```dart
} catch (e) {
  return false;
}
```

**Issue:** Silent catch-all suppresses all errors.

**Recommendation:** Consider logging failed checks for debugging:
```dart
} catch (e) {
  // Log at debug level for troubleshooting
  _logger?.call('Aliveness check failed for $url: $e');
  return false;
}
```

---

### 3. Hardcoded ports (Low Priority)

**Location:** `lib/src/models/registry.dart` line 17

Default ports (5681, 5682) are hardcoded.

**Recommendation:** Document these ports or make them configurable via environment variables.

---

### 4. Signal handling on Unix (Medium Priority)

**Location:** `lib/src/services/process_control.dart` lines 27-31

```dart
return Process.killPid(pid, ProcessSignal.sigcont);
```

**Issue:** Using `SIGCONT` to check aliveness is unconventional. While it works (returns true if process exists), it also resumes stopped processes.

**Recommendation:** Consider:
- Using signal 0 (`SIGUSR1` is not available, but the current approach works)
- On Linux, checking `/proc/{pid}/stat` for more reliable detection
- Document why `SIGCONT` is used

---

### 5. Windows PID detection is fragile (Medium Priority)

**Location:** `lib/src/services/process_control.dart` lines 99-115

**Issue:** Using `wmic` to find PID by process name could match wrong processes if multiple instances are running. The `start /b` approach doesn't return PID reliably.

**Recommendation:** Consider:
- Using a wrapper script that writes PID to a file
- Using PowerShell's `Start-Process -PassThru` which returns the process object
- Implementing a PID file mechanism where the spawned process writes its own PID

---

### 6. Missing input validation in remote API (High Priority)

**Location:** `lib/src/http/remote_api_server.dart` lines 159-163

```dart
final body = await _readJsonBody(request);
final config = ProcessConfig.fromJson(body);
```

**Issue:** `ProcessConfig.fromJson(body)` is called without validation. Malformed JSON could throw unhandled exceptions that crash the request handler.

**Recommendation:**
```dart
try {
  final body = await _readJsonBody(request);
  final config = ProcessConfig.fromJson(body);
  // ... rest of logic
} on FormatException catch (e) {
  await _sendError(request, HttpStatus.badRequest, 'Invalid JSON: ${e.message}');
  return;
} on TypeError catch (e) {
  await _sendError(request, HttpStatus.badRequest, 'Missing required field: $e');
  return;
}
```

---

### 7. No rate limiting on HTTP API (Medium Priority)

**Location:** `lib/src/http/remote_api_server.dart`

**Issue:** The remote API server has no rate limiting, which could be a concern for DoS attacks.

**Recommendation:** Implement basic rate limiting:
- Track requests per IP per time window
- Return 429 Too Many Requests when exceeded
- Consider using a middleware pattern for this

---

### 8. Self-restart race condition (Low Priority)

**Location:** `lib/src/process_monitor.dart` lines 155-177

```dart
// 4. Give new instance time to start
await Future<void>.delayed(const Duration(milliseconds: 500));

// 5. Exit current process
_log('Exiting current instance');
exit(0);
```

**Issue:** There's a 500ms delay, but no verification the new instance started successfully.

**Recommendation:**
- Increase delay or implement a handshake mechanism
- New instance could write a "ready" signal file
- Current instance waits for ready signal before exiting

---

### 9. Missing tests for critical paths

**Location:** `test/` directory

The following are not tested:
- Integration tests for `ProcessMonitor` start/stop lifecycle
- Tests for `RemoteApiServer` endpoints
- Tests for `ProcessControl.startProcess`
- Error scenarios (process crash handling, restart logic)

**Recommendation:** Add integration tests using temporary directories and mock processes.

---

### 10. Dispose pattern inconsistency

**Location:** `lib/src/process_monitor.dart`

**Issue:** `AlivenessChecker` has `dispose()` method but it's only called at the end of `stop()`. If `stop()` fails early, the HTTP client isn't closed.

**Recommendation:** Use try-finally pattern:
```dart
Future<void> stop() async {
  try {
    // ... stop logic
  } finally {
    _alivenessChecker.dispose();
    await _logManager.close();
  }
}
```

---

## 📋 Summary

| Category | Rating | Notes |
|----------|--------|-------|
| Code Structure | ⭐⭐⭐⭐⭐ | Excellent separation of concerns |
| Error Handling | ⭐⭐⭐ | Good but some gaps in HTTP API |
| Documentation | ⭐⭐ | README needs completion |
| Test Coverage | ⭐⭐⭐ | Models tested, missing integration tests |
| Security | ⭐⭐⭐ | Whitelist/blacklist exists, needs rate limiting |
| Cross-Platform | ⭐⭐⭐⭐ | Very good, Windows needs hardening |

**Overall:** Solid implementation with well-thought-out architecture. Main areas for improvement are completing the README, adding integration tests, and hardening the Windows process spawning logic.

---

## Action Items

### High Priority
- [ ] Add input validation in remote API endpoints

### Medium Priority
- [ ] Add logging to aliveness checker failures
- [ ] Improve Windows PID detection reliability
- [ ] Add rate limiting to HTTP API
- [ ] Add integration tests

### Low Priority
- [ ] Complete README documentation
- [ ] Document hardcoded port numbers
- [ ] Improve self-restart reliability
- [ ] Fix dispose pattern in stop() method
