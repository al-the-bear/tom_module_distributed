import 'dart:async';

import '../ledger_api/ledger_api.dart';
import 'simulation_config.dart';

/// Handles formatted output for the async simulation.
class AsyncSimulationPrinter {
  final Stopwatch _stopwatch = Stopwatch();
  final List<String> output = [];
  final void Function(String)? onLog;

  AsyncSimulationPrinter({this.onLog}) {
    _stopwatch.start();
  }

  /// Format elapsed time as 'sss.mmm'.
  String get elapsedFormatted {
    final ms = _stopwatch.elapsedMilliseconds;
    final seconds = ms ~/ 1000;
    final millis = ms % 1000;
    return '${seconds.toString().padLeft(3, '0')}.${millis.toString().padLeft(3, '0')}';
  }

  int get elapsedMs => _stopwatch.elapsedMilliseconds;

  /// Print a message with timestamp and indentation.
  void log({
    required int depth,
    required String participant,
    required String message,
  }) {
    final indent = '    ' * depth;
    final time = elapsedFormatted;
    final line = '$time | $indent[$participant] $message';
    output.add(line);
    print(line);
    onLog?.call(line);
  }

  /// Print a call from one participant to another.
  void logCall({
    required int depth,
    required String from,
    required String to,
    required String method,
  }) {
    log(depth: depth, participant: from, message: '→ [$to] $method');
  }

  /// Print a return from a call.
  void logReturn({
    required int depth,
    required String from,
    required String to,
    required String result,
  }) {
    log(depth: depth, participant: from, message: '← [$to] $result');
  }

  /// Print a heartbeat tick with detailed check information.
  void logHeartbeatDetailed({
    required int depth,
    required String participant,
    required HeartbeatResult result,
  }) {
    // Check 1: Ledger file exists
    log(
      depth: depth,
      participant: participant,
      message: '♥ [1/5] Ledger exists: ${result.ledgerExists ? "YES" : "NO"}',
    );

    // Check 2: Abort flag
    log(
      depth: depth,
      participant: participant,
      message:
          '♥ [2/5] Abort flag: ${result.abortFlag ? "TRUE → ABORTING" : "false"}',
    );

    // Check 3: Call frame count
    log(
      depth: depth,
      participant: participant,
      message:
          '♥ [3/5] Call frame count: ${result.callFrameCount} (${result.participants.join(" → ")})',
    );

    // Check 4: Temp resources
    log(
      depth: depth,
      participant: participant,
      message: '♥ [4/5] Temp resources: ${result.tempResourceCount}',
    );

    // Check 5: Heartbeat staleness
    final ageStr = '${result.heartbeatAgeMs}ms';
    log(
      depth: depth,
      participant: participant,
      message:
          '♥ [5/5] Heartbeat age: $ageStr ${result.isStale ? "→ STALE!" : "(fresh)"}',
    );

    // Summary line only for non-OK status
    if (result.abortFlag || result.isStale) {
      final status = result.abortFlag ? 'ABORT' : 'STALE';
      log(
        depth: depth,
        participant: participant,
        message: '♥ ──── heartbeat complete [$status] ────',
      );
    }
  }

  /// Print a simple heartbeat tick (legacy).
  void logHeartbeat({
    required int depth,
    required String participant,
    required bool abortFlag,
    required bool childrenAlive,
  }) {
    final status = abortFlag
        ? 'abort: TRUE → ABORTING'
        : 'abort: false, children: ${childrenAlive ? "alive" : "DEAD"}';
    log(
      depth: depth,
      participant: participant,
      message: '♥ heartbeat ($status)',
    );
  }

  /// Print a special event (like user abort).
  void logEvent({required String message}) {
    final line = '\n>>> $message <<<\n';
    output.add(line);
    print(line);
    onLog?.call(line);
  }

  /// Print a simulation header.
  void printHeader(String title) {
    final separator = '=' * 60;
    final lines = ['', separator, title, separator, ''];
    for (final line in lines) {
      output.add(line);
      print(line);
      onLog?.call(line);
    }
  }

  /// Print a phase header.
  void printPhase(String phase) {
    final separator = '-' * 40;
    final lines = ['', separator, phase, separator];
    for (final line in lines) {
      output.add(line);
      print(line);
      onLog?.call(line);
    }
  }

  /// Print phase completion.
  void printPhaseComplete(String status, String message) {
    final line = '\n[$status] $message\n';
    output.add(line);
    print(line);
    onLog?.call(line);
  }

  /// Print a file operation.
  void logFileOp({
    required int depth,
    required String participant,
    required String operation,
    required String path,
    String? backupPath,
  }) {
    final backup = backupPath != null ? ' → backup: $backupPath' : '';
    log(
      depth: depth,
      participant: participant,
      message: '$operation($path)$backup',
    );
  }

  /// Reset the stopwatch.
  void reset() {
    _stopwatch.reset();
    _stopwatch.start();
    output.clear();
  }

  /// Stop the stopwatch.
  void stop() {
    _stopwatch.stop();
  }
}

/// Base class for async simulated participants using the Ledger API.
abstract class AsyncSimParticipant {
  final String name;
  final int pid;
  final Ledger ledger;
  final AsyncSimulationPrinter printer;
  final SimulationConfig config;

  /// The operation handle for this participant.
  Operation? _operation;

  /// Current call depth (for logging).
  int _currentDepth = 0;

  AsyncSimParticipant({
    required this.name,
    required this.pid,
    required String basePath,
    required this.printer,
    required this.config,
    void Function(String)? onBackupCreated,
  }) : ledger = Ledger(
         basePath: basePath,
         participantId: name.toLowerCase(),
         participantPid: pid,
         callback: onBackupCreated != null
             ? LedgerCallback(onBackupCreated: onBackupCreated)
             : null,
       );

  /// Get the operation handle (throws if not set).
  Operation get operation =>
      _operation ?? (throw StateError('No operation registered'));

  /// Whether this participant has an active operation.
  bool get hasOperation => _operation != null;

  /// Whether this participant is aborted.
  bool get isAborted => _operation?.isAborted ?? false;

  /// Future that completes when abort is signaled.
  Future<void> get onAbort => _operation?.onAbort ?? Completer<void>().future;

  /// Get elapsed time formatted.
  String get elapsedFormatted => printer.elapsedFormatted;

  /// Set the current call depth.
  set currentDepth(int depth) => _currentDepth = depth;

  // ─────────────────────────────────────────────────────────────
  // Operation lifecycle (for initiator)
  // ─────────────────────────────────────────────────────────────

  /// Start a new operation (initiator only).
  ///
  /// Note: The [operationId] parameter is for logging only. The actual
  /// operation ID is auto-generated by the Ledger.
  Future<Operation> startOperation({
    required int depth,
    String? description,
  }) async {
    log(depth: depth, message: 'startOperation()');
    _currentDepth = depth;

    _operation = await ledger.createOperation(description: description);

    log(depth: depth, message: '  → operationId: "${_operation!.operationId}"');

    return _operation!;
  }

  /// Complete the operation (initiator only).
  Future<void> completeOperation({required int depth}) async {
    log(
      depth: depth,
      message: 'completeOperation(opId: "${operation.operationId}")',
    );
    await operation.complete();
    _operation = null;
  }

  // ─────────────────────────────────────────────────────────────
  // Operation lifecycle (for participants)
  // ─────────────────────────────────────────────────────────────

  /// Join an existing operation (participant).
  Future<Operation> joinOperation({
    required int depth,
    required String operationId,
  }) async {
    log(depth: depth, message: 'joinOperation(opId: "$operationId")');
    _currentDepth = depth;

    _operation = await ledger.joinOperation(operationId: operationId);

    return _operation!;
  }

  // ─────────────────────────────────────────────────────────────
  // Call execution
  // ─────────────────────────────────────────────────────────────

  /// Add a call frame for a call.
  Future<void> createCallFrame({
    required int depth,
    required String callId,
  }) async {
    log(depth: depth, message: 'createCallFrame(callId: "$callId", pid: $pid)');
    await operation.createCallFrame(callId: callId);
  }

  /// Remove a call frame for a call.
  Future<void> deleteCallFrame({
    required int depth,
    required String callId,
  }) async {
    log(depth: depth, message: 'deleteCallFrame(callId: "$callId")');
    await operation.deleteCallFrame(callId: callId);
  }

  // ─────────────────────────────────────────────────────────────
  // Heartbeat
  // ─────────────────────────────────────────────────────────────

  /// Start the heartbeat for this participant.
  void startHeartbeat({required int depth}) {
    log(depth: depth, message: 'startHeartbeat(intervalMs: 4000-5000)');
    _currentDepth = depth;

    operation.startHeartbeat(
      interval: const Duration(milliseconds: 4500),
      jitterMs: 500,
      onError: (op, error) {
        printer.log(
          depth: _currentDepth,
          participant: name,
          message: '♥ ERROR: ${error.message}',
        );
        if (error.type == HeartbeatErrorType.abortFlagSet) {
          // Already handled by Operation.triggerAbort
        }
      },
      onSuccess: (op, result) {
        printer.logHeartbeatDetailed(
          depth: _currentDepth,
          participant: name,
          result: result,
        );
      },
    );
  }

  /// Stop the heartbeat for this participant.
  void stopHeartbeat({required int depth}) {
    log(depth: depth, message: 'stopHeartbeat()');
    operation.stopHeartbeat();
  }

  // ─────────────────────────────────────────────────────────────
  // Abort
  // ─────────────────────────────────────────────────────────────

  /// Set the abort flag.
  Future<void> setAbortFlag({required int depth, required bool value}) async {
    log(
      depth: depth,
      message:
          'setAbortFlag(opId: "${operation.operationId}", aborted: $value)',
    );
    await operation.setAbortFlag(value);
    if (value) {
      operation.triggerAbort();
    }
  }

  /// Check if the operation is aborted.
  Future<bool> checkAbort({required int depth}) async {
    final aborted = await operation.checkAbort();
    if (aborted) {
      log(depth: depth, message: 'checkAbort() → ABORTED');
    }
    return aborted;
  }

  /// Trigger local abort for this participant.
  void triggerAbort() {
    operation.triggerAbort();
  }

  // ─────────────────────────────────────────────────────────────
  // Temp resources
  // ─────────────────────────────────────────────────────────────

  /// Register a temporary resource.
  Future<void> registerTempResource({
    required int depth,
    required String path,
  }) async {
    log(depth: depth, message: 'registerTempResource(path: "$path")');
    await operation.registerTempResource(path: path);
  }

  /// Unregister a temporary resource.
  Future<void> unregisterTempResource({
    required int depth,
    required String path,
  }) async {
    log(depth: depth, message: 'unregisterTempResource("$path")');
    await operation.unregisterTempResource(path: path);
  }

  // ─────────────────────────────────────────────────────────────
  // Logging helpers
  // ─────────────────────────────────────────────────────────────

  /// Log a message at the given depth.
  void log({required int depth, required String message}) {
    printer.log(depth: depth, participant: name, message: message);
  }

  /// Wait for a simulated duration (real time).
  Future<void> simulateWork({required Duration duration}) async {
    await Future.delayed(duration);
  }

  /// Check if we should abort and throw if so.
  Future<void> checkAbortOrThrow({required int depth}) async {
    final aborted = await checkAbort(depth: depth);
    if (aborted) {
      throw AbortedException(operation.operationId);
    }
  }
}

/// Exception thrown when operation is aborted.
class AbortedException implements Exception {
  final String operationId;
  AbortedException(this.operationId);

  @override
  String toString() => 'AbortedException: Operation $operationId was aborted';
}
