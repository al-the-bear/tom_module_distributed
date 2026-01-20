import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../local_ledger/file_ledger.dart';

/// Callback for getting elapsed time formatted string.
typedef ElapsedFormattedCallback = String Function();

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
  final ElapsedFormattedCallback getElapsedFormatted;
  final bool isInitiator;

  /// Cached operation data.
  LedgerData? _cachedData;

  /// Timestamp of last change to the operation file.
  DateTime? _lastChangeTimestamp;

  /// Heartbeat timer for this participant.
  Timer? _heartbeatTimer;

  /// Whether this participant is aborted.
  bool _isAborted = false;

  /// Callbacks for heartbeat events.
  HeartbeatErrorCallback? onHeartbeatError;
  HeartbeatSuccessCallback? onHeartbeatSuccess;

  /// Completer that signals abort.
  final Completer<void> _abortCompleter = Completer<void>();

  Operation._({
    required Ledger ledger,
    required this.operationId,
    required this.participantId,
    required this.pid,
    required this.getElapsedFormatted,
    required this.isInitiator,
  }) : _ledger = ledger;

  /// Get the cached operation data.
  LedgerData? get cachedData => _cachedData;

  /// Get the last change timestamp.
  DateTime? get lastChangeTimestamp => _lastChangeTimestamp;

  /// Whether this participant is aborted.
  bool get isAborted => _isAborted;

  /// Future that completes when abort is signaled.
  Future<void> get onAbort => _abortCompleter.future;

  /// Get the current elapsed time formatted.
  String get elapsedFormatted => getElapsedFormatted();

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

  /// Log a single line to the operation's log file.
  Future<void> log(String line) async {
    await _ledger._appendLog(operationId, line);
  }

  /// Log multiple lines to the operation's log file.
  Future<void> logLines(List<String> lines) async {
    await _ledger._appendLogLines(operationId, lines);
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
  // Call execution management
  // ─────────────────────────────────────────────────────────────

  /// Start tracking a call execution (push stack frame).
  Future<void> startCallExecution({
    required String callId,
  }) async {
    final updated = await _ledger._modifyOperation(
      operationId: operationId,
      elapsedFormatted: elapsedFormatted,
      updater: (data) {
        data.stack.add(StackFrame(
          participantId: participantId,
          callId: callId,
          pid: pid,
          startTime: DateTime.now(),
        ));
        data.lastHeartbeat = DateTime.now();
        return data;
      },
    );
    if (updated != null) _updateCache(updated);
  }

  /// End tracking a call execution (pop stack frame).
  Future<void> endCallExecution({
    required String callId,
  }) async {
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

      // Check for stale heartbeat
      if (result.isStale) {
        onHeartbeatError?.call(
          this,
          HeartbeatError(
            type: HeartbeatErrorType.heartbeatStale,
            message: 'Heartbeat is stale (${result.heartbeatAgeMs}ms)',
          ),
        );
        // Don't return - still call success callback
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

  Future<HeartbeatResult?> _performHeartbeatWithChecks() async {
    final acquired = await _ledger._acquireLock(operationId);
    if (!acquired) return null;

    try {
      final file = File(_ledger._operationPath(operationId));
      if (!file.existsSync()) return null;

      // Create backup
      await _ledger._createBackup(operationId, elapsedFormatted);

      // Read current state
      final content = await file.readAsString();
      final data =
          LedgerData.fromJson(json.decode(content) as Map<String, dynamic>);

      // Calculate heartbeat age before updating
      final heartbeatAge =
          DateTime.now().difference(data.lastHeartbeat).inMilliseconds;
      final isStale = heartbeatAge > 10000;

      // Update heartbeat
      data.lastHeartbeat = DateTime.now();

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
        isStale: isStale,
        stackParticipants: data.stack.map((f) => f.participantId).toList(),
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

  // ─────────────────────────────────────────────────────────────
  // Complete operation
  // ─────────────────────────────────────────────────────────────

  /// Complete the operation (for initiator only).
  ///
  /// This moves the operation file to the trail folder and
  /// unregisters it from the ledger.
  Future<void> complete() async {
    if (!isInitiator) {
      throw StateError('Only the initiator can complete an operation');
    }
    stopHeartbeat();
    await _ledger._completeOperation(
      operationId: operationId,
      elapsedFormatted: elapsedFormatted,
    );
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
class Ledger {
  final String basePath;
  final void Function(String)? onBackupCreated;
  final void Function(String)? onLogLine;

  late final Directory _ledgerDir;

  /// Registry of all active operations in this ledger.
  final Map<String, Operation> _operations = {};

  /// Global heartbeat timer.
  Timer? _globalHeartbeatTimer;

  /// Callback for global heartbeat errors.
  HeartbeatErrorCallback? onGlobalHeartbeatError;

  /// Lock timeout and retry settings.
  static const _lockTimeout = Duration(seconds: 2);
  static const _lockRetryInterval = Duration(milliseconds: 50);

  Ledger({
    required this.basePath,
    this.onBackupCreated,
    this.onLogLine,
  }) {
    _ledgerDir = Directory(basePath);
    if (!_ledgerDir.existsSync()) {
      _ledgerDir.createSync(recursive: true);
    }
  }

  /// Get all active operations.
  Map<String, Operation> get operations => Map.unmodifiable(_operations);

  /// Get an operation by ID.
  Operation? getOperation(String operationId) => _operations[operationId];

  // ─────────────────────────────────────────────────────────────
  // Path helpers
  // ─────────────────────────────────────────────────────────────

  String _operationPath(String operationId) =>
      '$basePath/$operationId.json';

  String _lockPath(String operationId) =>
      '$basePath/$operationId.json.lock';

  String _trailPath(String operationId) =>
      '$basePath/${operationId}_trail';

  String _backupPath(String operationId, String elapsedFormatted) =>
      '${_trailPath(operationId)}/${elapsedFormatted}_$operationId.json';

  String _logPath(String operationId) =>
      '$basePath/${operationId}_log.txt';

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
        if (DateTime.now().difference(startTime) > const Duration(seconds: 1)) {
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
  // Backup
  // ─────────────────────────────────────────────────────────────

  Future<String> _createBackup(String operationId, String elapsedFormatted) async {
    final sourceFile = File(_operationPath(operationId));
    if (!sourceFile.existsSync()) return '';

    final backupPath = _backupPath(operationId, elapsedFormatted);
    final trailDir = Directory(_trailPath(operationId));
    if (!trailDir.existsSync()) {
      await trailDir.create(recursive: true);
    }

    await sourceFile.copy(backupPath);
    onBackupCreated?.call(backupPath);
    return backupPath;
  }

  // ─────────────────────────────────────────────────────────────
  // Operation lifecycle
  // ─────────────────────────────────────────────────────────────

  /// Start a new operation (for the initiator).
  ///
  /// Creates the operation file and returns an [Operation] object
  /// that can be used to interact with the operation.
  Future<Operation> startOperation({
    required String operationId,
    required int initiatorPid,
    required String participantId,
    required ElapsedFormattedCallback getElapsedFormatted,
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
        lastHeartbeat: timestamp,
      );

      // Add initiator frame
      ledgerData.stack.add(StackFrame(
        participantId: 'initiator',
        callId: 'root',
        pid: initiatorPid,
        startTime: timestamp,
      ));

      // Write initial file
      final file = File(_operationPath(operationId));
      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(ledgerData.toJson()));

      // Create operation object
      final operation = Operation._(
        ledger: this,
        operationId: operationId,
        participantId: participantId,
        pid: initiatorPid,
        getElapsedFormatted: getElapsedFormatted,
        isInitiator: true,
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

  /// Participate in an existing operation.
  ///
  /// Returns an [Operation] object for the participant to interact with.
  Future<Operation> participateInOperation({
    required String operationId,
    required int participantPid,
    required String participantId,
    required ElapsedFormattedCallback getElapsedFormatted,
  }) async {
    // Create operation object
    final operation = Operation._(
      ledger: this,
      operationId: operationId,
      participantId: participantId,
      pid: participantPid,
      getElapsedFormatted: getElapsedFormatted,
      isInitiator: false,
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

      // Create backup
      await _createBackup(operationId, elapsedFormatted);

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

  /// Complete an operation - move file to trail.
  Future<void> _completeOperation({
    required String operationId,
    required String elapsedFormatted,
  }) async {
    final acquired = await _acquireLock(operationId);
    if (!acquired) return;

    try {
      final file = File(_operationPath(operationId));
      if (!file.existsSync()) return;

      // Update status to 'completed'
      final content = await file.readAsString();
      final ledgerData =
          LedgerData.fromJson(json.decode(content) as Map<String, dynamic>);
      ledgerData.status = 'completed';

      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(ledgerData.toJson()));

      // Ensure trail directory exists
      final trailDir = Directory(_trailPath(operationId));
      if (!trailDir.existsSync()) {
        await trailDir.create(recursive: true);
      }

      // Move to trail folder as final file
      final finalPath =
          '${_trailPath(operationId)}/${elapsedFormatted}_final_$operationId.json';
      await file.rename(finalPath);
      onBackupCreated?.call(finalPath);

      // Unregister
      _unregisterOperation(operationId);
    } finally {
      await _releaseLock(operationId);
    }
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

  /// Append multiple lines to the operation's log file.
  Future<void> _appendLogLines(String operationId, List<String> lines) async {
    if (lines.isEmpty) return;
    final logFile = File(_logPath(operationId));
    final content = lines.map((l) => '$l\n').join();
    await logFile.writeAsString(content, mode: FileMode.append, flush: true);
    for (final line in lines) {
      onLogLine?.call(line);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Global heartbeat
  // ─────────────────────────────────────────────────────────────

  /// Start the global heartbeat that monitors all operations.
  ///
  /// The global heartbeat checks each registered operation's cached
  /// last change timestamp to detect stale operations.
  void startGlobalHeartbeat({
    Duration interval = const Duration(seconds: 5),
    Duration staleThreshold = const Duration(seconds: 15),
    HeartbeatErrorCallback? onError,
  }) {
    onGlobalHeartbeatError = onError;

    _globalHeartbeatTimer?.cancel();
    _globalHeartbeatTimer = Timer.periodic(interval, (_) {
      _checkAllOperations(staleThreshold);
    });
  }

  /// Stop the global heartbeat.
  void stopGlobalHeartbeat() {
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
    stopGlobalHeartbeat();
    for (final operation in _operations.values) {
      operation.stopHeartbeat();
    }
    _operations.clear();
  }
}
