import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../local_ledger/file_ledger.dart';
import 'call_callback.dart';

// Re-export callback types
export 'call_callback.dart';

/// Heartbeat error types.
enum HeartbeatErrorType {
  ledgerNotFound,
  lockFailed,
  abortFlagSet,
  heartbeatStale,
  ioError,
}

/// Heartbeat error with details.
class HeartbeatError {
  final HeartbeatErrorType type;
  final String message;
  final Object? cause;

  const HeartbeatError({
    required this.type,
    required this.message,
    this.cause,
  });

  @override
  String toString() => 'HeartbeatError($type): $message';
}

/// Callback for heartbeat errors.
typedef HeartbeatErrorCallback = void Function(
  Operation operation,
  HeartbeatError error,
);

/// Callback for successful heartbeat.
typedef HeartbeatSuccessCallback = void Function(
  Operation operation,
  HeartbeatResult result,
);

/// Tracks a call in progress with its callback.
class _ActiveCall {
  final String callId;
  final CallCallback callback;
  final DateTime startedAt;
  final String? description;
  final Completer<void> completer;
  final bool isSpawned;
  final bool failOnCrash;

  _ActiveCall({
    required this.callId,
    required this.callback,
    required this.startedAt,
    this.description,
    required this.isSpawned,
    this.failOnCrash = true,
  }) : completer = Completer<void>();
}

// ═══════════════════════════════════════════════════════════════
// OPERATION CLASS
// ═══════════════════════════════════════════════════════════════

/// Represents a running operation.
///
/// Each participant gets their own Operation object to interact with
/// the shared operation file and log.
class Operation {
  final Ledger _ledger;
  final String operationId;
  final String participantId;
  final int pid;
  final bool isInitiator;

  /// When this operation was started.
  ///
  /// For initiators, this is when the operation was created.
  /// For participants, this is when they joined the operation.
  /// This field allows easy calculation of elapsed time without a Stopwatch,
  /// and can be passed to spawned processes for consistent timeline logging.
  final DateTime startTime;

  /// Cached operation data.
  LedgerData? _cachedData;

  /// Timestamp of last change to the operation file.
  DateTime? _lastChangeTimestamp;

  /// Heartbeat timer for this participant.
  Timer? _heartbeatTimer;

  /// Whether this participant is aborted.
  bool _isAborted = false;

  /// Staleness threshold in milliseconds for detecting crashed participants.
  /// If a participant's heartbeat is older than this, it's considered stale.
  int stalenessThresholdMs = 10000;

  /// Callbacks for heartbeat events.
  HeartbeatErrorCallback? onHeartbeatError;
  HeartbeatSuccessCallback? onHeartbeatSuccess;

  /// Completer that signals abort.
  final Completer<void> _abortCompleter = Completer<void>();

  /// Completer that signals operation failure (for waitForCompletion).
  final Completer<OperationFailedInfo> _failureCompleter =
      Completer<OperationFailedInfo>();

  /// Active calls tracked by this participant.
  final Map<String, _ActiveCall> _activeCalls = {};

  /// Counter for generating unique call IDs.
  int _callCounter = 0;

  /// Random for generating unique call IDs.
  final _random = Random();

  Operation._({
    required Ledger ledger,
    required this.operationId,
    required this.participantId,
    required this.pid,
    required this.isInitiator,
    required this.startTime,
  }) : _ledger = ledger;

  /// Get the cached operation data.
  LedgerData? get cachedData => _cachedData;

  /// Get the last change timestamp.
  DateTime? get lastChangeTimestamp => _lastChangeTimestamp;

  /// Whether this participant is aborted.
  bool get isAborted => _isAborted;

  /// Future that completes when abort is signaled.
  Future<void> get onAbort => _abortCompleter.future;

  /// Future that completes when operation fails.
  Future<OperationFailedInfo> get onFailure => _failureCompleter.future;

  /// Get the current elapsed time formatted as "SSS.mmm" (seconds.milliseconds).
  String get elapsedFormatted {
    final duration = elapsedDuration;
    final seconds = duration.inSeconds;
    final millis = duration.inMilliseconds % 1000;
    return '${seconds.toString().padLeft(3, '0')}.${millis.toString().padLeft(3, '0')}';
  }

  /// Get the elapsed duration since operation start.
  ///
  /// Uses [startTime] to calculate the elapsed time without needing a Stopwatch.
  Duration get elapsedDuration => DateTime.now().difference(startTime);

  /// Get the start time formatted as ISO 8601 string.
  ///
  /// Useful for passing to spawned processes for consistent timeline logging.
  String get startTimeIso => startTime.toIso8601String();

  /// Get the start time as milliseconds since epoch.
  ///
  /// Useful for passing to spawned processes via command-line arguments.
  int get startTimeMs => startTime.millisecondsSinceEpoch;

  // ─────────────────────────────────────────────────────────────
  // Call ID generation
  // ─────────────────────────────────────────────────────────────

  /// Generate a unique call ID.
  String _generateCallId() {
    _callCounter++;
    final randomPart =
        _random.nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
    return 'call_${participantId}_${_callCounter}_$randomPart';
  }

  // ─────────────────────────────────────────────────────────────
  // Cache management
  // ─────────────────────────────────────────────────────────────

  /// Refresh the cached data from the operation file.
  Future<void> _refreshCache() async {
    _cachedData = await _ledger._readOperation(operationId);
    if (_cachedData != null) {
      _lastChangeTimestamp = DateTime.now();
    }
  }

  /// Update the cache after a modification.
  void _updateCache(LedgerData data) {
    _cachedData = data;
    _lastChangeTimestamp = DateTime.now();
  }

  // ─────────────────────────────────────────────────────────────
  // Logging
  // ─────────────────────────────────────────────────────────────

  /// Write an entry to the operation log.
  Future<void> log(String message, {LogLevel level = LogLevel.info}) async {
    final timestamp = DateTime.now().toIso8601String();
    final line = '$timestamp [${level.name}] $message';
    await _ledger._appendLog(operationId, line);
  }

  /// Write an entry to the debug log (INTERNAL USE ONLY).
  ///
  /// This method is for internal ledger debugging and testing.
  /// Application code should use [log] instead.
  Future<void> debugLog(String message) async {
    await _ledger._appendDebugLog(operationId, message);
  }

  /// Log a formatted message with timestamp and participant.
  Future<void> logMessage({
    required int depth,
    required String message,
  }) async {
    final indent = '    ' * depth;
    final line = '$elapsedFormatted | $indent[$participantId] $message';
    await log(line);
    print(line);
  }

  // ─────────────────────────────────────────────────────────────
  // Call management (NEW API per specification)
  // ─────────────────────────────────────────────────────────────

  /// Start a call and return a [Call<T>] object for lifecycle management.
  ///
  /// The returned [Call<T>] object provides [Call.end] and [Call.fail] methods
  /// for completing the call, eliminating the need to track callIds manually.
  ///
  /// If [failOnCrash] is true (default), a crash in this call will fail the
  /// entire operation. If false, the crash is contained to this call only.
  ///
  /// Example:
  /// ```dart
  /// final call = await operation.startCall<int>(
  ///   callback: CallCallback(onCleanup: () async => releaseResources()),
  /// );
  /// try {
  ///   final result = await performWork();
  ///   await call.end(result);  // End successfully with result
  /// } catch (e, st) {
  ///   await call.fail(e, st);  // Fail with error
  /// }
  /// ```
  Future<Call<T>> startCall<T>({
    CallCallback<T>? callback,
    String? description,
    bool failOnCrash = true,
  }) async {
    final callId = _generateCallId();
    final now = DateTime.now();

    // Track locally
    _activeCalls[callId] = _ActiveCall(
      callId: callId,
      callback: callback ?? CallCallback<T>(),
      startedAt: now,
      description: description,
      isSpawned: false,
      failOnCrash: failOnCrash,
    );

    // Push stack frame
    final updated = await _ledger._modifyOperation(
      operationId: operationId,
      elapsedFormatted: elapsedFormatted,
      updater: (data) {
        data.stack.add(StackFrame(
          participantId: participantId,
          callId: callId,
          pid: pid,
          startTime: now,
          lastHeartbeat: now,
          description: description,
          failOnCrash: failOnCrash,
        ));
        data.lastHeartbeat = now;
        return data;
      },
    );
    if (updated != null) _updateCache(updated);

    // Log the call start
    await log('CALL_STARTED callId=$callId participant=$participantId');

    return Call<T>.internal(
      callId: callId,
      operation: this,
      startedAt: now,
      description: description,
    );
  }

  /// End a call successfully.
  ///
  /// Prefer using [Call.end] on the returned Call object instead.
  /// This method is kept for backward compatibility.
  @Deprecated('Use Call.end() instead')
  Future<void> endCall({required String callId}) async {
    await endCallInternal$(callId: callId, result: null);
  }

  /// Internal method to end a call, called by Call.end().
  /// 
  /// **Note:** This method is for internal use by the ledger API.
  /// Users should call [Call.end] instead.
  Future<void> endCallInternal$<T>({
    required String callId,
    T? result,
  }) async {
    final activeCall = _activeCalls.remove(callId);
    if (activeCall == null) {
      throw StateError('No active call with ID: $callId');
    }

    final now = DateTime.now();

    // Pop stack frame
    final updated = await _ledger._modifyOperation(
      operationId: operationId,
      elapsedFormatted: elapsedFormatted,
      updater: (data) {
        final index = data.stack.lastIndexWhere((f) => f.callId == callId);
        if (index >= 0) {
          data.stack.removeAt(index);
        }
        data.lastHeartbeat = now;
        return data;
      },
    );
    if (updated != null) _updateCache(updated);

    // Log the call end
    final duration = now.difference(activeCall.startedAt);
    await log(
        'CALL_ENDED callId=$callId duration=${duration.inMilliseconds}ms');

    // Call onCompletion callback if result provided
    if (result != null && activeCall.callback is CallCallback<T>) {
      final callback = activeCall.callback as CallCallback<T>;
      await callback.onCompletion?.call(result);
    }

    // Complete the completer for spawned calls
    if (!activeCall.completer.isCompleted) {
      activeCall.completer.complete();
    }
  }

  /// Fail a call due to an error.
  ///
  /// Prefer using [Call.fail] on the returned Call object instead.
  /// This method is kept for backward compatibility.
  ///
  /// This removes the stack frame, logs the failure, and calls cleanup.
  /// If [failOnCrash] was true for this call, it may trigger operation failure.
  @Deprecated('Use Call.fail() instead')
  Future<void> failCall({
    required String callId,
    required Object error,
    StackTrace? stackTrace,
  }) async {
    await failCallInternal$(callId: callId, error: error, stackTrace: stackTrace);
  }

  /// Internal method to fail a call, called by Call.fail().
  /// 
  /// **Note:** This method is for internal use by the ledger API.
  /// Users should call [Call.fail] instead.
  Future<void> failCallInternal$({
    required String callId,
    required Object error,
    StackTrace? stackTrace,
  }) async {
    final activeCall = _activeCalls.remove(callId);
    if (activeCall == null) {
      throw StateError('No active call with ID: $callId');
    }

    final now = DateTime.now();

    // Pop stack frame
    final updated = await _ledger._modifyOperation(
      operationId: operationId,
      elapsedFormatted: elapsedFormatted,
      updater: (data) {
        final index = data.stack.lastIndexWhere((f) => f.callId == callId);
        if (index >= 0) {
          data.stack.removeAt(index);
        }
        data.lastHeartbeat = now;
        return data;
      },
    );
    if (updated != null) _updateCache(updated);

    // Log the call failure
    final duration = now.difference(activeCall.startedAt);
    await log(
        'CALL_FAILED callId=$callId duration=${duration.inMilliseconds}ms error=$error',
        level: LogLevel.error);

    // Call cleanup callback
    await activeCall.callback.onCleanup?.call();

    // If this call had failOnCrash=true, signal operation failure
    if (activeCall.failOnCrash) {
      _signalFailure(OperationFailedInfo(
        operationId: operationId,
        failedAt: now,
        reason: 'Call $callId failed: $error',
        crashedCallIds: [callId],
      ));
    }

    // Complete the completer
    if (!activeCall.completer.isCompleted) {
      activeCall.completer.complete();
    }
  }

  /// Execute work while monitoring operation state.
  ///
  /// If the operation enters cleanup/failed state, the work is interrupted.
  /// Returns the result of the work function.
  ///
  /// Parameters:
  /// - [work] - Async function that produces the result
  /// - [onOperationFailed] - Called if operation fails before work completes
  /// - [onError] - Called if work throws an error; can return a fallback value
  ///
  /// Example:
  /// ```dart
  /// final result = await operation.waitForCompletion<int>(
  ///   work: () async => await computeValue(),
  ///   onOperationFailed: (info) async => print('Operation failed!'),
  ///   onError: (error, stackTrace) async {
  ///     print('Error: $error');
  ///     return -1; // Fallback value
  ///   },
  /// );
  /// ```
  Future<T> waitForCompletion<T>(
    Future<T> Function() work, {
    Future<void> Function(OperationFailedInfo info)? onOperationFailed,
    Future<T> Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    try {
      // Race between work completion and operation failure
      return await Future.any<T>([
        work(),
        onFailure.then<T>((info) async {
          await onOperationFailed?.call(info);
          throw OperationFailedException(info);
        }),
      ]);
    } catch (e, st) {
      if (onError != null && e is! OperationFailedException) {
        return await onError(e, st);
      }
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Spawned Call API
  // ─────────────────────────────────────────────────────────────

  /// Tracking for spawned calls.
  final Map<String, SpawnedCall> _spawnedCalls = {};

  /// Spawn a call that runs asynchronously.
  ///
  /// Returns [SpawnedCall<T>] immediately. The call executes `work` asynchronously
  /// and manages its own lifecycle (no need to call endCall).
  ///
  /// Parameters:
  /// - [work] - Async function that produces the result
  /// - [callback] - Optional callbacks for completion, crash, cleanup, and operation failure
  /// - [description] - Optional description for logging
  /// - [failOnCrash] - If true (default), a crash fails the entire operation
  ///
  /// Example:
  /// ```dart
  /// final call = operation.spawnCall<int>(
  ///   work: () async => await computeExpensiveValue(),
  ///   callback: CallCallback(
  ///     onCompletion: (result) async => print('Got: $result'),
  ///     onCallCrashed: () async => 0, // Fallback value
  ///     onOperationFailed: (info) async => print('Op failed!'),
  ///   ),
  /// );
  /// 
  /// // Access callId immediately
  /// print('Call started: ${call.callId}');
  /// 
  /// // Wait for result later
  /// await call.future;
  /// print('Result: ${call.result}');
  /// ```
  SpawnedCall<T> spawnCall<T>({
    Future<T> Function()? work,
    Future<T> Function(SpawnedCall<T> call)? workWithCall,
    CallCallback<T>? callback,
    String? description,
    bool failOnCrash = true,
  }) {
    // Either work or workWithCall must be provided
    if (work == null && workWithCall == null) {
      throw ArgumentError('Either work or workWithCall must be provided');
    }
    
    final callId = _generateCallId();
    final now = DateTime.now();

    // Create SpawnedCall instance
    final spawnedCall = SpawnedCall<T>(
      callId: callId,
      description: description,
    );
    _spawnedCalls[callId] = spawnedCall;

    // Create internal callback for cleanup
    final internalCallback = CallCallback<dynamic>(
      onCleanup: callback?.onCleanup,
    );

    // Track locally
    _activeCalls[callId] = _ActiveCall(
      callId: callId,
      callback: internalCallback,
      startedAt: now,
      description: description,
      isSpawned: true,
      failOnCrash: failOnCrash,
    );

    // Create the actual work function
    final actualWork = work ?? (() => workWithCall!(spawnedCall));

    // Execute asynchronously
    _runSpawnedCall<T>(
      callId: callId,
      work: actualWork,
      spawnedCall: spawnedCall,
      callback: callback,
      failOnCrash: failOnCrash,
    );

    return spawnedCall;
  }

  /// Internal method to run a spawned call.
  Future<void> _runSpawnedCall<T>({
    required String callId,
    required Future<T> Function() work,
    required SpawnedCall<T> spawnedCall,
    CallCallback<T>? callback,
    required bool failOnCrash,
  }) async {
    final now = DateTime.now();

    // Push stack frame
    final updated = await _ledger._modifyOperation(
      operationId: operationId,
      elapsedFormatted: elapsedFormatted,
      updater: (data) {
        data.stack.add(StackFrame(
          participantId: participantId,
          callId: callId,
          pid: pid,
          startTime: now,
          lastHeartbeat: now,
          description: spawnedCall.description,
          failOnCrash: failOnCrash,
        ));
        data.lastHeartbeat = now;
        return data;
      },
    );
    if (updated != null) _updateCache(updated);

    await log('CALL_SPAWNED callId=$callId participant=$participantId');

    // Monitor for operation failure
    onFailure.then((info) async {
      await callback?.onOperationFailed?.call(info);
    });

    try {
      // Execute work
      final result = await work();

      // Success - store result
      spawnedCall.complete(result);

      // Remove stack frame
      await _ledger._modifyOperation(
        operationId: operationId,
        elapsedFormatted: elapsedFormatted,
        updater: (data) {
          final index = data.stack.lastIndexWhere((f) => f.callId == callId);
          if (index >= 0) data.stack.removeAt(index);
          data.lastHeartbeat = DateTime.now();
          return data;
        },
      );

      await log('CALL_COMPLETED callId=$callId');

      // Call onCompletion callback
      await callback?.onCompletion?.call(result);

      // Cleanup active call tracking
      final activeCall = _activeCalls.remove(callId);
      if (activeCall != null && !activeCall.completer.isCompleted) {
        activeCall.completer.complete();
      }
    } catch (e, st) {
      // Failure - try to get fallback from onCallCrashed
      T? fallbackResult;
      if (callback?.onCallCrashed != null) {
        try {
          fallbackResult = await callback!.onCallCrashed!();
          if (fallbackResult != null) {
            // Got a fallback, treat as success
            spawnedCall.complete(fallbackResult);
          } else {
            spawnedCall.fail(e, st);
          }
        } catch (_) {
          spawnedCall.fail(e, st);
        }
      } else {
        spawnedCall.fail(e, st);
      }

      // Remove stack frame
      await _ledger._modifyOperation(
        operationId: operationId,
        elapsedFormatted: elapsedFormatted,
        updater: (data) {
          final index = data.stack.lastIndexWhere((f) => f.callId == callId);
          if (index >= 0) data.stack.removeAt(index);
          data.lastHeartbeat = DateTime.now();
          return data;
        },
      );

      await log('CALL_FAILED callId=$callId error=$e', level: LogLevel.error);

      // Cleanup active call tracking
      final activeCall = _activeCalls.remove(callId);
      if (activeCall != null && !activeCall.completer.isCompleted) {
        activeCall.completer.complete();
      }

      // If failOnCrash is true and we didn't get a fallback, signal operation failure
      if (failOnCrash && fallbackResult == null) {
        _signalFailure(OperationFailedInfo(
          operationId: operationId,
          failedAt: DateTime.now(),
          reason: 'Call $callId failed: $e',
          crashedCallIds: [callId],
        ));
      }
    }
  }

  /// Wait for spawned calls to complete and get a SyncResult.
  ///
  /// Waits for all specified calls to complete and returns status.
  /// 
  /// Note: Individual call crash handling is done via the onCallCrashed callback
  /// provided to spawnCall() at spawn time. This method only notifies about
  /// operation-level failures.
  Future<SyncResult> sync(
    List<SpawnedCall> calls, {
    Future<void> Function(OperationFailedInfo info)? onOperationFailed,
    Future<void> Function()? onCompletion,
  }) async {
    if (calls.isEmpty) {
      return SyncResult();
    }

    final List<SpawnedCall> successful = [];
    final List<SpawnedCall> failed = [];
    final List<SpawnedCall> unknown = [];

    // Wait for all calls or operation failure
    bool operationDidFail = false;

    try {
      await Future.any([
        Future.wait(calls.map((c) => c.future)),
        onFailure.then((info) async {
          operationDidFail = true;
          await onOperationFailed?.call(info);
        }),
      ]);
    } catch (_) {
      // Ignore - we'll categorize below
    }

    // Categorize results
    for (final call in calls) {
      if (call.isCompleted) {
        if (call.isSuccess) {
          successful.add(call);
        } else {
          failed.add(call);
          // Note: Individual crash callbacks were handled at spawn time via onCallCrashed
        }
      } else {
        unknown.add(call);
      }
    }

    // Call completion callback
    await onCompletion?.call();

    return SyncResult(
      successfulCalls: successful,
      failedCalls: failed,
      unknownCalls: unknown,
      operationFailed: operationDidFail,
    );
  }

  /// Await a single spawned call to complete.
  ///
  /// This is a convenience method equivalent to `syncTyped([call], ...)`.
  /// Use this when you have a single spawned call that you want to wait for.
  ///
  /// Returns a [SyncResult] with the call categorized as successful, failed,
  /// or unknown (if operation failed before the call completed).
  ///
  /// Note: Individual call crash handling is done via the onCallCrashed callback
  /// provided to spawnTyped() at spawn time. This method only notifies about
  /// operation-level failures.
  /// 
  /// For direct result access, use [SpawnedCall.await_] which returns `T`
  /// directly or throws on failure.
  /// 
  /// Example:
  /// ```dart
  /// final call = operation.spawnCall<int>(
  ///   work: () async => 42,
  /// );
  /// 
  /// final result = await operation.awaitCall(call);
  /// if (result.allSucceeded) {
  ///   print('Result: ${call.result}');
  /// }
  /// 
  /// // Or use the direct await pattern:
  /// try {
  ///   final value = await call.await_();
  ///   print('Got: $value');
  /// } catch (e) {
  ///   print('Failed: $e');
  /// }
  /// ```
  Future<SyncResult> awaitCall<T>(
    SpawnedCall<T> call, {
    Future<void> Function(OperationFailedInfo info)? onOperationFailed,
    Future<void> Function()? onCompletion,
  }) {
    return sync(
      [call],
      onOperationFailed: onOperationFailed,
      onCompletion: onCompletion,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Exec Helper Methods (convenience API for process spawning)
  // ─────────────────────────────────────────────────────────────

  /// Execute a file-result worker process.
  ///
  /// Spawns a process that writes its result to a file, then polls for that
  /// file and returns the parsed result.
  ///
  /// This is a convenience method that combines process spawning with file
  /// polling using [OperationHelper.pollFile].
  ///
  /// Parameters:
  /// - [executable] - The executable to run (e.g., 'dart')
  /// - [arguments] - Command-line arguments
  /// - [resultFilePath] - Path where the worker will write its result
  /// - [workingDirectory] - Optional working directory for the process
  /// - [description] - Optional description for logging
  /// - [deserializer] - Optional function to parse file content
  /// - [deleteResultFile] - Whether to delete the result file after reading (default: true)
  /// - [pollInterval] - How often to check for the result file (default: 100ms)
  /// - [timeout] - Optional timeout for the entire operation
  /// - [onStdout] - Optional callback for stdout lines
  /// - [onStderr] - Optional callback for stderr lines
  /// - [onExit] - Optional callback when process exits (receives exit code)
  /// - [failOnCrash] - Whether crash should fail entire operation (default: true)
  /// - [callback] - Optional callbacks for completion, crash, cleanup, and operation failure
  ///
  /// Returns a [SpawnedCall<T>] immediately. The call executes asynchronously.
  /// Access `callId` immediately, await `future` for results.
  /// 
  /// Example:
  /// ```dart
  /// final worker = operation.execFileResultWorker<Map>(
  ///   executable: 'dart',
  ///   arguments: ['run', 'worker.dart', '--output', resultPath],
  ///   resultFilePath: resultPath,
  ///   onExit: (exitCode) => print('Worker exited with code: $exitCode'),
  /// );
  /// print('Started: ${worker.callId}');
  /// await worker.future;
  /// if (worker.isSuccess) {
  ///   print('Result: ${worker.result}');
  /// }
  /// ```
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
  }) {
    return spawnCall<T>(
      workWithCall: (call) async {
        // Start the process
        final process = await Process.start(
          executable,
          arguments,
          workingDirectory: workingDirectory ?? Directory.current.path,
        );
        
        // Attach process to SpawnedCall for kill/cancel support
        call.setProcess$(process);

        // Handle stdout
        process.stdout.transform(utf8.decoder).listen((data) {
          if (onStdout != null) {
            for (final line in data.split('\n')) {
              if (line.isNotEmpty) onStdout(line);
            }
          }
        });

        // Handle stderr
        process.stderr.transform(utf8.decoder).listen((data) {
          if (onStderr != null) {
            for (final line in data.split('\n')) {
              if (line.isNotEmpty) onStderr(line);
            }
          }
        });

        // Wait for result file using pollFile
        final result = await OperationHelper.pollFile<T>(
          path: resultFilePath,
          delete: deleteResultFile,
          deserializer: deserializer,
          pollInterval: pollInterval,
          timeout: timeout,
        )();

        // Wait for process to exit
        final exitCode = await process.exitCode;
        onExit?.call(exitCode);

        return result;
      },
      description: description ?? 'File result worker',
      failOnCrash: failOnCrash,
      callback: callback,
    );
  }

  /// Execute a stdout-result worker process.
  ///
  /// Spawns a process that outputs its result to stdout as JSON, then parses
  /// and returns the result.
  ///
  /// This is a convenience method for processes that communicate their result
  /// via stdout (common for CLI tools and simple workers).
  ///
  /// ## Worker Requirements
  ///
  /// The worker process MUST:
  /// - Output ONLY the JSON result to stdout (no other content)
  /// - Use stderr for all status messages, progress, and debugging
  /// - Exit with code 0 on success
  ///
  /// Example worker implementation:
  /// ```dart
  /// void main(List<String> args) async {
  ///   // Parse parameters from args
  ///   final param1 = args.firstWhere((a) => a.startsWith('--param1=')).split('=')[1];
  ///   
  ///   // All status messages go to stderr
  ///   stderr.writeln('Processing with param: $param1');
  ///   
  ///   // Do work...
  ///   await Future.delayed(Duration(seconds: 2));
  ///   
  ///   // ONLY the result goes to stdout (as JSON)
  ///   final result = {'status': 'success', 'value': param1};
  ///   stdout.write(jsonEncode(result));  // No newline needed
  ///   
  ///   stderr.writeln('Done!');
  /// }
  /// ```
  ///
  /// ## Parameters
  /// - [executable] - The executable to run (e.g., 'dart')
  /// - [arguments] - Command-line arguments (including parameters for the worker)
  /// - [workingDirectory] - Optional working directory for the process
  /// - [description] - Optional description for logging
  /// - [deserializer] - Optional function to parse stdout content (default: json.decode)
  /// - [onStderr] - Optional callback for stderr lines (for monitoring worker progress)
  /// - [onExit] - Optional callback when process exits (receives exit code)
  /// - [timeout] - Optional timeout for the entire operation
  /// - [failOnCrash] - Whether crash should fail entire operation (default: true)
  /// - [callback] - Optional callbacks for completion, crash, cleanup, and operation failure
  ///
  /// Returns a [SpawnedCall<T>] immediately. The call executes asynchronously.
  /// Access `callId` immediately, await `future` for results.
  /// 
  /// ## Example
  /// ```dart
  /// final worker = operation.execStdioWorker<Map<String, dynamic>>(
  ///   executable: 'dart',
  ///   arguments: [
  ///     'run', 'worker.dart',
  ///     '--param1=hello',
  ///     '--param2=world',
  ///   ],
  ///   onStderr: (line) => print('[Worker] $line'),
  ///   onExit: (exitCode) => print('Exited: $exitCode'),
  /// );
  /// await worker.future;
  /// if (worker.isSuccess) {
  ///   print('Result: ${worker.result['combined_result']}');
  /// }
  /// ```
  SpawnedCall<T> execStdioWorker<T>({
    required String executable,
    required List<String> arguments,
    String? workingDirectory,
    String? description,
    T Function(String content)? deserializer,
    void Function(String line)? onStderr,
    void Function(int exitCode)? onExit,
    Duration? timeout,
    bool failOnCrash = true,
    CallCallback<T>? callback,
  }) {
    return spawnCall<T>(
      workWithCall: (call) async {
        // Start the process
        final process = await Process.start(
          executable,
          arguments,
          workingDirectory: workingDirectory ?? Directory.current.path,
        );
        
        // Attach process to SpawnedCall for kill/cancel support
        call.setProcess$(process);

        // Handle stderr
        process.stderr.transform(utf8.decoder).listen((data) {
          if (onStderr != null) {
            for (final line in data.split('\n')) {
              if (line.isNotEmpty) onStderr(line);
            }
          }
        });

        // Collect stdout
        final stdoutBuffer = StringBuffer();
        await for (final data in process.stdout.transform(utf8.decoder)) {
          stdoutBuffer.write(data);
        }

        // Wait for process to exit
        final exitCode = await process.exitCode;
        onExit?.call(exitCode);
        
        if (exitCode != 0) {
          throw ProcessException(
            executable,
            arguments,
            'Process exited with code $exitCode',
            exitCode,
          );
        }

        // Parse result
        final content = stdoutBuffer.toString();
        if (deserializer != null) {
          return deserializer(content);
        }

        // Default: try to parse as JSON
        if (T == String) {
          return content as T;
        }
        return json.decode(content) as T;
      },
      description: description ?? 'Stdout worker',
      failOnCrash: failOnCrash,
      callback: callback,
    );
  }

  /// Execute a request to an already-running server process.
  ///
  /// Makes a request to a server that is already running (started separately,
  /// perhaps at the beginning of the operation). The server and client share
  /// the filesystem and can communicate via files in the operation directory.
  ///
  /// This is a convenience method for scenarios where a long-running server
  /// process handles multiple requests during an operation. The server should
  /// be started at the beginning of the operation and stay running throughout.
  ///
  /// Communication pattern (file-based for local participants):
  /// 1. Client writes request to a request file (e.g., `request_<callId>.json`)
  /// 2. Server polls for request files, processes them
  /// 3. Server writes response to a response file (e.g., `response_<callId>.json`)
  /// 4. Client polls for response file and reads result
  ///
  /// Parameters:
  /// - [work] - Async function that performs the actual request to the server
  /// - [description] - Optional description for logging
  /// - [timeout] - Optional timeout for the request
  /// - [failOnCrash] - Whether crash should fail entire operation (default: true)
  /// - [callback] - Optional callbacks for completion, crash, cleanup, and operation failure
  ///
  /// Returns a [SpawnedCall<T>] immediately. The call executes asynchronously.
  /// Access `callId` immediately, await `future` for results.
  /// 
  /// Example:
  /// ```dart
  /// // Write request file, poll for response
  /// final call = operation.execServerRequest<Map>(
  ///   work: () async {
  ///     // Write request
  ///     final requestPath = '${ledger.basePath}/request_${callId}.json';
  ///     await File(requestPath).writeAsString(jsonEncode({'action': 'process'}));
  ///     
  ///     // Poll for response
  ///     return await OperationHelper.pollFile<Map>(
  ///       path: '${ledger.basePath}/response_${callId}.json',
  ///       delete: true,
  ///     )();
  ///   },
  /// );
  /// print('Started: ${call.callId}');
  /// await call.future;
  /// if (call.isSuccess) {
  ///   print('Server response: ${call.result}');
  /// }
  /// ```
  SpawnedCall<T> execServerRequest<T>({
    required Future<T> Function() work,
    String? description,
    Duration? timeout,
    bool failOnCrash = true,
    CallCallback<T>? callback,
  }) {
    return spawnCall<T>(
      work: () async {
        if (timeout != null) {
          return await work().timeout(timeout);
        }
        return await work();
      },
      description: description ?? 'Server request',
      failOnCrash: failOnCrash,
      callback: callback,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────
  // Low-level stack frame operations
  // ─────────────────────────────────────────────────────────────

  /// Push a stack frame for a call (low-level operation).
  ///
  /// This is a lower-level method that directly manipulates the stack.
  /// For most use cases, prefer [startCall] which provides structured
  /// call tracking with callbacks.
  ///
  /// Use this method when:
  /// - You need direct control over stack frame management
  /// - Testing stack behavior without callback overhead
  /// - Implementing custom call patterns
  Future<void> pushStackFrame({required String callId}) async {
    final now = DateTime.now();
    final updated = await _ledger._modifyOperation(
      operationId: operationId,
      elapsedFormatted: elapsedFormatted,
      updater: (data) {
        data.stack.add(StackFrame(
          participantId: participantId,
          callId: callId,
          pid: pid,
          startTime: now,
          lastHeartbeat: now,
        ));
        data.lastHeartbeat = now;
        return data;
      },
    );
    if (updated != null) _updateCache(updated);
  }

  /// Pop a stack frame for a call (low-level operation).
  ///
  /// This is a lower-level method that directly manipulates the stack.
  /// For most use cases, prefer [Call.end] which provides structured
  /// call tracking.
  ///
  /// Use this method when:
  /// - You need direct control over stack frame management
  /// - Testing stack behavior without callback overhead
  /// - Implementing custom call patterns
  Future<void> popStackFrame({required String callId}) async {
    final updated = await _ledger._modifyOperation(
      operationId: operationId,
      elapsedFormatted: elapsedFormatted,
      updater: (data) {
        final index = data.stack.lastIndexWhere((f) => f.callId == callId);
        if (index >= 0) {
          data.stack.removeAt(index);
        }
        data.lastHeartbeat = DateTime.now();
        return data;
      },
    );
    if (updated != null) _updateCache(updated);
  }

  // ─────────────────────────────────────────────────────────────
  // Temp resource management
  // ─────────────────────────────────────────────────────────────

  /// Register a temporary resource.
  Future<void> registerTempResource({required String path}) async {
    final updated = await _ledger._modifyOperation(
      operationId: operationId,
      elapsedFormatted: elapsedFormatted,
      updater: (data) {
        data.tempResources.add(TempResource(
          path: path,
          owner: pid,
          registeredAt: DateTime.now(),
        ));
        data.lastHeartbeat = DateTime.now();
        return data;
      },
    );
    if (updated != null) _updateCache(updated);
  }

  /// Unregister a temporary resource.
  Future<void> unregisterTempResource({required String path}) async {
    final updated = await _ledger._modifyOperation(
      operationId: operationId,
      elapsedFormatted: elapsedFormatted,
      updater: (data) {
        data.tempResources.removeWhere((r) => r.path == path);
        data.lastHeartbeat = DateTime.now();
        return data;
      },
    );
    if (updated != null) _updateCache(updated);
  }

  // ─────────────────────────────────────────────────────────────
  // Abort management
  // ─────────────────────────────────────────────────────────────

  /// Set the abort flag on the operation.
  Future<void> setAbortFlag(bool value) async {
    final updated = await _ledger._modifyOperation(
      operationId: operationId,
      elapsedFormatted: elapsedFormatted,
      updater: (data) {
        data.aborted = value;
        data.lastHeartbeat = DateTime.now();
        return data;
      },
    );
    if (updated != null) _updateCache(updated);
  }

  /// Check if the operation is aborted.
  Future<bool> checkAbort() async {
    await _refreshCache();
    return _cachedData?.aborted ?? true;
  }

  /// Trigger local abort for this participant.
  void triggerAbort() {
    _isAborted = true;
    stopHeartbeat();
    if (!_abortCompleter.isCompleted) {
      _abortCompleter.complete();
    }
  }

  /// Signal that the operation has failed.
  void _signalFailure(OperationFailedInfo info) {
    if (!_failureCompleter.isCompleted) {
      _failureCompleter.complete(info);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Heartbeat
  // ─────────────────────────────────────────────────────────────

  /// Start the heartbeat for this participant.
  ///
  /// The heartbeat periodically:
  /// 1. Updates the lastHeartbeat timestamp
  /// 2. Checks the abort flag
  /// 3. Checks for stale child processes
  /// 4. Calls onHeartbeatError if issues are detected
  /// 5. Calls onHeartbeatSuccess if everything is OK
  void startHeartbeat({
    Duration interval = const Duration(milliseconds: 4500),
    int jitterMs = 500,
    HeartbeatErrorCallback? onError,
    HeartbeatSuccessCallback? onSuccess,
  }) {
    onHeartbeatError = onError;
    onHeartbeatSuccess = onSuccess;
    _scheduleNextHeartbeat(interval: interval, jitterMs: jitterMs);
  }

  void _scheduleNextHeartbeat({
    required Duration interval,
    required int jitterMs,
  }) {
    if (_isAborted) return;

    // Add jitter
    final jitter = DateTime.now().millisecond % jitterMs;
    final delay = interval + Duration(milliseconds: jitter);

    _heartbeatTimer = Timer(delay, () async {
      if (_isAborted) return;
      await _doHeartbeat();
      _scheduleNextHeartbeat(interval: interval, jitterMs: jitterMs);
    });
  }

  Future<void> _doHeartbeat() async {
    try {
      // Perform heartbeat update with checks
      final result = await _performHeartbeatWithChecks();

      if (result == null) {
        onHeartbeatError?.call(
          this,
          const HeartbeatError(
            type: HeartbeatErrorType.ledgerNotFound,
            message: 'Operation file not found',
          ),
        );
        return;
      }

      // Check for abort
      if (result.abortFlag) {
        _isAborted = true;
        if (!_abortCompleter.isCompleted) {
          _abortCompleter.complete();
        }
        onHeartbeatError?.call(
          this,
          const HeartbeatError(
            type: HeartbeatErrorType.abortFlagSet,
            message: 'Abort flag is set',
          ),
        );
        return;
      }

      // Check for stale heartbeat (crash detection)
      if (result.hasStaleChildren) {
        // Detected crash - invoke callbacks for affected calls
        await _handleDetectedCrash(result.staleParticipants);
      }

      // Check for operation in cleanup/failed state
      await _refreshCache();
      if (_cachedData?.operationState == OperationState.cleanup ||
          _cachedData?.operationState == OperationState.failed) {
        _signalFailure(OperationFailedInfo(
          operationId: operationId,
          failedAt: DateTime.now(),
          reason: 'Operation entered ${_cachedData?.operationState} state',
          crashedCallIds: result.staleParticipants,
        ));
      }

      // Success callback
      onHeartbeatSuccess?.call(this, result);
    } catch (e) {
      onHeartbeatError?.call(
        this,
        HeartbeatError(
          type: HeartbeatErrorType.ioError,
          message: 'Heartbeat failed: $e',
          cause: e,
        ),
      );
    }
  }

  /// Handle detected crash - log affected calls and signal failure.
  Future<void> _handleDetectedCrash(List<String> staleParticipants) async {
    // Find calls from stale participants and log
    final crashedCallIds = <String>[];
    for (final call in _activeCalls.values) {
      if (staleParticipants.contains(participantId)) {
        crashedCallIds.add(call.callId);
        await log(
          'CRASH_DETECTED callId=${call.callId} reason=Stale heartbeat',
          level: LogLevel.error,
        );
      }
    }
    
    // Signal operation failure if there were crashes
    if (crashedCallIds.isNotEmpty) {
      _signalFailure(OperationFailedInfo(
        operationId: operationId,
        failedAt: DateTime.now(),
        reason: 'Stale heartbeat detected for ${crashedCallIds.length} calls',
        crashedCallIds: crashedCallIds,
      ));
    }
  }

  Future<HeartbeatResult?> _performHeartbeatWithChecks() async {
    final acquired = await _ledger._acquireLock(operationId);
    if (!acquired) return null;

    try {
      final file = File(_ledger._operationPath(operationId));
      if (!file.existsSync()) return null;

      // Create backup
      await _ledger._createTrailSnapshot(operationId, elapsedFormatted);

      // Read current state
      final content = await file.readAsString();
      final data =
          LedgerData.fromJson(json.decode(content) as Map<String, dynamic>);
      
      // Copy the data before modification for the result
      final dataBefore = LedgerData.fromJson(data.toJson());

      // Calculate global heartbeat age before updating (for backward compatibility)
      final heartbeatAge =
          DateTime.now().difference(data.lastHeartbeat).inMilliseconds;

      // Collect per-participant heartbeat ages BEFORE updating
      final participantAges = <String, int>{};
      final staleParticipants = <String>[];

      for (final frame in data.stack) {
        final age = frame.heartbeatAgeMs;
        participantAges[frame.participantId] = age;
        if (age > stalenessThresholdMs) {
          staleParticipants.add(frame.participantId);
        }
      }

      // Check if any participant OTHER than self is stale
      final hasStaleOther = staleParticipants.any((p) => p != participantId);

      // Update global heartbeat (backward compatibility)
      data.lastHeartbeat = DateTime.now();

      // Update THIS participant's heartbeat in their stack frame
      for (final frame in data.stack) {
        if (frame.participantId == participantId) {
          frame.lastHeartbeat = DateTime.now();
        }
      }

      // Write back
      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(data.toJson()));

      // Update cache
      _updateCache(data);

      return HeartbeatResult(
        abortFlag: data.aborted,
        ledgerExists: true,
        heartbeatUpdated: true,
        stackDepth: data.stack.length,
        tempResourceCount: data.tempResources.length,
        heartbeatAgeMs: heartbeatAge,
        isStale:
            hasStaleOther, // Now true only if OTHER participants are stale
        stackParticipants: data.stack.map((f) => f.participantId).toList(),
        participantHeartbeatAges: participantAges,
        staleParticipants:
            staleParticipants.where((p) => p != participantId).toList(),
        dataBefore: dataBefore,
        dataAfter: data,
      );
    } finally {
      await _ledger._releaseLock(operationId);
    }
  }

  /// Stop the heartbeat for this participant.
  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Perform a single heartbeat and return the result.
  ///
  /// This is useful for manual heartbeat control in tests or
  /// when the automatic timer-based heartbeat is not suitable.
  /// Returns null if the ledger file doesn't exist.
  Future<HeartbeatResult?> heartbeat() async {
    return await _performHeartbeatWithChecks();
  }

  // ─────────────────────────────────────────────────────────────
  // Complete operation
  // ─────────────────────────────────────────────────────────────

  /// Complete the operation (for initiator only).
  ///
  /// This moves the operation files to the backup folder and
  /// unregisters it from the ledger.
  Future<void> complete() async {
    if (!isInitiator) {
      throw StateError('Only the initiator can complete an operation');
    }
    stopHeartbeat();

    // Log completion
    await log('OPERATION_COMPLETED');

    await _ledger._completeOperation(
      operationId: operationId,
      elapsedFormatted: elapsedFormatted,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Cleanup operations
  // ─────────────────────────────────────────────────────────────

  /// Lock the operation file for exclusive access during cleanup.
  ///
  /// Returns the operation data if lock was acquired.
  /// Release with [writeAndUnlockOperation] or [unlockOperation].
  Future<LedgerData?> retrieveAndLockOperation() async {
    return await _ledger._retrieveAndLockOperation(operationId);
  }

  /// Unlock the operation file without writing changes.
  Future<void> unlockOperation() async {
    await _ledger._releaseLock(operationId);
  }

  /// Write operation data back and unlock the operation file.
  Future<void> writeAndUnlockOperation(LedgerData data) async {
    await _ledger._writeAndUnlockOperation(operationId, data, elapsedFormatted);
  }

  /// Get the current operation state.
  Future<OperationState> getOperationState() async {
    await _refreshCache();
    return _cachedData?.operationState ?? OperationState.running;
  }

  /// Set the operation state.
  Future<void> setOperationState(OperationState state) async {
    final updated = await _ledger._modifyOperation(
      operationId: operationId,
      elapsedFormatted: elapsedFormatted,
      updater: (data) {
        data.operationState = state;
        data.lastHeartbeat = DateTime.now();
        return data;
      },
    );
    if (updated != null) _updateCache(updated);

    // Log state change
    await log('OPERATION_STATE_CHANGED state=${state.name}');
  }
}

// ═══════════════════════════════════════════════════════════════
// LEDGER CLASS
// ═══════════════════════════════════════════════════════════════

/// Global ledger that manages all operations.
///
/// The Ledger is responsible for:
/// - Creating and managing operation files
/// - Maintaining a registry of active operations
/// - Providing global heartbeat monitoring
/// - Managing log files for each operation
/// - Managing backups and backup cleanup
///
/// ## Participant Identity
///
/// Participant identity can be set at Ledger creation time (recommended for
/// production) or per-operation (for simulations and testing):
///
/// **Production pattern (one identity per Ledger):**
/// ```dart
/// final ledger = Ledger(
///   basePath: '/tmp/ledger',
///   participantId: 'orchestrator',
/// );
/// final op = await ledger.createOperation(); // Uses ledger's participantId
/// ```
///
/// **Simulation pattern (multiple identities per Ledger):**
/// ```dart
/// final ledger = Ledger(basePath: '/tmp/ledger');
/// final cliOp = await ledger.createOperation(participantId: 'cli');
/// final bridgeOp = await ledger.joinOperation(
///   operationId: opId,
///   participantId: 'bridge',
/// );
/// ```
class Ledger {
  final String basePath;

  /// The participant ID for this ledger instance.
  ///
  /// This identifies who is interacting with the ledger. Each participant
  /// (CLI, Bridge, VS Code, etc.) should have its own unique ID.
  final String participantId;

  /// The process ID for this participant.
  ///
  /// Defaults to the current process PID if not specified in constructor.
  final int participantPid;

  final void Function(String)? onBackupCreated;
  final void Function(String)? onLogLine;

  /// Maximum number of backup operations to retain.
  final int maxBackups;

  late final Directory _ledgerDir;
  late final Directory _backupDir;

  /// Registry of all active operations in this ledger.
  final Map<String, Operation> _operations = {};

  /// Global heartbeat timer.
  Timer? _globalHeartbeatTimer;

  /// Callback for global heartbeat errors.
  HeartbeatErrorCallback? onGlobalHeartbeatError;

  /// Lock timeout and retry settings.
  static const _lockTimeout = Duration(seconds: 2);
  static const _lockRetryInterval = Duration(milliseconds: 50);

  /// Heartbeat interval for global monitoring.
  final Duration heartbeatInterval;

  /// Staleness threshold for detecting crashed operations.
  final Duration staleThreshold;

  Ledger({
    required this.basePath,
    required this.participantId,
    int? participantPid,
    this.onBackupCreated,
    this.onLogLine,
    this.onGlobalHeartbeatError,
    this.maxBackups = 20,
    this.heartbeatInterval = const Duration(seconds: 5),
    this.staleThreshold = const Duration(seconds: 15),
  }) : participantPid = participantPid ?? pid {
    _ledgerDir = Directory(basePath);
    _backupDir = Directory('$basePath/backup');
    if (!_ledgerDir.existsSync()) {
      _ledgerDir.createSync(recursive: true);
    }
    if (!_backupDir.existsSync()) {
      _backupDir.createSync(recursive: true);
    }
    // Auto-start global heartbeat
    _startGlobalHeartbeat();
  }

  /// Get all active operations.
  Map<String, Operation> get operations => Map.unmodifiable(_operations);

  /// Get an operation by ID.
  Operation? getOperation(String operationId) => _operations[operationId];

  // ─────────────────────────────────────────────────────────────
  // Path helpers
  // ─────────────────────────────────────────────────────────────

  String _operationPath(String operationId) =>
      '$basePath/$operationId.operation.json';

  String _lockPath(String operationId) =>
      '$basePath/$operationId.operation.json.lock';

  String _logPath(String operationId) => '$basePath/$operationId.operation.log';

  String _debugLogPath(String operationId) =>
      '$basePath/$operationId.operation.debug.log';

  String _backupOperationPath(String operationId) =>
      '${_backupDir.path}/$operationId/operation.json';

  String _backupLogPath(String operationId) =>
      '${_backupDir.path}/$operationId/operation.log';

  String _backupDebugLogPath(String operationId) =>
      '${_backupDir.path}/$operationId/operation.debug.log';
  
  /// Get the backup folder for an operation.
  String _backupFolderPath(String operationId) =>
      '${_backupDir.path}/$operationId';

  // Trail folder for per-modification snapshots
  String _trailPath(String operationId) => '$basePath/${operationId}_trail';

  String _trailSnapshotPath(String operationId, String elapsedFormatted) =>
      '${_trailPath(operationId)}/${elapsedFormatted}_$operationId.json';

  // ─────────────────────────────────────────────────────────────
  // Operation ID generation
  // ─────────────────────────────────────────────────────────────

  /// Generate an operation ID per specification.
  ///
  /// Format: `YYYYMMDDTHH:MM:SS.sss-{participantId}-{random}`
  String _generateOperationId(String participantId) {
    final now = DateTime.now();
    // Format: 20260121T14:30:45.123
    final timestamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}T'
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    final random =
        Random().nextInt(0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    return '$timestamp-$participantId-$random';
  }

  // ─────────────────────────────────────────────────────────────
  // Locking
  // ─────────────────────────────────────────────────────────────

  Future<bool> _acquireLock(String operationId) async {
    final lockFile = File(_lockPath(operationId));
    final startTime = DateTime.now();

    while (true) {
      try {
        if (lockFile.existsSync()) {
          final stat = lockFile.statSync();
          final age = DateTime.now().difference(stat.modified);
          if (age > _lockTimeout) {
            lockFile.deleteSync();
          }
        }

        await lockFile.create(exclusive: true);
        await lockFile.writeAsString(
          '{"pid": $pid, "timestamp": "${DateTime.now().toIso8601String()}"}',
        );
        return true;
      } catch (e) {
        if (DateTime.now().difference(startTime) >
            const Duration(seconds: 1)) {
          return false;
        }
        await Future.delayed(_lockRetryInterval);
      }
    }
  }

  Future<void> _releaseLock(String operationId) async {
    final lockFile = File(_lockPath(operationId));
    if (lockFile.existsSync()) {
      await lockFile.delete();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Trail snapshots (per-modification backups for debugging)
  // ─────────────────────────────────────────────────────────────

  Future<String> _createTrailSnapshot(
      String operationId, String elapsedFormatted) async {
    final sourceFile = File(_operationPath(operationId));
    if (!sourceFile.existsSync()) return '';

    final snapshotPath = _trailSnapshotPath(operationId, elapsedFormatted);
    final trailDir = Directory(_trailPath(operationId));
    if (!trailDir.existsSync()) {
      await trailDir.create(recursive: true);
    }

    await sourceFile.copy(snapshotPath);
    onBackupCreated?.call(snapshotPath);
    return snapshotPath;
  }

  // ─────────────────────────────────────────────────────────────
  // Backup cleanup
  // ─────────────────────────────────────────────────────────────

  /// Clean old backups beyond the retention limit.
  /// 
  /// Counts operation folders (not files) to determine retention.
  Future<void> _cleanOldBackups() async {
    if (!_backupDir.existsSync()) return;

    // List all operation folders in backup
    final folders = _backupDir
        .listSync()
        .whereType<Directory>()
        .toList();

    if (folders.length <= maxBackups) return;

    // Sort by folder name (which contains timestamp, so alphabetical = chronological)
    // Oldest first
    folders.sort((a, b) {
      final aName = a.path.split('/').last;
      final bName = b.path.split('/').last;
      return aName.compareTo(bName);
    });

    // Delete oldest folders beyond limit
    final toDelete = folders.sublist(0, folders.length - maxBackups);
    for (final folder in toDelete) {
      await folder.delete(recursive: true);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Operation lifecycle
  // ─────────────────────────────────────────────────────────────

  /// Create a new operation (for the initiator).
  ///
  /// Creates the operation file and returns an [Operation] object
  /// that can be used to interact with the operation.
  ///
  /// The participant identity is taken from the Ledger constructor:
  /// ```dart
  /// final ledger = Ledger(basePath: path, participantId: 'orchestrator');
  /// final op = await ledger.createOperation(); // Uses 'orchestrator'
  /// ```
  ///
  /// An operation ID will be auto-generated based on timestamp and
  /// participantId.
  Future<Operation> createOperation({
    String? description,
  }) async {
    final operationId = _generateOperationId(participantId);
    return await _startOperationWithId(
      operationId: operationId,
      participantId: participantId,
      participantPid: participantPid,
      description: description,
    );
  }

  Future<Operation> _startOperationWithId({
    required String operationId,
    required String participantId,
    required int participantPid,
    String? description,
  }) async {
    final acquired = await _acquireLock(operationId);
    if (!acquired) {
      throw StateError('Failed to acquire lock for operation $operationId');
    }

    try {
      final timestamp = DateTime.now();
      final ledgerData = LedgerData(
        operationId: operationId,
        initiatorId: participantId,
        lastHeartbeat: timestamp,
      );

      // Write initial file
      final file = File(_operationPath(operationId));
      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(ledgerData.toJson()));

      // Create empty log files
      await File(_logPath(operationId)).writeAsString('');
      await File(_debugLogPath(operationId)).writeAsString('');

      // Create operation object
      final operation = Operation._(
        ledger: this,
        operationId: operationId,
        participantId: participantId,
        pid: participantPid,
        isInitiator: true,
        startTime: timestamp,
      );
      operation._cachedData = ledgerData;
      operation._lastChangeTimestamp = timestamp;

      // Register in global registry
      _operations[operationId] = operation;

      return operation;
    } finally {
      await _releaseLock(operationId);
    }
  }

  /// Join an existing operation.
  ///
  /// Returns an [Operation] object for the participant to interact with.
  ///
  /// The participant identity is taken from the Ledger constructor:
  /// ```dart
  /// final ledger = Ledger(basePath: path, participantId: 'worker_1');
  /// final op = await ledger.joinOperation(operationId: opId);
  /// ```
  Future<Operation> joinOperation({
    required String operationId,
  }) async {
    final joinTime = DateTime.now();
    
    // Create operation object
    final operation = Operation._(
      ledger: this,
      operationId: operationId,
      participantId: participantId,
      pid: participantPid,
      isInitiator: false,
      startTime: joinTime,
    );

    // Load current state
    await operation._refreshCache();

    // Register in global registry
    _operations[operationId] = operation;

    return operation;
  }

  /// Remove an operation from the registry.
  void _unregisterOperation(String operationId) {
    _operations.remove(operationId);
  }

  // ─────────────────────────────────────────────────────────────
  // File operations (called by Operation)
  // ─────────────────────────────────────────────────────────────

  /// Read the operation file.
  Future<LedgerData?> _readOperation(String operationId) async {
    final file = File(_operationPath(operationId));
    if (!file.existsSync()) return null;

    final acquired = await _acquireLock(operationId);
    if (!acquired) return null;

    try {
      final content = await file.readAsString();
      return LedgerData.fromJson(json.decode(content) as Map<String, dynamic>);
    } finally {
      await _releaseLock(operationId);
    }
  }

  /// Modify the operation file with backup.
  Future<LedgerData?> _modifyOperation({
    required String operationId,
    required String elapsedFormatted,
    required LedgerData Function(LedgerData data) updater,
  }) async {
    final acquired = await _acquireLock(operationId);
    if (!acquired) {
      throw StateError('Failed to acquire lock for operation $operationId');
    }

    try {
      final file = File(_operationPath(operationId));
      if (!file.existsSync()) {
        throw StateError('Operation file does not exist: $operationId');
      }

      // Create trail snapshot
      await _createTrailSnapshot(operationId, elapsedFormatted);

      // Read current state
      final content = await file.readAsString();
      final ledgerData =
          LedgerData.fromJson(json.decode(content) as Map<String, dynamic>);

      // Apply update
      final updated = updater(ledgerData);

      // Write back
      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(updated.toJson()));

      return updated;
    } finally {
      await _releaseLock(operationId);
    }
  }

  /// Lock and retrieve operation for cleanup operations.
  ///
  /// Used during cleanup to atomically read the operation file.
  /// Release with [_writeAndUnlockOperation] or [_releaseLock].
  Future<LedgerData?> _retrieveAndLockOperation(String operationId) async {
    final acquired = await _acquireLock(operationId);
    if (!acquired) return null;

    try {
      final file = File(_operationPath(operationId));
      if (!file.existsSync()) {
        await _releaseLock(operationId);
        return null;
      }

      final content = await file.readAsString();
      return LedgerData.fromJson(json.decode(content) as Map<String, dynamic>);
    } catch (e) {
      await _releaseLock(operationId);
      rethrow;
    }
  }

  /// Write operation data and unlock after cleanup operations.
  Future<void> _writeAndUnlockOperation(
    String operationId,
    LedgerData data,
    String elapsedFormatted,
  ) async {
    try {
      // Create trail snapshot
      await _createTrailSnapshot(operationId, elapsedFormatted);

      // Write updated data
      final file = File(_operationPath(operationId));
      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(data.toJson()));
    } finally {
      await _releaseLock(operationId);
    }
  }

  /// Complete an operation - move files to backup folder.
  Future<void> _completeOperation({
    required String operationId,
    required String elapsedFormatted,
  }) async {
    final acquired = await _acquireLock(operationId);
    if (!acquired) return;

    try {
      // Update operation state
      final file = File(_operationPath(operationId));
      if (file.existsSync()) {
        final content = await file.readAsString();
        final ledgerData =
            LedgerData.fromJson(json.decode(content) as Map<String, dynamic>);
        ledgerData.operationState = OperationState.completed;

        final encoder = const JsonEncoder.withIndent('  ');
        await file.writeAsString(encoder.convert(ledgerData.toJson()));
      }

      // Move files to backup
      await _moveToBackup(operationId);

      // Clean old backups
      await _cleanOldBackups();

      // Unregister
      _unregisterOperation(operationId);
    } finally {
      await _releaseLock(operationId);
    }
  }

  /// Move operation files to backup folder.
  /// 
  /// Creates a per-operation folder in the backup directory.
  Future<void> _moveToBackup(String operationId) async {
    // Create the operation's backup folder
    final backupFolder = Directory(_backupFolderPath(operationId));
    if (!backupFolder.existsSync()) {
      await backupFolder.create(recursive: true);
    }
    
    final sourceOp = File(_operationPath(operationId));
    final sourceLog = File(_logPath(operationId));
    final sourceDebug = File(_debugLogPath(operationId));

    if (sourceOp.existsSync()) {
      await sourceOp.rename(_backupOperationPath(operationId));
    }
    if (sourceLog.existsSync()) {
      await sourceLog.rename(_backupLogPath(operationId));
    }
    if (sourceDebug.existsSync()) {
      await sourceDebug.rename(_backupDebugLogPath(operationId));
    }

    onBackupCreated?.call(_backupFolderPath(operationId));
  }

  // ─────────────────────────────────────────────────────────────
  // Log file operations
  // ─────────────────────────────────────────────────────────────

  /// Append a line to the operation's log file.
  Future<void> _appendLog(String operationId, String line) async {
    final logFile = File(_logPath(operationId));
    await logFile.writeAsString('$line\n', mode: FileMode.append, flush: true);
    onLogLine?.call(line);
  }

  /// Append a line to the operation's debug log file.
  Future<void> _appendDebugLog(String operationId, String message) async {
    final logFile = File(_debugLogPath(operationId));
    final timestamp = DateTime.now().toIso8601String();
    final line = '$timestamp $message';
    await logFile.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }

  // ─────────────────────────────────────────────────────────────
  // Global heartbeat (internal)
  // ─────────────────────────────────────────────────────────────

  /// Start the global heartbeat that monitors all operations.
  ///
  /// Called automatically in the constructor. Uses [heartbeatInterval]
  /// and [staleThreshold] from constructor parameters.
  void _startGlobalHeartbeat() {
    _globalHeartbeatTimer?.cancel();
    _globalHeartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      _checkAllOperations(staleThreshold);
    });
  }

  /// Stop the global heartbeat.
  void _stopGlobalHeartbeat() {
    _globalHeartbeatTimer?.cancel();
    _globalHeartbeatTimer = null;
  }

  /// Check all registered operations for staleness.
  void _checkAllOperations(Duration staleThreshold) {
    final now = DateTime.now();

    for (final entry in _operations.entries) {
      final operation = entry.value;
      final lastChange = operation._lastChangeTimestamp;

      if (lastChange == null) {
        onGlobalHeartbeatError?.call(
          operation,
          HeartbeatError(
            type: HeartbeatErrorType.ledgerNotFound,
            message: 'Operation ${operation.operationId} has no cached data',
          ),
        );
        continue;
      }

      final age = now.difference(lastChange);
      if (age > staleThreshold) {
        onGlobalHeartbeatError?.call(
          operation,
          HeartbeatError(
            type: HeartbeatErrorType.heartbeatStale,
            message:
                'Operation ${operation.operationId} is stale (${age.inSeconds}s)',
          ),
        );
      }
    }
  }

  /// Dispose of the ledger and stop all heartbeats.
  void dispose() {
    _stopGlobalHeartbeat();
    for (final operation in _operations.values) {
      operation.stopHeartbeat();
    }
    _operations.clear();
  }
}
