// ignore_for_file: non_constant_identifier_names

/// Failure Notification Patterns
///
/// Dart code patterns for handling callee failures in a distributed ledger.
///
/// When a participant makes a call to another participant and waits for the
/// result, it needs to know if the callee crashed. The operation file contains
/// the state, but a Dart program shouldn't block on file polling.
///
/// This file demonstrates several patterns for efficient failure detection.
library;

import 'dart:async';

// ============================================================================
// TYPE DEFINITIONS
// ============================================================================

/// Operation state in the ledger.
enum OperationState {
  /// Operation is running normally.
  running,

  /// Failure detected, cleanup in progress.
  cleanup,

  /// All frames cleaned up.
  failed,

  /// Operation completed successfully.
  completed,
}

/// Represents an operation in the distributed ledger.
///
/// Provides state tracking and notification mechanisms for distributed calls.
abstract class Operation {
  /// Current operation state.
  OperationState get state;

  /// Stream of operation state changes.
  ///
  /// Emits [OperationStateEvent] whenever the operation state changes.
  /// Listens to this stream to detect when a callee fails without polling.
  Stream<OperationStateEvent> get stateChanges;

  /// Wait for the operation to reach a terminal state.
  ///
  /// Returns either [OperationState.failed] or [OperationState.completed].
  Future<OperationState> waitForTerminal();

  /// Wait for cleanup to start.
  ///
  /// Completes immediately if already in cleanup state.
  /// Otherwise completes when operation transitions to cleanup.
  Future<void> waitForCleanup();
}

class OperationStateEvent {
  final OperationState newState;
  final OperationState previousState;
  final DateTime timestamp;
  final String detectedBy;

  OperationStateEvent({
    required this.newState,
    required this.previousState,
    required this.timestamp,
    required this.detectedBy,
  });

  @override
  String toString() =>
      'StateChange($previousState → $newState at $timestamp by $detectedBy)';
}

// ============================================================================
// PATTERN 1: STREAM-BASED FAILURE DETECTION
// ============================================================================

/// Pattern 1: Listen to operation state changes to detect failures.
///
/// This is the recommended pattern for most use cases.
/// It avoids polling and integrates well with async/await.
Future<String> pattern1_streamBased(Operation operation) async {
  print('Pattern 1: Stream-Based Failure Detection');

  // Listen for state changes
  final subscription = operation.stateChanges.listen(
    (event) {
      print('State changed: ${event.newState}');

      if (event.newState == OperationState.cleanup) {
        print('Callee failed, entering cleanup');
      } else if (event.newState == OperationState.failed) {
        print('Operation failed and cleanup complete');
      }
    },
    onError: (error) {
      print('Error watching operation: $error');
    },
  );

  try {
    // Make the actual call while listening to state changes
    // In real code, this would be the actual RPC call
    final result = await _makeCall();
    return result;
  } finally {
    await subscription.cancel();
  }
}

// ============================================================================
// PATTERN 2: WAIT-FOR-CLEANUP
// ============================================================================

/// Pattern 2: Wait for cleanup to detect failure.
///
/// Use this when you want to know if the operation will fail (enter cleanup)
/// without waiting for full cleanup completion.
Future<String> pattern2_waitForCleanup(Operation operation) async {
  print('\nPattern 2: Wait For Cleanup');

  // Race the actual call against cleanup detection
  try {
    return await Future.any([
      // The actual call
      _makeCall(),

      // Cleanup detection
      operation.waitForCleanup().then(
            (_) => throw FailureDetectedException('Cleanup started'),
          ),
    ]);
  } on FailureDetectedException catch (e) {
    print('Failure detected: $e');
    return 'failed';
  }
}

// ============================================================================
// PATTERN 3: WAIT-FOR-TERMINAL WITH TIMEOUT
// ============================================================================

/// Pattern 3: Wait for terminal state with timeout.
///
/// Use this when you want to wait for the operation to completely finish
/// (either successfully or with failure cleanup), but also want a timeout.
Future<String> pattern3_waitForTerminalWithTimeout(
  Operation operation,
) async {
  print('\nPattern 3: Wait For Terminal With Timeout');

  final timeout = Duration(seconds: 30);

  try {
    // Wait for the operation to finish
    final finalState =
        await operation.waitForTerminal().timeout(timeout);

    if (finalState == OperationState.failed) {
      print('Operation failed');
      return 'failed';
    } else {
      print('Operation completed successfully');
      return 'success';
    }
  } on TimeoutException {
    print('Operation timed out waiting for terminal state');
    return 'timeout';
  }
}

// ============================================================================
// PATTERN 4: CONCURRENT CALL WITH MULTIPLE SAFETY NETS
// ============================================================================

/// Pattern 4: Complex pattern combining multiple safety mechanisms.
///
/// Use this for critical calls where you want:
/// - Early failure detection (via cleanup)
/// - Timeout protection
/// - Graceful degradation
/// - Proper cleanup
Future<String> pattern4_complexSafetyNet(
  Operation operation,
) async {
  print('\nPattern 4: Concurrent Call With Safety Nets');

  const callTimeout = Duration(seconds: 5);
  const totalTimeout = Duration(seconds: 30);

  final startTime = DateTime.now();

  // Create a future that tracks operation failure
  final failureDetector = operation.waitForCleanup().then(
    (_) {
      print('Failure detected at ${_elapsed(startTime)}');
      throw OperationFailedException('Callee entered cleanup state');
    },
  );

  // Create the actual call future
  final callFuture = _makeCall().timeout(
    callTimeout,
    onTimeout: () {
      print('Individual call timed out at ${_elapsed(startTime)}');
      throw CallTimeoutException('Call exceeded $callTimeout');
    },
  );

  // Create an overall timeout future
  final overallTimeout = Future.delayed(totalTimeout).then(
    (_) {
      print('Overall timeout at ${_elapsed(startTime)}');
      throw OverallTimeoutException('Total operation exceeded $totalTimeout');
    },
  );

  try {
    // Race all three
    return await Future.any([
      callFuture,
      failureDetector,
      overallTimeout,
    ]).timeout(
      // Additional safety net
      totalTimeout + const Duration(seconds: 5),
      onTimeout: () {
        print('CRITICAL: Future.any still not resolved');
        return 'critical_timeout';
      },
    );
  } on OperationFailedException {
    print('Callee failed - cleaning up');
    return 'callee_failed';
  } on CallTimeoutException {
    print('Call timed out - retrying or failing');
    return 'call_timeout';
  } on OverallTimeoutException {
    print('Operation timed out - aborting');
    return 'overall_timeout';
  } catch (e) {
    print('Unexpected error: $e');
    return 'unexpected_error: $e';
  }
}

// ============================================================================
// PATTERN 5: CALLBACK-BASED WITH EARLY EXIT
// ============================================================================

/// Pattern 5: Use callbacks for immediate state change notification.
///
/// Use this when you want to react immediately to state changes
/// and potentially exit the call early.
Future<String> pattern5_callbackBased(Operation operation) async {
  print('\nPattern 5: Callback-Based Pattern');

  bool failureDetected = false;

  // Set up immediate notification
  final subscription = operation.stateChanges.listen((event) {
    if (event.newState == OperationState.cleanup ||
        event.newState == OperationState.failed) {
      failureDetected = true;
      print('Failure detected by callback');
    }
  });

  try {
    // Make the call, but check for failure periodically
    return await _makeCallWithInterruption(
      checkInterrupt: () => failureDetected,
    );
  } finally {
    await subscription.cancel();
  }
}

// ============================================================================
// PATTERN 6: STREAM-BASED WITH FIRST
// ============================================================================

/// Pattern 6: Wait for the first of multiple completion signals.
///
/// Use this for a simple "any of these things happen first" pattern.
Future<String> pattern6_streamFirstPattern(Operation operation) async {
  print('\nPattern 6: Stream First Pattern');

  try {
    final result = await Future.any<String>([
      // Success path
      _makeCall().then((v) {
        print('Call succeeded: $v');
        return 'success: $v';
      }),

      // Failure path
      operation.stateChanges
          .where((e) => e.newState == OperationState.cleanup)
          .first
          .then((_) {
            print('Cleanup detected');
            throw OperationFailedException('Operation cleanup started');
          }),

      // Timeout path
      Future.delayed(const Duration(seconds: 10)).then((_) {
        print('Timeout');
        throw TimeoutException('Call timeout');
      }),
    ]);

    return result;
  } on OperationFailedException catch (e) {
    return 'operation_failed: $e';
  } on TimeoutException catch (e) {
    return 'timeout: $e';
  }
}

// ============================================================================
// UTILITY FUNCTIONS AND EXCEPTION TYPES
// ============================================================================

/// Simulate making a remote call.
/// In real code, this would be the actual RPC.
Future<String> _makeCall() async {
  await Future.delayed(const Duration(milliseconds: 100));
  return 'result_from_callee';
}

/// Simulate a call that can be interrupted.
Future<String> _makeCallWithInterruption({
  required bool Function() checkInterrupt,
}) async {
  for (int i = 0; i < 10; i++) {
    if (checkInterrupt()) {
      throw OperationFailedException('Interrupted by failure detection');
    }
    await Future.delayed(const Duration(milliseconds: 100));
  }
  return 'completed';
}

String _elapsed(DateTime start) {
  final elapsed = DateTime.now().difference(start);
  return '${elapsed.inMilliseconds}ms';
}

class FailureDetectedException implements Exception {
  final String message;
  FailureDetectedException(this.message);

  @override
  String toString() => 'FailureDetectedException: $message';
}

class OperationFailedException implements Exception {
  final String message;
  OperationFailedException(this.message);

  @override
  String toString() => 'OperationFailedException: $message';
}

class CallTimeoutException implements Exception {
  final String message;
  CallTimeoutException(this.message);

  @override
  String toString() => 'CallTimeoutException: $message';
}

class OverallTimeoutException implements Exception {
  final String message;
  OverallTimeoutException(this.message);

  @override
  String toString() => 'OverallTimeoutException: $message';
}

// ============================================================================
// EXAMPLE USAGE
// ============================================================================

Future<void> main() async {
  // Mock operation for demonstration
  final mockOperation = _MockOperation();

  // Try different patterns
  print('=== Failure Notification Patterns ===\n');

  final result1 = await pattern1_streamBased(mockOperation);
  print('Result 1: $result1\n');

  final result2 = await pattern2_waitForCleanup(mockOperation);
  print('Result 2: $result2\n');

  final result3 = await pattern3_waitForTerminalWithTimeout(mockOperation);
  print('Result 3: $result3\n');

  final result4 = await pattern4_complexSafetyNet(mockOperation);
  print('Result 4: $result4\n');

  final result5 = await pattern5_callbackBased(mockOperation);
  print('Result 5: $result5\n');

  final result6 = await pattern6_streamFirstPattern(mockOperation);
  print('Result 6: $result6\n');
}

// ============================================================================
// MOCK IMPLEMENTATION FOR TESTING
// ============================================================================

class _MockOperation implements Operation {
  OperationState _state = OperationState.running;
  final _stateController = StreamController<OperationStateEvent>.broadcast();
  late final Completer<OperationState> _terminalCompleter;
  late final Completer<void> _cleanupCompleter;

  _MockOperation() {
    _terminalCompleter = Completer<OperationState>();
    _cleanupCompleter = Completer<void>();
    _simulateFailure();
  }

  @override
  OperationState get state => _state;

  @override
  Stream<OperationStateEvent> get stateChanges =>
      _stateController.stream;

  @override
  Future<OperationState> waitForTerminal() =>
      _terminalCompleter.future;

  @override
  Future<void> waitForCleanup() => _cleanupCompleter.future;

  void _simulateFailure() {
    Future.delayed(const Duration(milliseconds: 500), () {
      _changeState(OperationState.cleanup);
      _cleanupCompleter.complete();
    });

    Future.delayed(const Duration(milliseconds: 1000), () {
      _changeState(OperationState.failed);
      _terminalCompleter.complete(OperationState.failed);
    });
  }

  void _changeState(OperationState newState) {
    final oldState = _state;
    _state = newState;
    _stateController.add(OperationStateEvent(
      newState: newState,
      previousState: oldState,
      timestamp: DateTime.now(),
      detectedBy: 'mock',
    ));
  }
}
