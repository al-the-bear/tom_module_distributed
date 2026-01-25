library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../ledger_local/file_ledger.dart';
import 'ledger_base.dart';

// Re-export types
export 'cleanup_handler.dart';
export 'ledger_base.dart';
export 'ledger_types.dart';

// Part files
part 'call_callback.dart';
part 'ledger_server.dart';

/// Internal callback for heartbeat errors (uses _LedgerOperation).
typedef _InternalHeartbeatErrorCallback =
    void Function(_LedgerOperation operation, HeartbeatError error);

/// Internal callback for successful heartbeat (uses _LedgerOperation).
typedef _InternalHeartbeatSuccessCallback =
    void Function(_LedgerOperation operation, HeartbeatResult result);

/// Tracks a call in progress with its callback.
class _ActiveCall {
  final String callId;
  final int sessionId;
  final CallCallback callback;
  final DateTime startedAt;
  final String? description;
  final Completer<void> completer;
  final bool isSpawned;
  final bool failOnCrash;

  _ActiveCall({
    required this.callId,
    required this.sessionId,
    required this.callback,
    required this.startedAt,
    this.description,
    required this.isSpawned,
    this.failOnCrash = true,
  }) : completer = Completer<void>();
}

// ═══════════════════════════════════════════════════════════════
// OPERATION CLASS (PUBLIC API)
// ═══════════════════════════════════════════════════════════════

/// Represents a running operation for a specific join session.
///
/// Each call to [Ledger.joinOperation] or [Ledger.createOperation] returns
/// a new [Operation] with its own session. This allows tracking which
/// calls belong to which join, and ensures [leave] only checks calls
/// created through this handle.
///
/// **Key properties:**
/// - Each handle has a unique [sessionId] within the operation
/// - Calls created through this handle are tracked to this session
/// - [getPendingSpawnedCalls] returns only spawned calls from this session
/// - [hasPendingCalls] checks if there are any pending calls
/// - [leave] can optionally cancel pending calls from this session
///
/// **Example:**
/// ```dart
/// final handle1 = await ledger.joinOperation(operationId: opId);
/// final handle2 = await ledger.joinOperation(operationId: opId);
///
/// // Each handle tracks its own calls
/// final call1 = handle1.spawnCall(work: () async => doWork1());
/// final call2 = handle2.spawnCall(work: () async => doWork2());
///
/// // handle1 only sees call1
/// print(handle1.getPendingSpawnedCalls()); // [call1]
/// print(handle1.hasPendingCalls()); // true
///
/// // Leave with cancel
/// handle1.leave(cancelPendingCalls: true);
/// handle2.leave(cancelPendingCalls: true);
/// ```
class LocalOperation implements Operation {
  /// The underlying ledger operation (internal).
  final _LedgerOperation _operation;

  /// This operation's unique session ID within the ledger operation.
  @override
  final int sessionId;

  LocalOperation._(this._operation, this.sessionId);

  // ─────────────────────────────────────────────────────────────
  // Delegated properties from Operation
  // ─────────────────────────────────────────────────────────────

  /// The operation ID.
  @override
  String get operationId => _operation.operationId;

  /// The participant ID.
  @override
  String get participantId => _operation.participantId;

  /// The process ID.
  int get pid => _operation.pid;

  /// Whether this is the initiator.
  @override
  bool get isInitiator => _operation.isInitiator;

  /// When this operation was started.
  @override
  DateTime get startTime => _operation.startTime;

  /// Cached operation data.
  @override
  LedgerData? get cachedData => _operation.cachedData;

  /// Last change timestamp.
  DateTime? get lastChangeTimestamp => _operation.lastChangeTimestamp;

  /// Whether this participant is aborted.
  @override
  bool get isAborted => _operation.isAborted;

  /// Future that completes when abort is signaled.
  @override
  Future<void> get onAbort => _operation.onAbort;

  /// Future that completes when operation fails.
  @override
  Future<OperationFailedInfo> get onFailure => _operation.onFailure;

  /// Elapsed time formatted as "SSS.mmm".
  @override
  String get elapsedFormatted => _operation.elapsedFormatted;

  /// Elapsed duration since operation start.
  @override
  Duration get elapsedDuration => _operation.elapsedDuration;

  /// Start time as ISO 8601 string.
  @override
  String get startTimeIso => _operation.startTimeIso;

  /// Start time as milliseconds since epoch.
  @override
  int get startTimeMs => _operation.startTimeMs;

  /// Staleness threshold in milliseconds.
  int get stalenessThresholdMs => _operation.stalenessThresholdMs;
  set stalenessThresholdMs(int value) =>
      _operation.stalenessThresholdMs = value;

  // ─────────────────────────────────────────────────────────────
  // Call management (delegated with session tracking)
  // ─────────────────────────────────────────────────────────────

  /// Start a call tracked to this session.
  ///
  /// See [Operation.startCall] for details.
  @override
  Future<Call<T>> startCall<T>({
    CallCallback<T>? callback,
    String? description,
    bool failOnCrash = true,
  }) {
    return _operation._startCallWithSession<T>(
      sessionId: sessionId,
      callback: callback,
      description: description,
      failOnCrash: failOnCrash,
    );
  }

  /// Spawn a call tracked to this session.
  ///
  /// See [Operation.spawnCall] for details.
  @override
  SpawnedCall<T> spawnCall<T>({
    required Future<T> Function(SpawnedCall<T> call, Operation operation) work,
    CallCallback<T>? callback,
    String? description,
    bool failOnCrash = true,
  }) {
    return _operation._spawnCallWithSession<T>(
      sessionId: sessionId,
      operation: this,
      work: work,
      callback: callback,
      description: description,
      failOnCrash: failOnCrash,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Session-specific call tracking
  // ─────────────────────────────────────────────────────────────

  /// Check if this session has any pending calls.
  ///
  /// Returns true if there are any calls (regular or spawned) that were
  /// started through this handle and have not yet completed.
  @override
  bool hasPendingCalls() {
    return _operation._hasPendingCallsForSession(sessionId);
  }

  /// Get pending spawned calls for this session.
  ///
  /// Returns a list of [SpawnedCall] objects that were started through
  /// this handle and have not yet completed.
  ///
  /// For checking if there are any pending calls (including regular calls),
  /// use [hasPendingCalls].
  List<SpawnedCall> getPendingSpawnedCalls() {
    return _operation._getPendingSpawnedCallsForSession(sessionId);
  }

  /// Get pending regular calls for this session.
  ///
  /// Returns a list of [Call] objects that were started through
  /// this handle via [startCall] and have not yet completed.
  ///
  /// For spawned calls, use [getPendingSpawnedCalls].
  List<Call<dynamic>> getPendingCalls() {
    return _operation._getPendingCallsForSession(sessionId);
  }

  /// Get the number of pending calls for this session.
  ///
  /// Returns the count of all calls (regular and spawned) that were
  /// started through this handle and have not yet completed.
  @override
  int get pendingCallCount {
    return _operation._getPendingCallCountForSession(sessionId);
  }

  /// Leave this session of the operation.
  ///
  /// **Parameters:**
  /// - [cancelPendingCalls] - If true, cancels all pending calls from this
  ///   session before leaving. If false (default), throws [StateError] if
  ///   there are pending calls.
  ///
  /// **Throws:**
  /// - [StateError] if there are pending calls and [cancelPendingCalls] is false
  ///
  /// When the last session leaves, the heartbeat is stopped and the
  /// operation is unregistered.
  @override
  void leave({bool cancelPendingCalls = false}) {
    _operation._leaveSession(sessionId, cancelPendingCalls: cancelPendingCalls);
  }

  // ─────────────────────────────────────────────────────────────
  // Delegated methods from Operation
  // ─────────────────────────────────────────────────────────────

  /// Write an entry to the operation log.
  @override
  Future<void> log(String message, {LogLevel level = LogLevel.info}) =>
      _operation.log(message, level: level);

  /// Complete the operation (for initiator only).
  @override
  Future<void> complete() => _operation.complete();

  /// Set the abort flag on the operation.
  @override
  Future<void> setAbortFlag(bool value) => _operation.setAbortFlag(value);

  /// Check if the operation is aborted.
  @override
  Future<bool> checkAbort() => _operation.checkAbort();

  /// Trigger local abort for this participant.
  @override
  void triggerAbort() => _operation.triggerAbort();

  /// Wait for work while monitoring for operation failure.
  @override
  Future<T> waitForCompletion<T>(
    Future<T> Function() work, {
    Future<void> Function(OperationFailedInfo info)? onOperationFailed,
    Future<T> Function(Object error, StackTrace stackTrace)? onError,
  }) => _operation.waitForCompletion(
    work,
    onOperationFailed: onOperationFailed,
    onError: onError,
  );

  /// Start the heartbeat.
  @override
  void startHeartbeat({
    Duration interval = const Duration(milliseconds: 4500),
    int jitterMs = 500,
    HeartbeatErrorCallback? onError,
    HeartbeatSuccessCallback? onSuccess,
  }) {
    // Wrap public callbacks to internal callbacks that pass this Operation
    _InternalHeartbeatErrorCallback? internalOnError;
    _InternalHeartbeatSuccessCallback? internalOnSuccess;

    if (onError != null) {
      internalOnError = (_, error) => onError(this, error);
    }
    if (onSuccess != null) {
      internalOnSuccess = (_, result) => onSuccess(this, result);
    }

    _operation.startHeartbeat(
      interval: interval,
      jitterMs: jitterMs,
      onError: internalOnError,
      onSuccess: internalOnSuccess,
    );
  }

  /// Stop the heartbeat.
  void stopHeartbeat() => _operation.stopHeartbeat();

  /// Sync operation state with callbacks.
  @override
  Future<SyncResult> sync(
    List<SpawnedCall> calls, {
    Future<void> Function(OperationFailedInfo info)? onOperationFailed,
    Future<void> Function()? onCompletion,
  }) => _operation.sync(
    calls,
    onOperationFailed: onOperationFailed,
    onCompletion: onCompletion,
  );

  /// Execute a worker that writes result to a file.
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
  }) => _operation.execFileResultWorker(
    executable: executable,
    arguments: arguments,
    resultFilePath: resultFilePath,
    workingDirectory: workingDirectory,
    description: description,
    deserializer: deserializer,
    deleteResultFile: deleteResultFile,
    pollInterval: pollInterval,
    timeout: timeout,
    onStdout: onStdout,
    onStderr: onStderr,
    onExit: onExit,
    failOnCrash: failOnCrash,
    callback: callback,
  );

  /// Execute a worker that outputs to stdout.
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
  }) => _operation.execStdioWorker(
    executable: executable,
    arguments: arguments,
    workingDirectory: workingDirectory,
    description: description,
    deserializer: deserializer,
    onStderr: onStderr,
    onExit: onExit,
    timeout: timeout,
    failOnCrash: failOnCrash,
    callback: callback,
  );

  // ─────────────────────────────────────────────────────────────
  // Additional delegated methods (for backward compatibility)
  // ─────────────────────────────────────────────────────────────

  /// Wait for a spawned call to complete.
  @override
  Future<SyncResult> awaitCall<T>(
    SpawnedCall<T> call, {
    Future<void> Function(OperationFailedInfo info)? onOperationFailed,
    Future<void> Function()? onCompletion,
  }) => _operation.awaitCall(
    call,
    onOperationFailed: onOperationFailed,
    onCompletion: onCompletion,
  );

  /// Write debug log entry.
  Future<void> debugLog(String message) => _operation.debugLog(message);

  /// Get operation state.
  Future<OperationState?> getOperationState() => _operation.getOperationState();

  /// Set operation state.
  Future<void> setOperationState(OperationState state) =>
      _operation.setOperationState(state);

  /// Perform heartbeat.
  Future<HeartbeatResult?> heartbeat() => _operation.heartbeat();

  /// Log a formatted message with timestamp and participant.
  Future<void> logMessage({required int depth, required String message}) =>
      _operation.logMessage(depth: depth, message: message);

  /// Create a call frame (low-level API).
  @override
  Future<void> createCallFrame({required String callId}) =>
      _operation.createCallFrame(callId: callId);

  /// Delete a call frame (low-level API).
  @override
  Future<void> deleteCallFrame({required String callId}) =>
      _operation.deleteCallFrame(callId: callId);

  /// Register temporary resource.
  @override
  Future<void> registerTempResource({required String path}) =>
      _operation.registerTempResource(path: path);

  /// Unregister temporary resource.
  @override
  Future<void> unregisterTempResource({required String path}) =>
      _operation.unregisterTempResource(path: path);

  /// Retrieve and lock operation (low-level API).
  Future<LedgerData?> retrieveAndLockOperation() =>
      _operation.retrieveAndLockOperation();

  /// Unlock operation (low-level API).
  Future<void> unlockOperation() => _operation.unlockOperation();

  /// Write and unlock operation (low-level API).
  Future<void> writeAndUnlockOperation(LedgerData data) =>
      _operation.writeAndUnlockOperation(data);

  /// Execute a server request (simple spawned call wrapper).
  SpawnedCall<T> execServerRequest<T>({
    required Future<T> Function() work,
    String? description,
    Duration? timeout,
    bool failOnCrash = true,
    CallCallback<T>? callback,
  }) => _operation.execServerRequest(
    work: work,
    description: description,
    timeout: timeout,
    failOnCrash: failOnCrash,
    callback: callback,
  );
}

// ═══════════════════════════════════════════════════════════════
// _LEDGEROPERATION CLASS (INTERNAL)
// ═══════════════════════════════════════════════════════════════

/// Internal class representing a running operation.
///
/// Each participant gets their own _LedgerOperation object to interact with
/// the shared operation file and log. This class is internal; users interact
/// with [Operation] which wraps this with session-aware call tracking.
class _LedgerOperation implements CallLifecycle {
  final LocalLedger _ledger;
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

  /// Internal callbacks for heartbeat events (uses _LedgerOperation).
  _InternalHeartbeatErrorCallback? _onHeartbeatError;
  _InternalHeartbeatSuccessCallback? _onHeartbeatSuccess;

  /// Completer that signals abort.
  final Completer<void> _abortCompleter = Completer<void>();

  /// Completer that signals operation failure (for waitForCompletion).
  final Completer<OperationFailedInfo> _failureCompleter =
      Completer<OperationFailedInfo>();

  /// Active calls tracked by this participant.
  final Map<String, _ActiveCall> _activeCalls = {};

  /// Counter for generating unique call IDs.
  int _callCounter = 0;

  /// Counter for generating unique session IDs.
  int _sessionCounter = 0;

  /// Active session IDs (each joinOperation creates a new session).
  final Set<int> _activeSessions = {};

  /// Random for generating unique call IDs.
  final _random = Random();

  _LedgerOperation._({
    required LocalLedger ledger,
    required this.operationId,
    required this.participantId,
    required this.pid,
    required this.isInitiator,
    required this.startTime,
  }) : _ledger = ledger;

  /// Number of times this operation has been joined.
  ///
  /// A participant may join the same operation multiple times (e.g., handling
  /// multiple calls for the same operation). Heartbeat is started on first
  /// join and stopped when join count reaches 0 via [leave].
  int _joinCount = 0;

  /// Get the join count for this operation.
  int get joinCount => _joinCount;

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
    final randomPart = _random
        .nextInt(0xFFFF)
        .toRadixString(16)
        .padLeft(4, '0');
    return 'call_${participantId}_${_callCounter}_$randomPart';
  }

  // ─────────────────────────────────────────────────────────────
  // Session management (for OperationHandle)
  // ─────────────────────────────────────────────────────────────

  /// Create a new session and return its ID.
  int _createSession() {
    _sessionCounter++;
    _activeSessions.add(_sessionCounter);
    _joinCount++;
    return _sessionCounter;
  }

  /// Start a call tracked to a specific session.
  Future<Call<T>> _startCallWithSession<T>({
    required int sessionId,
    CallCallback<T>? callback,
    String? description,
    bool failOnCrash = true,
  }) async {
    final callId = _generateCallId();
    final now = DateTime.now();

    // Track locally with session ID
    _activeCalls[callId] = _ActiveCall(
      callId: callId,
      sessionId: sessionId,
      callback: callback ?? CallCallback<T>(),
      startedAt: now,
      description: description,
      isSpawned: false,
      failOnCrash: failOnCrash,
    );

    // Add call frame
    final updated = await _ledger._modifyOperation(
      operationId: operationId,
      elapsedFormatted: elapsedFormatted,
      updater: (data) {
        data.callFrames.add(
          CallFrame(
            participantId: participantId,
            callId: callId,
            pid: pid,
            startTime: now,
            lastHeartbeat: now,
            description: description,
            failOnCrash: failOnCrash,
          ),
        );
        data.lastHeartbeat = now;
        return data;
      },
    );
    if (updated != null) _updateCache(updated);

    await log('CALL_STARTED callId=$callId participant=$participantId');

    final call = Call<T>.internal(
      operation: this,
      callId: callId,
      startedAt: now,
    );
    _calls[callId] = call;
    return call;
  }

  /// Spawn a call tracked to a specific session.
  SpawnedCall<T> _spawnCallWithSession<T>({
    required int sessionId,
    required Operation operation,
    required Future<T> Function(SpawnedCall<T> call, Operation operation) work,
    CallCallback<T>? callback,
    String? description,
    bool failOnCrash = true,
  }) {
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

    // Track locally with session ID
    _activeCalls[callId] = _ActiveCall(
      callId: callId,
      sessionId: sessionId,
      callback: internalCallback,
      startedAt: now,
      description: description,
      isSpawned: true,
      failOnCrash: failOnCrash,
    );

    // Execute asynchronously
    _runSpawnedCall<T>(
      callId: callId,
      work: () => work(spawnedCall, operation),
      spawnedCall: spawnedCall,
      callback: callback,
      failOnCrash: failOnCrash,
    );

    return spawnedCall;
  }

  /// Check if a session has any pending calls.
  bool _hasPendingCallsForSession(int sessionId) {
    return _activeCalls.entries.any((e) => e.value.sessionId == sessionId);
  }

  /// Get count of pending calls for a specific session.
  int _getPendingCallCountForSession(int sessionId) {
    return _activeCalls.entries
        .where((e) => e.value.sessionId == sessionId)
        .length;
  }

  /// Get pending spawned calls for a specific session.
  List<SpawnedCall> _getPendingSpawnedCallsForSession(int sessionId) {
    final pendingCallIds = _activeCalls.entries
        .where((e) => e.value.sessionId == sessionId && e.value.isSpawned)
        .map((e) => e.key)
        .toList();

    return pendingCallIds
        .map((id) => _spawnedCalls[id])
        .whereType<SpawnedCall>()
        .where((c) => !c.isCompleted)
        .toList();
  }

  /// Get pending regular calls for a specific session.
  List<Call<dynamic>> _getPendingCallsForSession(int sessionId) {
    final pendingCallIds = _activeCalls.entries
        .where((e) => e.value.sessionId == sessionId && !e.value.isSpawned)
        .map((e) => e.key)
        .toList();

    return pendingCallIds
        .map((id) => _calls[id])
        .whereType<Call<dynamic>>()
        .where((c) => !c.isCompleted)
        .toList();
  }

  /// Leave a specific session.
  void _leaveSession(int sessionId, {bool cancelPendingCalls = false}) {
    if (!_activeSessions.contains(sessionId)) {
      throw StateError('Session $sessionId is not active');
    }

    // Get pending spawned calls for this session
    final pendingCalls = _getPendingSpawnedCallsForSession(sessionId);

    if (pendingCalls.isNotEmpty) {
      if (cancelPendingCalls) {
        // Cancel all pending calls
        for (final call in pendingCalls) {
          call.cancel();
        }
      } else {
        final callIds = pendingCalls.map((c) => c.callId).join(', ');
        throw StateError(
          'Cannot leave operation - ${pendingCalls.length} spawned call(s) '
          'still active: [$callIds]. End or cancel all calls before leaving, '
          'or use leave(cancelPendingCalls: true).',
        );
      }
    }

    // Remove session
    _activeSessions.remove(sessionId);
    _joinCount--;

    if (_joinCount == 0) {
      stopHeartbeat();
      _ledger._unregisterOperation(operationId);
    }
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
  Future<void> logMessage({required int depth, required String message}) async {
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

    // Track locally (sessionId: 0 for direct Operation calls, not via handle)
    _activeCalls[callId] = _ActiveCall(
      callId: callId,
      sessionId: 0,
      callback: callback ?? CallCallback<T>(),
      startedAt: now,
      description: description,
      isSpawned: false,
      failOnCrash: failOnCrash,
    );

    // Add call frame
    final updated = await _ledger._modifyOperation(
      operationId: operationId,
      elapsedFormatted: elapsedFormatted,
      updater: (data) {
        data.callFrames.add(
          CallFrame(
            participantId: participantId,
            callId: callId,
            pid: pid,
            startTime: now,
            lastHeartbeat: now,
            description: description,
            failOnCrash: failOnCrash,
          ),
        );
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

  /// Internal method to end a call, called by Call.end().
  ///
  /// **Note:** This method is for internal use by the ledger API.
  /// Users should call [Call.end] instead.
  @override
  Future<void> endCallInternal<T>({required String callId, T? result}) async {
    final activeCall = _activeCalls.remove(callId);
    if (activeCall == null) {
      throw StateError('No active call with ID: $callId');
    }
    _calls.remove(callId);

    final now = DateTime.now();

    // Remove call frame
    final updated = await _ledger._modifyOperation(
      operationId: operationId,
      elapsedFormatted: elapsedFormatted,
      updater: (data) {
        final index = data.callFrames.lastIndexWhere((f) => f.callId == callId);
        if (index >= 0) {
          data.callFrames.removeAt(index);
        }
        data.lastHeartbeat = now;
        return data;
      },
    );
    if (updated != null) _updateCache(updated);

    // Log the call end
    final duration = now.difference(activeCall.startedAt);
    await log(
      'CALL_ENDED callId=$callId duration=${duration.inMilliseconds}ms',
    );

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

  /// Internal method to fail a call, called by Call.fail().
  ///
  /// **Note:** This method is for internal use by the ledger API.
  /// Users should call [Call.fail] instead.
  @override
  Future<void> failCallInternal({
    required String callId,
    required Object error,
    StackTrace? stackTrace,
  }) async {
    final activeCall = _activeCalls.remove(callId);
    if (activeCall == null) {
      throw StateError('No active call with ID: $callId');
    }
    _calls.remove(callId);

    final now = DateTime.now();

    // Remove call frame
    final updated = await _ledger._modifyOperation(
      operationId: operationId,
      elapsedFormatted: elapsedFormatted,
      updater: (data) {
        final index = data.callFrames.lastIndexWhere((f) => f.callId == callId);
        if (index >= 0) {
          data.callFrames.removeAt(index);
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
      level: LogLevel.error,
    );

    // Call cleanup callback
    await activeCall.callback.onCleanup?.call();

    // If this call had failOnCrash=true, signal operation failure
    if (activeCall.failOnCrash) {
      _signalFailure(
        OperationFailedInfo(
          operationId: operationId,
          failedAt: now,
          reason: 'Call $callId failed: $error',
          crashedCallIds: [callId],
        ),
      );
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
  // Call Tracking
  // ─────────────────────────────────────────────────────────────

  /// Tracking for regular calls.
  final Map<String, Call<dynamic>> _calls = {};

  /// Tracking for spawned calls.
  final Map<String, SpawnedCall> _spawnedCalls = {};

  /// Internal spawn call for simple work without call/operation access.
  ///
  /// Used by [execServerRequest] for convenience.
  SpawnedCall<T> _spawnCallSimple<T>({
    required Future<T> Function() work,
    CallCallback<T>? callback,
    String? description,
    bool failOnCrash = true,
  }) {
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

    // Track locally (sessionId: 0 for internal calls)
    _activeCalls[callId] = _ActiveCall(
      callId: callId,
      sessionId: 0,
      callback: internalCallback,
      startedAt: now,
      description: description,
      isSpawned: true,
      failOnCrash: failOnCrash,
    );

    // Execute asynchronously
    _runSpawnedCall<T>(
      callId: callId,
      work: work,
      spawnedCall: spawnedCall,
      callback: callback,
      failOnCrash: failOnCrash,
    );

    return spawnedCall;
  }

  /// Internal spawn call for work that needs call access (e.g., process spawning).
  ///
  /// Used by [spawnProcessWithOutput] and similar methods.
  SpawnedCall<T> _spawnCallWithCallAccess<T>({
    required Future<T> Function(SpawnedCall<T> call) work,
    CallCallback<T>? callback,
    String? description,
    bool failOnCrash = true,
  }) {
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

    // Track locally (sessionId: 0 for internal calls)
    _activeCalls[callId] = _ActiveCall(
      callId: callId,
      sessionId: 0,
      callback: internalCallback,
      startedAt: now,
      description: description,
      isSpawned: true,
      failOnCrash: failOnCrash,
    );

    // Execute asynchronously
    _runSpawnedCall<T>(
      callId: callId,
      work: () => work(spawnedCall),
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

    // Add call frame
    final updated = await _ledger._modifyOperation(
      operationId: operationId,
      elapsedFormatted: elapsedFormatted,
      updater: (data) {
        data.callFrames.add(
          CallFrame(
            participantId: participantId,
            callId: callId,
            pid: pid,
            startTime: now,
            lastHeartbeat: now,
            description: spawnedCall.description,
            failOnCrash: failOnCrash,
          ),
        );
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

      // Remove call frame
      await _ledger._modifyOperation(
        operationId: operationId,
        elapsedFormatted: elapsedFormatted,
        updater: (data) {
          final index = data.callFrames.lastIndexWhere(
            (f) => f.callId == callId,
          );
          if (index >= 0) data.callFrames.removeAt(index);
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

      // Remove call frame
      await _ledger._modifyOperation(
        operationId: operationId,
        elapsedFormatted: elapsedFormatted,
        updater: (data) {
          final index = data.callFrames.lastIndexWhere(
            (f) => f.callId == callId,
          );
          if (index >= 0) data.callFrames.removeAt(index);
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
        _signalFailure(
          OperationFailedInfo(
            operationId: operationId,
            failedAt: DateTime.now(),
            reason: 'Call $callId failed: $e',
            crashedCallIds: [callId],
          ),
        );
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
    return _spawnCallWithCallAccess<T>(
      work: (call) async {
        // Start the process
        final process = await Process.start(
          executable,
          arguments,
          workingDirectory: workingDirectory ?? Directory.current.path,
        );

        // Attach process to SpawnedCall for kill/cancel support
        call._setProcess(process);

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
    return _spawnCallWithCallAccess<T>(
      work: (call) async {
        // Start the process
        final process = await Process.start(
          executable,
          arguments,
          workingDirectory: workingDirectory ?? Directory.current.path,
        );

        // Attach process to SpawnedCall for kill/cancel support
        call._setProcess(process);

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
    return _spawnCallSimple<T>(
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
  // Low-level call frame operations
  // ─────────────────────────────────────────────────────────────

  /// Create a call frame (low-level operation).
  ///
  /// This is a lower-level method that directly manipulates the call frames.
  /// For most use cases, prefer [startCall] which provides structured
  /// call tracking with callbacks.
  ///
  /// Use this method when:
  /// - You need direct control over call frame management
  /// - Testing call frame behavior without callback overhead
  /// - Implementing custom call patterns
  ///
  /// Note: Call frames are stored in a list and identified by callId,
  /// not by position. Frames can be removed in any order.
  Future<void> createCallFrame({required String callId}) async {
    final now = DateTime.now();
    final updated = await _ledger._modifyOperation(
      operationId: operationId,
      elapsedFormatted: elapsedFormatted,
      updater: (data) {
        data.callFrames.add(
          CallFrame(
            participantId: participantId,
            callId: callId,
            pid: pid,
            startTime: now,
            lastHeartbeat: now,
          ),
        );
        data.lastHeartbeat = now;
        return data;
      },
    );
    if (updated != null) _updateCache(updated);
  }

  /// Delete a call frame (low-level operation).
  ///
  /// This is a lower-level method that directly manipulates the call frames.
  /// For most use cases, prefer [Call.end] which provides structured
  /// call tracking.
  ///
  /// Use this method when:
  /// - You need direct control over call frame management
  /// - Testing call frame behavior without callback overhead
  /// - Implementing custom call patterns
  ///
  /// Note: This method finds the frame by callId and removes it, regardless
  /// of position. Frames can be removed in any order.
  Future<void> deleteCallFrame({required String callId}) async {
    final updated = await _ledger._modifyOperation(
      operationId: operationId,
      elapsedFormatted: elapsedFormatted,
      updater: (data) {
        final index = data.callFrames.lastIndexWhere((f) => f.callId == callId);
        if (index >= 0) {
          data.callFrames.removeAt(index);
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
        data.tempResources.add(
          TempResource(path: path, owner: pid, registeredAt: DateTime.now()),
        );
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
  ///
  /// **Note:** Heartbeat is automatically started when an operation is
  /// created or joined. This method is primarily useful for:
  /// - Restarting heartbeat with different settings
  /// - Adding custom callbacks (onError, onSuccess)
  ///
  /// If heartbeat is already running, it will be stopped and restarted
  /// with the new settings.
  void startHeartbeat({
    Duration interval = const Duration(milliseconds: 4500),
    int jitterMs = 500,
    _InternalHeartbeatErrorCallback? onError,
    _InternalHeartbeatSuccessCallback? onSuccess,
  }) {
    // Cancel any existing heartbeat timer
    stopHeartbeat();

    _onHeartbeatError = onError;
    _onHeartbeatSuccess = onSuccess;
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
        _onHeartbeatError?.call(
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
        _onHeartbeatError?.call(
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

        // Signal error - stale heartbeat detected
        _onHeartbeatError?.call(
          this,
          HeartbeatError(
            type: HeartbeatErrorType.heartbeatStale,
            message:
                'Stale heartbeat detected from: ${result.staleParticipants.join(", ")}',
          ),
        );
        return;
      }

      // Check for operation in cleanup/failed state
      await _refreshCache();
      if (_cachedData?.operationState == OperationState.cleanup ||
          _cachedData?.operationState == OperationState.failed) {
        _signalFailure(
          OperationFailedInfo(
            operationId: operationId,
            failedAt: DateTime.now(),
            reason: 'Operation entered ${_cachedData?.operationState} state',
            crashedCallIds: result.staleParticipants,
          ),
        );
      }

      // Success callback
      _onHeartbeatSuccess?.call(this, result);
    } catch (e) {
      _onHeartbeatError?.call(
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
      _signalFailure(
        OperationFailedInfo(
          operationId: operationId,
          failedAt: DateTime.now(),
          reason: 'Stale heartbeat detected for ${crashedCallIds.length} calls',
          crashedCallIds: crashedCallIds,
        ),
      );
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
      final data = LedgerData.fromJson(
        json.decode(content) as Map<String, dynamic>,
      );

      // Copy the data before modification for the result
      final dataBefore = LedgerData.fromJson(data.toJson());

      // Calculate global heartbeat age before updating (for backward compatibility)
      final heartbeatAge = DateTime.now()
          .difference(data.lastHeartbeat)
          .inMilliseconds;

      // Collect per-participant heartbeat ages BEFORE updating
      final participantAges = <String, int>{};
      final staleParticipants = <String>[];

      for (final frame in data.callFrames) {
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

      // Update THIS participant's heartbeat in their call frame
      for (final frame in data.callFrames) {
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
        callFrameCount: data.callFrames.length,
        tempResourceCount: data.tempResources.length,
        heartbeatAgeMs: heartbeatAge,
        isStale: hasStaleOther, // Now true only if OTHER participants are stale
        participants: data.callFrames.map((f) => f.participantId).toList(),
        participantHeartbeatAges: participantAges,
        staleParticipants: staleParticipants
            .where((p) => p != participantId)
            .toList(),
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
  // Leave operation (decrements join count)
  // ─────────────────────────────────────────────────────────────

  /// Leave the operation (decrements the join count).
  ///
  /// A participant may join the same operation multiple times when handling
  /// multiple calls. Each join increments the join count, and each leave
  /// decrements it.
  ///
  /// When the join count reaches 0:
  /// - The heartbeat is automatically stopped
  /// - The operation is unregistered from this participant's ledger
  ///
  /// This is the counterpart to [Ledger.joinOperation]. Call this when
  /// finished with a call/task for this operation.
  ///
  /// Throws [StateError] if:
  /// - Join count is already 0
  /// - There are still active spawned calls (must be ended or cancelled first)
  ///
  /// Example:
  /// ```dart
  /// // First call joins the operation
  /// final op = await ledger.joinOperation(operationId: opId);
  /// // ... do work for first call ...
  /// op.leave(); // join count: 1 -> 0, heartbeat stops
  /// ```
  ///
  /// For multiple joins:
  /// ```dart
  /// final op1 = await ledger.joinOperation(operationId: opId);
  /// final op2 = await ledger.joinOperation(operationId: opId); // Same op
  /// // join count is now 2
  /// op1.leave(); // join count: 2 -> 1, heartbeat continues
  /// op2.leave(); // join count: 1 -> 0, heartbeat stops
  /// ```
  void leave() {
    if (_joinCount <= 0) {
      throw StateError('Cannot leave operation - join count is already 0');
    }

    // Check for active spawned calls
    final activeSpawnedCalls = _activeCalls.values
        .where((c) => c.isSpawned)
        .toList();
    if (activeSpawnedCalls.isNotEmpty) {
      final callIds = activeSpawnedCalls.map((c) => c.callId).join(', ');
      throw StateError(
        'Cannot leave operation - ${activeSpawnedCalls.length} spawned call(s) '
        'still active: [$callIds]. End or cancel all calls before leaving.',
      );
    }

    _joinCount--;

    if (_joinCount == 0) {
      stopHeartbeat();
      _ledger._unregisterOperation(operationId);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Complete operation
  // ─────────────────────────────────────────────────────────────

  /// Complete the operation (for initiator only).
  ///
  /// This:
  /// 1. Stops the heartbeat
  /// 2. Logs the completion
  /// 3. Moves the operation files to the backup folder
  /// 4. Unregisters the operation from the ledger
  ///
  /// **Note:** This is different from [leave], which is for
  /// participants who joined an operation. Initiators should call
  /// [complete] when the operation is done.
  ///
  /// Example:
  /// ```dart
  /// final op = await ledger.createOperation();
  /// // ... do work ...
  /// await op.complete(); // Archives the operation
  /// ```
  Future<void> complete() async {
    if (!isInitiator) {
      throw StateError('Only the initiator can complete an operation');
    }
    stopHeartbeat();
    _joinCount = 0; // Reset join count

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
/// final ledger = LocalLedger(
///   basePath: '/tmp/ledger',
///   participantId: 'orchestrator',
/// );
/// final op = await ledger.createOperation(); // Uses ledger's participantId
/// ```
///
/// **Simulation pattern (multiple identities per Ledger):**
/// ```dart
/// final ledger = LocalLedger(basePath: '/tmp/ledger');
/// final cliOp = await ledger.createOperation(participantId: 'cli');
/// final bridgeOp = await ledger.joinOperation(
///   operationId: opId,
///   participantId: 'bridge',
/// );
/// ```
class LocalLedger extends Ledger {
  final String basePath;

  /// The participant ID for this ledger instance.
  ///
  /// This identifies who is interacting with the ledger. Each participant
  /// (CLI, Bridge, VS Code, etc.) should have its own unique ID.
  @override
  final String participantId;

  /// The process ID for this participant.
  ///
  /// Defaults to the current process PID if not specified in constructor.
  @override
  final int participantPid;

  /// Grouped callbacks for ledger events.
  final LedgerCallback? callback;

  // Private getters for internal use
  void Function(String)? get _backupCallback => callback?.onBackupCreated;
  void Function(String)? get _logCallback => callback?.onLogLine;
  HeartbeatErrorCallback? get _globalHeartbeatCallback =>
      callback?.onGlobalHeartbeatError;

  /// Maximum number of backup operations to retain.
  @override
  final int maxBackups;

  late final Directory _ledgerDir;
  late final Directory _backupDir;

  /// Registry of all active internal operations in this ledger.
  final Map<String, _LedgerOperation> _operations = {};

  /// Global heartbeat timer.
  Timer? _globalHeartbeatTimer;

  /// Lock timeout for detecting stale locks.
  final Duration lockTimeout;

  /// Initial lock retry interval (used with exponential backoff).
  final Duration lockRetryInterval;

  /// Maximum lock retry interval (caps exponential backoff).
  final Duration maxLockRetryInterval;

  /// Heartbeat interval for global monitoring.
  @override
  final Duration heartbeatInterval;

  /// Staleness threshold for detecting crashed operations.
  @override
  final Duration staleThreshold;

  /// Creates a new Ledger instance.
  ///
  /// **Example usage with callback:**
  /// ```dart
  /// final ledger = LocalLedger(
  ///   basePath: '/tmp/ledger',
  ///   participantId: 'cli',
  ///   callback: LedgerCallback(
  ///     onBackupCreated: (path) => print('Backup: $path'),
  ///     onLogLine: (line) => print('Log: $line'),
  ///   ),
  /// );
  /// ```
  LocalLedger({
    required this.basePath,
    required this.participantId,
    int? participantPid,
    this.callback,
    this.maxBackups = 20,
    this.heartbeatInterval = const Duration(seconds: 5),
    this.staleThreshold = const Duration(seconds: 15),
    this.lockTimeout = const Duration(seconds: 2),
    this.lockRetryInterval = const Duration(milliseconds: 50),
    this.maxLockRetryInterval = const Duration(milliseconds: 500),
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
    final random = Random()
        .nextInt(0xFFFFFFFF)
        .toRadixString(16)
        .padLeft(8, '0');
    return '$timestamp-$participantId-$random';
  }

  /// Pattern for valid operation IDs.
  ///
  /// Only allows alphanumeric characters, hyphens, underscores, colons, and dots.
  /// Prevents path traversal attacks via `..` or `/` sequences.
  static final _validOperationIdPattern = RegExp(r'^[a-zA-Z0-9_\-:.]+$');

  /// Validates that an operation ID is safe for use in file paths.
  ///
  /// Throws [ArgumentError] if the operation ID contains invalid characters
  /// or could be used for path traversal.
  void _validateOperationId(String operationId) {
    if (operationId.isEmpty) {
      throw ArgumentError.value(
        operationId,
        'operationId',
        'Operation ID cannot be empty',
      );
    }
    if (operationId.contains('..') || operationId.contains('/')) {
      throw ArgumentError.value(
        operationId,
        'operationId',
        'Operation ID contains invalid path characters',
      );
    }
    if (!_validOperationIdPattern.hasMatch(operationId)) {
      throw ArgumentError.value(
        operationId,
        'operationId',
        'Operation ID contains invalid characters',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Locking
  // ─────────────────────────────────────────────────────────────

  /// Acquires an exclusive lock on the operation file.
  ///
  /// The lock file contains participant ID, PID, and timestamp for crash
  /// detection. If a stale lock is found (older than [lockTimeout]), the
  /// method checks if the lock owner has crashed by examining the operation
  /// file. If the participant has crashed, the stale lock is removed.
  ///
  /// Uses exponential backoff for retries, starting at [lockRetryInterval]
  /// and capping at [maxLockRetryInterval].
  Future<bool> _acquireLock(String operationId) async {
    final lockFile = File(_lockPath(operationId));
    final startTime = DateTime.now();
    var currentRetryInterval = lockRetryInterval;

    while (true) {
      try {
        if (lockFile.existsSync()) {
          final staleLockRemoved = await _handleStaleLock(
            operationId,
            lockFile,
          );
          if (!staleLockRemoved) {
            // Lock exists and is not stale (or stale but owner not crashed)
            // Wait and retry with exponential backoff
            if (DateTime.now().difference(startTime) > lockTimeout) {
              return false;
            }
            await Future.delayed(currentRetryInterval);
            // Exponential backoff with cap
            currentRetryInterval = Duration(
              milliseconds: (currentRetryInterval.inMilliseconds * 1.5).toInt(),
            );
            if (currentRetryInterval > maxLockRetryInterval) {
              currentRetryInterval = maxLockRetryInterval;
            }
            continue;
          }
        }

        await lockFile.create(exclusive: true);
        await lockFile.writeAsString(
          '{"participantId": "$participantId", "pid": $pid, '
          '"timestamp": "${DateTime.now().toIso8601String()}"}',
        );
        return true;
      } catch (e) {
        if (DateTime.now().difference(startTime) > lockTimeout) {
          return false;
        }
        await Future.delayed(currentRetryInterval);
        // Exponential backoff with cap
        currentRetryInterval = Duration(
          milliseconds: (currentRetryInterval.inMilliseconds * 1.5).toInt(),
        );
        if (currentRetryInterval > maxLockRetryInterval) {
          currentRetryInterval = maxLockRetryInterval;
        }
      }
    }
  }

  /// Handles a potentially stale lock file.
  ///
  /// Returns `true` if the lock was removed (allowing caller to proceed),
  /// `false` if the lock should be respected.
  Future<bool> _handleStaleLock(String operationId, File lockFile) async {
    final stat = lockFile.statSync();
    final age = DateTime.now().difference(stat.modified);

    if (age <= lockTimeout) {
      // Lock is fresh, respect it
      return false;
    }

    // Lock is stale - check if owner has crashed
    try {
      final lockContent = lockFile.readAsStringSync();
      final lockData = jsonDecode(lockContent) as Map<String, dynamic>;
      final lockParticipantId = lockData['participantId'] as String?;
      final lockPid = lockData['pid'] as int?;

      if (lockParticipantId != null) {
        // Check if this participant has crashed in the operation file
        final opFile = File(_operationPath(operationId));
        if (opFile.existsSync()) {
          final opContent = opFile.readAsStringSync();
          final opData = LedgerData.fromJson(jsonDecode(opContent));

          // Find the participant's frame(s) and check their heartbeat
          final participantFrames = opData.callFrames
              .where((f) => f.participantId == lockParticipantId)
              .toList();

          if (participantFrames.isNotEmpty) {
            // Check if all frames from this participant are stale
            final now = DateTime.now();
            final allStale = participantFrames.every((frame) {
              final frameAge = now.difference(frame.lastHeartbeat);
              return frameAge > staleThreshold;
            });

            if (allStale) {
              // Participant has crashed - safe to remove stale lock
              callback?.onLogLine?.call(
                '[Ledger] Removing stale lock from crashed participant '
                '$lockParticipantId (PID: $lockPid)',
              );
              lockFile.deleteSync();
              return true;
            }
          } else {
            // Participant has no frames - maybe it finished but crashed before
            // releasing lock. Safe to remove.
            lockFile.deleteSync();
            return true;
          }
        } else {
          // Operation file doesn't exist - lock is orphaned, remove it
          lockFile.deleteSync();
          return true;
        }
      } else {
        // Old lock format without participantId - use file age only
        lockFile.deleteSync();
        return true;
      }
    } catch (e) {
      // Error reading lock file - use file age as fallback
      lockFile.deleteSync();
      return true;
    }

    // Lock owner is not crashed (heartbeat is fresh), respect the lock
    return false;
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
    String operationId,
    String elapsedFormatted,
  ) async {
    final sourceFile = File(_operationPath(operationId));
    if (!sourceFile.existsSync()) return '';

    final snapshotPath = _trailSnapshotPath(operationId, elapsedFormatted);
    final trailDir = Directory(_trailPath(operationId));
    if (!trailDir.existsSync()) {
      await trailDir.create(recursive: true);
    }

    await sourceFile.copy(snapshotPath);
    _backupCallback?.call(snapshotPath);
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
    final folders = _backupDir.listSync().whereType<Directory>().toList();

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
  /// **Automatic heartbeat management:** The heartbeat is automatically
  /// started when the operation is created. Call [Operation.complete] to
  /// complete the operation, which stops the heartbeat and moves files
  /// to backup.
  ///
  /// **Heartbeat callbacks:** Optionally provide an [OperationCallback] with
  /// [OperationCallback.onHeartbeatSuccess] and/or
  /// [OperationCallback.onHeartbeatError] for monitoring and failure detection.
  ///
  /// The participant identity is taken from the Ledger constructor:
  /// ```dart
  /// final ledger = LocalLedger(basePath: path, participantId: 'orchestrator');
  /// final op = await ledger.createOperation(
  ///   callback: OperationCallback(
  ///     onHeartbeatError: (op, error) => print('Failure: ${error.message}'),
  ///   ),
  /// );
  /// // ... do work ...
  /// await op.complete(); // Stops heartbeat and archives files
  /// ```
  ///
  /// An operation ID will be auto-generated based on timestamp and
  /// participantId.
  @override
  Future<LocalOperation> createOperation({
    String? description,
    OperationCallback? callback,
  }) async {
    final operationId = _generateOperationId(participantId);
    return await _startOperationWithId(
      operationId: operationId,
      participantId: participantId,
      participantPid: participantPid,
      description: description,
      callback: callback,
    );
  }

  Future<LocalOperation> _startOperationWithId({
    required String operationId,
    required String participantId,
    required int participantPid,
    String? description,
    OperationCallback? callback,
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

      // Create internal operation object
      final ledgerOp = _LedgerOperation._(
        ledger: this,
        operationId: operationId,
        participantId: participantId,
        pid: participantPid,
        isInitiator: true,
        startTime: timestamp,
      );
      ledgerOp._cachedData = ledgerData;
      ledgerOp._lastChangeTimestamp = timestamp;

      // Register in global registry
      _operations[operationId] = ledgerOp;

      // Create session and wrap in Operation
      final sessionId = ledgerOp._createSession();
      final operation = LocalOperation._(ledgerOp, sessionId);

      // Auto-start heartbeat for initiator with optional callbacks
      operation.startHeartbeat(
        interval: heartbeatInterval,
        onSuccess: callback?.onHeartbeatSuccess,
        onError: callback?.onHeartbeatError,
      );

      // Wire up abort and failure callbacks
      if (callback?.onAbort != null) {
        unawaited(
          ledgerOp.onAbort.then((_) {
            callback!.onAbort!(operation);
          }),
        );
      }
      if (callback?.onFailure != null) {
        unawaited(
          operation.onFailure.then((info) {
            callback!.onFailure!(operation, info);
          }),
        );
      }

      return operation;
    } finally {
      await _releaseLock(operationId);
    }
  }

  /// Join an existing operation.
  ///
  /// Returns an [Operation] object for the participant to interact with.
  /// Each call returns a new Operation with its own session, even if joining
  /// the same operation multiple times.
  ///
  /// **Session tracking:** Each Operation tracks its own calls. Use
  /// [Operation.getPendingSpawnedCalls] to see spawned calls from this session,
  /// [Operation.hasPendingCalls] to check for any pending calls,
  /// and [Operation.leave] to leave with optional call cancellation.
  ///
  /// **Automatic heartbeat management:** The heartbeat is automatically
  /// started on first join and stopped when the last session leaves.
  ///
  /// **Heartbeat callbacks:** Optionally provide an [OperationCallback] with
  /// [OperationCallback.onHeartbeatSuccess] and/or
  /// [OperationCallback.onHeartbeatError] for monitoring and failure detection.
  ///
  /// The participant identity is taken from the Ledger constructor:
  /// ```dart
  /// final ledger = LocalLedger(basePath: path, participantId: 'worker_1');
  /// final op = await ledger.joinOperation(
  ///   operationId: opId,
  ///   callback: OperationCallback(
  ///     onHeartbeatError: (op, error) => print('Failure: ${error.message}'),
  ///   ),
  /// );
  /// // ... do work ...
  /// op.leave(); // Stops heartbeat when no sessions remain
  /// ```
  @override
  Future<LocalOperation> joinOperation({
    required String operationId,
    OperationCallback? callback,
  }) async {
    // Validate operationId to prevent path traversal attacks
    _validateOperationId(operationId);

    // Check if already have an internal _LedgerOperation for this operationId
    var ledgerOp = _operations[operationId];
    final isFirstJoin = ledgerOp == null;

    if (isFirstJoin) {
      // First join - create new _LedgerOperation
      final joinTime = DateTime.now();

      ledgerOp = _LedgerOperation._(
        ledger: this,
        operationId: operationId,
        participantId: participantId,
        pid: participantPid,
        isInitiator: false,
        startTime: joinTime,
      );

      // Load current state
      await ledgerOp._refreshCache();

      // Register in global registry
      _operations[operationId] = ledgerOp;
    }

    // Create a new session and wrap in Operation
    final sessionId = ledgerOp._createSession();
    final operation = LocalOperation._(ledgerOp, sessionId);

    // Start heartbeat on first join with optional callbacks
    if (isFirstJoin) {
      operation.startHeartbeat(
        interval: heartbeatInterval,
        onSuccess: callback?.onHeartbeatSuccess,
        onError: callback?.onHeartbeatError,
      );
    }

    // Wire up abort and failure callbacks (for each join)
    if (callback?.onAbort != null) {
      unawaited(
        ledgerOp.onAbort.then((_) {
          callback!.onAbort!(operation);
        }),
      );
    }
    if (callback?.onFailure != null) {
      unawaited(
        ledgerOp.onFailure.then((info) {
          callback!.onFailure!(operation, info);
        }),
      );
    }

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
      final ledgerData = LedgerData.fromJson(
        json.decode(content) as Map<String, dynamic>,
      );

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
        final ledgerData = LedgerData.fromJson(
          json.decode(content) as Map<String, dynamic>,
        );
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

    _backupCallback?.call(_backupFolderPath(operationId));
  }

  // ─────────────────────────────────────────────────────────────
  // Log file operations
  // ─────────────────────────────────────────────────────────────

  /// Append a line to the operation's log file.
  Future<void> _appendLog(String operationId, String line) async {
    final logFile = File(_logPath(operationId));
    await logFile.writeAsString('$line\n', mode: FileMode.append, flush: true);
    _logCallback?.call(line);
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
      final ledgerOp = entry.value;
      final lastChange = ledgerOp._lastChangeTimestamp;

      // Create a temporary session-less Operation for the callback
      // Uses session ID 0 to indicate this is a global monitoring context
      final operation = LocalOperation._(ledgerOp, 0);

      if (lastChange == null) {
        _globalHeartbeatCallback?.call(
          operation,
          HeartbeatError(
            type: HeartbeatErrorType.ledgerNotFound,
            message: 'Operation ${ledgerOp.operationId} has no cached data',
          ),
        );
        continue;
      }

      final age = now.difference(lastChange);
      if (age > staleThreshold) {
        _globalHeartbeatCallback?.call(
          operation,
          HeartbeatError(
            type: HeartbeatErrorType.heartbeatStale,
            message:
                'Operation ${ledgerOp.operationId} is stale (${age.inSeconds}s)',
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Internal API for server use with custom participantId
  // ─────────────────────────────────────────────────────────────

  /// Create a new operation on behalf of a remote client.
  ///
  /// **Server use only:** This method allows the server to create operations
  /// on behalf of remote clients, using the client's participantId.
  ///
  /// The [participantId] should be the remote client's identifier.
  /// The [participantPid] is optional; defaults to -1 for remote clients.
  Future<LocalOperation> _createOperationForClient({
    required String participantId,
    int participantPid = -1,
    String? description,
    OperationCallback? callback,
  }) async {
    final operationId = _generateOperationId(participantId);
    return await _startOperationWithId(
      operationId: operationId,
      participantId: participantId,
      participantPid: participantPid,
      description: description,
      callback: callback,
    );
  }

  /// Join an existing operation on behalf of a remote client.
  ///
  /// **Server use only:** This method allows the server to join operations
  /// on behalf of remote clients, using the client's participantId.
  ///
  /// The [participantId] should be the remote client's identifier.
  /// The [participantPid] is optional; defaults to -1 for remote clients.
  ///
  /// Throws [StateError] if the operation does not exist.
  Future<LocalOperation> _joinOperationForClient({
    required String operationId,
    required String participantId,
    int participantPid = -1,
    OperationCallback? callback,
  }) async {
    // Check if already have an internal _LedgerOperation for this operationId
    var ledgerOp = _operations[operationId];
    final isFirstJoin = ledgerOp == null;

    if (isFirstJoin) {
      // Verify the operation exists before joining
      final existingData = await _readOperation(operationId);
      if (existingData == null) {
        throw StateError('Operation not found: $operationId');
      }

      // First join - create new _LedgerOperation
      final joinTime = DateTime.now();

      ledgerOp = _LedgerOperation._(
        ledger: this,
        operationId: operationId,
        participantId: participantId,
        pid: participantPid,
        isInitiator: false,
        startTime: joinTime,
      );

      // Load current state (we know it exists now)
      await ledgerOp._refreshCache();

      // Register in global registry
      _operations[operationId] = ledgerOp;
    }

    // Create a new session and wrap in Operation
    final sessionId = ledgerOp._createSession();
    final operation = LocalOperation._(ledgerOp, sessionId);

    // Start heartbeat on first join with optional callbacks
    if (isFirstJoin) {
      operation.startHeartbeat(
        interval: heartbeatInterval,
        onSuccess: callback?.onHeartbeatSuccess,
        onError: callback?.onHeartbeatError,
      );
    }

    // Wire up abort and failure callbacks (for each join)
    if (callback?.onAbort != null) {
      unawaited(
        ledgerOp.onAbort.then((_) {
          callback!.onAbort!(operation);
        }),
      );
    }
    if (callback?.onFailure != null) {
      unawaited(
        ledgerOp.onFailure.then((info) {
          callback!.onFailure!(operation, info);
        }),
      );
    }

    return operation;
  }

  /// Get an operation by ID (for server use).
  ///
  /// **Server use only:** Returns the internal [LocalOperation] for the given
  /// operation ID, or null if not found.
  LocalOperation? _getOperationForServer(String operationId) {
    final ledgerOp = _operations[operationId];
    if (ledgerOp == null) return null;
    // Create an Operation with session 0 (server context)
    return LocalOperation._(ledgerOp, 0);
  }

  /// Get the internal ledger operation for direct access.
  ///
  /// **Server use only:** Returns the internal [_LedgerOperation] for
  /// low-level operations like deleteCallFrame.
  _LedgerOperation? _getInternalOperation(String operationId) {
    return _operations[operationId];
  }

  /// Dispose of the ledger and stop all heartbeats.
  @override
  void dispose() {
    _stopGlobalHeartbeat();
    for (final operation in _operations.values) {
      operation.stopHeartbeat();
    }
    _operations.clear();
  }
}
