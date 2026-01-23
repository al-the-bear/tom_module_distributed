/// Data classes for call callbacks and info structures.
///
/// These classes support the callback pattern for cleanup and crash notification.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../local_ledger/file_ledger.dart' show HeartbeatResult;
import 'ledger_api.dart' show HeartbeatError, Operation;

/// Callback structure for operation-level events.
///
/// Provides hooks for heartbeat success/error notifications during operation
/// lifecycle. Use this with [Ledger.createOperation] and [Ledger.joinOperation].
///
/// **Example:**
/// ```dart
/// final op = await ledger.createOperation(
///   callback: OperationCallback(
///     onHeartbeatSuccess: (op, result) => print('Heartbeat OK'),
///     onHeartbeatError: (op, error) => print('Failure: ${error.message}'),
///   ),
/// );
/// ```
class OperationCallback {
  /// Called on each successful heartbeat.
  ///
  /// Use this for monitoring heartbeat health and stack state.
  final void Function(Operation operation, HeartbeatResult result)? onHeartbeatSuccess;

  /// Called when a heartbeat detects a failure.
  ///
  /// The [HeartbeatError] contains information about what failed
  /// (stale participant, missing file, etc.). Use this to trigger
  /// recovery or cleanup actions.
  final void Function(Operation operation, HeartbeatError error)? onHeartbeatError;

  /// Creates an operation callback with optional handlers.
  const OperationCallback({
    this.onHeartbeatSuccess,
    this.onHeartbeatError,
  });

  /// Creates a callback that only handles errors.
  factory OperationCallback.onError(
    void Function(Operation operation, HeartbeatError error) onError,
  ) {
    return OperationCallback(onHeartbeatError: onError);
  }
}

/// Callback structure for spawned call operations.
///
/// Provides hooks for cleanup, completion, crash handling, and operation failure.
/// The type parameter [T] matches the result type of the spawned call.
class CallCallback<T> {
  /// Called by ledger during cleanup (crash or normal operation end).
  /// Use this to release resources, close connections, delete temp files, etc.
  final Future<void> Function()? onCleanup;

  /// Called when the call completes successfully with a result.
  final Future<void> Function(T result)? onCompletion;

  /// Called when this call crashes. Return a fallback result or null.
  /// If a non-null value is returned, the call is considered successful with that value.
  final Future<T?> Function()? onCallCrashed;

  /// Called when the operation fails (not just this call, but the whole operation).
  final Future<void> Function(OperationFailedInfo info)? onOperationFailed;

  CallCallback({
    this.onCleanup,
    this.onCompletion,
    this.onCallCrashed,
    this.onOperationFailed,
  });

  /// Create a simple callback with just cleanup logic.
  factory CallCallback.cleanup(Future<void> Function() onCleanup) {
    return CallCallback<T>(onCleanup: onCleanup);
  }
}

/// Information about an operation failure.
///
/// Passed to [CallCallback.onOperationFailed] and [Operation.sync].
class OperationFailedInfo {
  /// The operation that failed.
  final String operationId;

  /// When the failure was detected.
  final DateTime failedAt;

  /// The reason for the failure, if known.
  final String? reason;

  /// List of call IDs that crashed.
  final List<String> crashedCallIds;

  OperationFailedInfo({
    required this.operationId,
    required this.failedAt,
    this.reason,
    this.crashedCallIds = const [],
  });

  @override
  String toString() =>
      'OperationFailedInfo(operationId: $operationId, crashedCallIds: $crashedCallIds, reason: $reason)';
}

/// Exception thrown when an operation fails.
///
/// This exception wraps [OperationFailedInfo] and is thrown by methods like
/// [Operation.waitForCompletion] when the operation fails before work completes.
class OperationFailedException implements Exception {
  /// The failure info.
  final OperationFailedInfo info;

  OperationFailedException(this.info);

  @override
  String toString() => 'OperationFailedException: ${info.reason ?? info.operationId}';
}

/// Log levels for operation logging.
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// Extension to convert LogLevel to string.
extension LogLevelExtension on LogLevel {
  String get name => switch (this) {
        LogLevel.debug => 'DEBUG',
        LogLevel.info => 'INFO',
        LogLevel.warning => 'WARNING',
        LogLevel.error => 'ERROR',
      };
}

// ═══════════════════════════════════════════════════════════════════
// CALL CLASS (for synchronous call tracking)
// ═══════════════════════════════════════════════════════════════════

/// Represents an active call that was started synchronously.
///
/// This class is returned by [Operation.startCall] and provides methods
/// to end or fail the call without needing to track callIds manually.
///
/// Example:
/// ```dart
/// final call = await operation.startCall<int>(
///   callback: CallCallback(onCleanup: () async => print('cleanup')),
/// );
/// try {
///   // Do work...
///   final result = await computeSomething();
///   await call.end(result);
/// } catch (e, st) {
///   await call.fail(e, st);
/// }
/// ```
class Call<T> {
  /// The call ID generated by the ledger.
  final String callId;

  /// Optional description of this call.
  final String? description;

  /// The operation this call belongs to.
  final dynamic _operation; // Operation type, but avoid circular import

  /// When the call was started.
  final DateTime startedAt;

  /// Whether this call has been ended or failed.
  bool _isCompleted = false;

  /// Creates a Call instance.
  /// 
  /// This constructor is for internal use by the ledger API.
  Call.internal({
    required this.callId,
    required dynamic operation,
    required this.startedAt,
    this.description,
  }) : _operation = operation;

  /// Whether this call has been ended or failed.
  bool get isCompleted => _isCompleted;

  /// End the call successfully with an optional result.
  ///
  /// This pops the stack frame, logs the completion, and triggers
  /// the onCompletion callback if provided.
  ///
  /// Throws [StateError] if the call has already been completed.
  Future<void> end([T? result]) async {
    if (_isCompleted) {
      throw StateError('Call $callId has already been completed');
    }
    _isCompleted = true;
    await (_operation as dynamic).endCallInternal$(callId: callId, result: result);
  }

  /// Fail the call with an error.
  ///
  /// This pops the stack frame, logs the failure, triggers cleanup,
  /// and may trigger operation failure if [failOnCrash] was true.
  ///
  /// Throws [StateError] if the call has already been completed.
  Future<void> fail(Object error, [StackTrace? stackTrace]) async {
    if (_isCompleted) {
      throw StateError('Call $callId has already been completed');
    }
    _isCompleted = true;
    await (_operation as dynamic).failCallInternal$(
      callId: callId,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  String toString() => 'Call(callId: $callId, completed: $_isCompleted)';
}

// ═══════════════════════════════════════════════════════════════════
// SPAWNED CALL CLASS
// ═══════════════════════════════════════════════════════════════════

/// Represents a call that was spawned asynchronously.
///
/// This class tracks the state and result of a spawned call, and provides
/// control methods to cancel or kill the call.
///
/// ## Control Methods
/// 
/// - [cancel] - Signals cancellation to cooperative work (sets [isCancelled])
/// - [kill] - Forcefully terminates associated process
/// - [await] - Waits for the call to complete and returns the result
///
/// ## Example
/// ```dart
/// final call = operation.execStdioWorker<Map>(
///   executable: 'dart',
///   arguments: ['run', 'worker.dart'],
/// );
///
/// // Check for cancellation in the worker
/// if (call.isCancelled) return null;
///
/// // Or kill the process
/// call.kill();
///
/// // Wait for result
/// final result = await call.await();
/// ```
class SpawnedCall<T> {
  /// The call ID generated by the ledger.
  final String callId;

  /// Optional description of this call.
  final String? description;

  /// Internal completer for waiting on this call.
  final Completer<void> _completer = Completer<void>();

  /// Whether the call succeeded.
  bool _isSuccess = false;

  /// Whether cancellation has been requested.
  bool _isCancelled = false;

  /// The result of the call.
  T? _result;

  /// The error if the call failed.
  Object? _error;

  /// The stack trace if the call failed.
  StackTrace? _stackTrace;

  /// Optional process reference for process-based workers.
  Process? _process;

  /// Callback to be invoked when cancel() is called.
  Future<void> Function()? _onCancel;

  SpawnedCall({
    required this.callId,
    this.description,
  });

  /// Whether the call has completed (successfully or failed).
  bool get isCompleted => _completer.isCompleted;

  /// Whether the call completed successfully (not crashed).
  bool get isSuccess => _isSuccess;

  /// Whether the call failed/crashed.
  bool get isFailed => !_isSuccess && isCompleted;

  /// Whether cancellation has been requested.
  /// 
  /// Work functions should check this periodically and exit gracefully
  /// when true.
  bool get isCancelled => _isCancelled;

  /// The result of the call (only valid if isSuccess is true).
  /// Throws StateError if accessed before completion or if call failed.
  T get result {
    if (!isCompleted) throw StateError('Call not yet completed');
    if (!_isSuccess) throw StateError('Call failed, no result available');
    return _result as T;
  }

  /// The result if successful, null otherwise (safe accessor).
  /// Does not throw - returns null if not completed or failed.
  T? get resultOrNull => isSuccess ? _result : null;

  /// The result if successful, or the provided default value.
  /// Does not throw - returns defaultValue if not completed or failed.
  T resultOr(T defaultValue) => isSuccess ? (_result ?? defaultValue) : defaultValue;

  /// Wait for this call to complete.
  Future<void> get future => _completer.future;

  /// The error if the call failed (null if success or not completed).
  Object? get error => _error;

  /// The stack trace if the call failed (null if success or not completed).
  StackTrace? get stackTrace => _stackTrace;

  /// Request cancellation of this call.
  /// 
  /// This sets [isCancelled] to true and invokes the cancellation callback
  /// if one was registered. Work functions should check [isCancelled]
  /// periodically and exit gracefully.
  ///
  /// Note: This does not forcefully stop execution. Use [kill] to
  /// forcefully terminate an associated process.
  Future<void> cancel() async {
    if (_isCancelled || isCompleted) return;
    _isCancelled = true;
    await _onCancel?.call();
  }

  /// Forcefully terminate the associated process.
  ///
  /// This immediately kills the process (SIGTERM on Unix, terminate on Windows).
  /// Use [cancel] for graceful shutdown when possible.
  ///
  /// Returns true if a process was killed, false if no process was attached.
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (_process == null || isCompleted) return false;
    return _process!.kill(signal);
  }

  /// Wait for the call to complete and return the result.
  ///
  /// Throws [StateError] if the call failed.
  /// This is an alias for `await future; return result;`
  Future<T> await_() async {
    await _completer.future;
    return result;
  }

  /// Complete this call successfully with the given result.
  void complete(T result) {
    if (_completer.isCompleted) return;
    _result = result;
    _isSuccess = true;
    _completer.complete();
  }

  /// Fail this call with the given error.
  void fail(Object error, [StackTrace? stackTrace]) {
    if (_completer.isCompleted) return;
    _error = error;
    _stackTrace = stackTrace;
    _isSuccess = false;
    _completer.complete();
  }

  /// Set the process reference for process-based workers.
  /// 
  /// **Note:** This is for internal use by the ledger API.
  void setProcess$(Process process) {
    _process = process;
  }

  /// Set the cancellation callback.
  /// 
  /// **Note:** This is for internal use by the ledger API.
  void setOnCancel$(Future<void> Function() onCancel) {
    _onCancel = onCancel;
  }

  @override
  String toString() => 'SpawnedCall<$T>(callId: $callId, completed: $isCompleted, success: $isSuccess, cancelled: $_isCancelled)';
}

// ═══════════════════════════════════════════════════════════════════
// SYNC RESULT CLASS
// ═══════════════════════════════════════════════════════════════════

/// Result of a [Operation.sync] call.
///
/// Contains information about which calls succeeded, failed, or have unknown state.
class SyncResult {
  /// List of calls that completed successfully before sync returned.
  final List<SpawnedCall> successfulCalls;

  /// List of calls that failed/crashed before sync returned.
  final List<SpawnedCall> failedCalls;

  /// List of calls whose outcome is unknown (operation failed before they completed).
  /// These calls may still be running, may complete, or may crash.
  final List<SpawnedCall> unknownCalls;

  /// Whether the operation itself failed (not just individual calls).
  final bool operationFailed;

  SyncResult({
    this.successfulCalls = const [],
    this.failedCalls = const [],
    this.unknownCalls = const [],
    this.operationFailed = false,
  });

  /// Whether all calls completed successfully (no failures, no unknowns).
  bool get allSucceeded => failedCalls.isEmpty && unknownCalls.isEmpty && !operationFailed;

  /// Whether any calls failed.
  bool get hasFailed => failedCalls.isNotEmpty;

  /// Whether all tracked calls have a known outcome (no unknowns).
  bool get allResolved => unknownCalls.isEmpty;

  @override
  String toString() =>
      'SyncResult(success: ${successfulCalls.length}, failed: ${failedCalls.length}, unknown: ${unknownCalls.length}, operationFailed: $operationFailed)';
}

// ═══════════════════════════════════════════════════════════════════
// OPERATION HELPER CLASS
// ═══════════════════════════════════════════════════════════════════

/// Static helper methods for common operation patterns.
///
/// Provides utilities for polling files, waiting for conditions,
/// and other common async patterns used with the ledger API.
class OperationHelper {
  OperationHelper._(); // Prevent instantiation

  /// Creates a wait function that polls for a file to appear.
  ///
  /// Returns a function suitable for use with [Operation.waitForCompletion].
  ///
  /// Parameters:
  /// - [path] - Absolute path to the file to wait for
  /// - [delete] - Whether to delete the file after reading (default: `false`)
  /// - [deserializer] - Optional function to parse file content
  /// - [pollInterval] - How often to check for file (default: 100ms)
  /// - [timeout] - Optional timeout; throws [TimeoutException] if exceeded
  ///
  /// If no deserializer is provided:
  /// - If `T` is `String`, returns raw content
  /// - If `T` is `Map<String, dynamic>`, uses `jsonDecode(content)`
  static Future<T> Function() pollFile<T>({
    required String path,
    bool delete = false,
    T Function(String content)? deserializer,
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    return () async {
      final stopwatch = timeout != null ? (Stopwatch()..start()) : null;

      while (true) {
        final file = File(path);
        if (await file.exists()) {
          final content = await file.readAsString();
          if (delete) {
            await file.delete();
          }

          if (deserializer != null) {
            return deserializer(content);
          }

          // Default handling for common types
          if (T == String) {
            return content as T;
          }
          if (T == dynamic || T.toString().contains('Map')) {
            return jsonDecode(content) as T;
          }
          return content as T;
        }

        if (stopwatch != null && timeout != null && stopwatch.elapsed > timeout) {
          throw TimeoutException('File $path did not appear within $timeout');
        }

        await Future.delayed(pollInterval);
      }
    };
  }

  /// Creates a wait function that polls until a condition returns non-null.
  ///
  /// Parameters:
  /// - [check] - Function that returns `null` to continue polling, or a value to complete
  /// - [pollInterval] - How often to check (default: 100ms)
  /// - [timeout] - Optional timeout
  static Future<T> Function() pollUntil<T>({
    required Future<T?> Function() check,
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    return () async {
      final stopwatch = timeout != null ? (Stopwatch()..start()) : null;

      while (true) {
        final result = await check();
        if (result != null) {
          return result;
        }

        if (stopwatch != null && timeout != null && stopwatch.elapsed > timeout) {
          throw TimeoutException('Condition not met within $timeout');
        }

        await Future.delayed(pollInterval);
      }
    };
  }

  /// Creates a wait function that waits for multiple files to appear.
  ///
  /// All files must appear before returning. Returns contents in the same
  /// order as the input paths.
  ///
  /// Parameters:
  /// - [paths] - List of absolute paths to wait for
  /// - [delete] - Whether to delete files after reading (default: `false`)
  /// - [deserializer] - Optional function to parse each file's content
  /// - [pollInterval] - How often to check for files (default: 100ms)
  /// - [timeout] - Optional timeout for all files to appear
  static Future<List<T>> Function() pollFiles<T>({
    required List<String> paths,
    bool delete = false,
    T Function(String content)? deserializer,
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    return () async {
      final stopwatch = timeout != null ? (Stopwatch()..start()) : null;
      final results = <String, T>{};

      while (results.length < paths.length) {
        for (final path in paths) {
          if (results.containsKey(path)) continue;

          final file = File(path);
          if (await file.exists()) {
            final content = await file.readAsString();
            if (delete) {
              await file.delete();
            }

            if (deserializer != null) {
              results[path] = deserializer(content);
            } else if (T == String) {
              results[path] = content as T;
            } else if (T == dynamic || T.toString().contains('Map')) {
              results[path] = jsonDecode(content) as T;
            } else {
              results[path] = content as T;
            }
          }
        }

        if (results.length < paths.length) {
          if (stopwatch != null && timeout != null && stopwatch.elapsed > timeout) {
            final missing = paths.where((p) => !results.containsKey(p)).toList();
            throw TimeoutException('Files did not appear within $timeout: $missing');
          }
          await Future.delayed(pollInterval);
        }
      }

      // Return in same order as input paths
      return paths.map((p) => results[p]!).toList();
    };
  }
}
