import 'dart:async';

import 'async_simulation.dart';
import '../ledger_api/ledger_api.dart';

export 'scenario.dart'
    show
        FailureInjection,
        FailurePhase,
        FailingParticipant,
        FailureType,
        ScenarioCall,
        SimulationScenario,
        ScenarioResult;
export 'async_simulation.dart' show AbortedException;

// ─────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────

/// Types of failures that can be detected through heartbeat monitoring.
enum DetectedFailureType {
  /// Abort flag was set in the ledger.
  abortRequested,

  /// Heartbeat timestamp is stale (child crashed).
  staleHeartbeat,

  /// Expected child frame disappeared from stack.
  childDisappeared,

  /// Heartbeat operation failed (ledger error).
  heartbeatError,

  /// User triggered abort (Ctrl+C).
  userAbort,
}

/// Information about a detected failure.
class FailureDetection {
  final DetectedFailureType type;
  final String participant;
  final String message;

  FailureDetection({
    required this.type,
    required this.participant,
    required this.message,
  });

  @override
  String toString() => 'FailureDetection($type by $participant: $message)';
}

/// An event that occurred during scenario execution.
class ScenarioEvent {
  final int timestampMs;
  final String description;

  ScenarioEvent(this.timestampMs, this.description);

  @override
  String toString() => '${timestampMs}ms: $description';
}

/// Result of a concurrent scenario run.
class ConcurrentScenarioResult {
  final bool success;
  final FailureDetection? detectedFailure;
  final String? errorMessage;
  final List<ScenarioEvent> events;
  final Duration elapsed;
  final List<String> log;

  ConcurrentScenarioResult({
    required this.success,
    this.detectedFailure,
    this.errorMessage,
    required this.events,
    required this.elapsed,
    required this.log,
  });

  @override
  String toString() {
    final status = success ? 'SUCCESS' : 'FAILURE';
    final detail = detectedFailure?.toString() ?? errorMessage ?? '';
    return '[$status] ${elapsed.inMilliseconds}ms - $detail';
  }
}

// ─────────────────────────────────────────────────────────────
// IndependentParticipant
// ─────────────────────────────────────────────────────────────

/// A participant that runs independently in its own async context.
///
/// This simulates a real distributed system where each participant:
/// 1. Runs in its own process/isolate
/// 2. Updates heartbeats independently
/// 3. Monitors child participants through the ledger
/// 4. Can "crash" by stopping heartbeats and hanging forever
class IndependentParticipant {
  final String name;
  final int pid;
  final LocalLedger ledger;
  final AsyncSimulationPrinter printer;
  final int heartbeatIntervalMs;
  final int heartbeatTimeoutMs;

  Operation? _operation;
  Timer? _heartbeatTimer;
  bool _isCrashed = false;
  Completer<void>? _crashCompleter;

  /// Completer that signals when this participant detects a failure.
  final Completer<FailureDetection> _failureDetected =
      Completer<FailureDetection>();

  /// Stream of heartbeat results for monitoring.
  final _heartbeatController = StreamController<HeartbeatResult>.broadcast();
  Stream<HeartbeatResult> get heartbeatResults => _heartbeatController.stream;

  /// Future that completes when a failure is detected.
  Future<FailureDetection> get onFailureDetected => _failureDetected.future;

  IndependentParticipant({
    required this.name,
    required this.pid,
    required String basePath,
    required this.printer,
    this.heartbeatIntervalMs = 4500,
    this.heartbeatTimeoutMs = 10000,
    void Function(String)? onBackupCreated,
  }) : ledger = LocalLedger(
         basePath: basePath,
         participantId: name.toLowerCase(),
         participantPid: pid,
         callback: onBackupCreated != null
             ? LedgerCallback(onBackupCreated: onBackupCreated)
             : null,
       );

  bool get hasOperation => _operation != null;
  Operation get operation => _operation!;
  bool get isCrashed => _isCrashed;

  /// Start a new operation (initiator only).
  Future<Operation> startOperation({required int depth}) async {
    printer.log(depth: depth, participant: name, message: 'startOperation()');
    _operation = await ledger.createOperation();
    printer.log(
      depth: depth,
      participant: name,
      message: '  → operationId: "${_operation!.operationId}"',
    );
    // Set staleness threshold for crash detection
    _operation?.stalenessThresholdMs = heartbeatTimeoutMs;
    return _operation!;
  }

  /// Join an existing operation.
  Future<void> joinOperation({
    required String operationId,
    required int depth,
  }) async {
    printer.log(
      depth: depth,
      participant: name,
      message: 'joinOperation($operationId)',
    );
    _operation = await ledger.joinOperation(operationId: operationId);
    // Set staleness threshold for crash detection
    _operation?.stalenessThresholdMs = heartbeatTimeoutMs;
  }

  /// Dispose this participant's ledger.
  void dispose() {
    _heartbeatController.close();
    ledger.dispose();
  }

  /// Add a call frame for a call.
  Future<void> createCallFrame({
    required String callId,
    required int depth,
  }) async {
    printer.log(
      depth: depth,
      participant: name,
      message: 'createCallFrame($callId)',
    );
    await _operation?.createCallFrame(callId: callId);
  }

  /// Remove a call frame for a call.
  Future<void> deleteCallFrame({
    required String callId,
    required int depth,
  }) async {
    printer.log(
      depth: depth,
      participant: name,
      message: 'deleteCallFrame($callId)',
    );
    await _operation?.deleteCallFrame(callId: callId);
  }

  /// Complete the operation.
  Future<void> completeOperation({required int depth}) async {
    printer.log(
      depth: depth,
      participant: name,
      message: 'completeOperation()',
    );
    await _operation?.complete();
    _operation = null;
  }

  /// Start heartbeat with staleness detection.
  ///
  /// The heartbeat loop:
  /// 1. Updates this participant's timestamp in the ledger
  /// 2. Checks for abort flag
  /// 3. Checks for stale child heartbeats
  /// 4. Signals failure if detected
  void startHeartbeat({
    required int depth,
    required int expectedCallFrameCount,
  }) {
    printer.log(
      depth: depth,
      participant: name,
      message:
          'startHeartbeat(interval: ${heartbeatIntervalMs}ms, timeout: ${heartbeatTimeoutMs}ms)',
    );

    _heartbeatTimer = Timer.periodic(
      Duration(milliseconds: heartbeatIntervalMs),
      (_) => _performHeartbeat(depth, expectedCallFrameCount),
    );

    // Initial heartbeat immediately
    _performHeartbeat(depth, expectedCallFrameCount);
  }

  Future<void> _performHeartbeat(int depth, int expectedCallFrameCount) async {
    if (_isCrashed) return;
    if (_operation == null) return;

    try {
      final result = await operation.heartbeat();
      if (result == null) {
        _signalFailure(
          FailureDetection(
            type: DetectedFailureType.heartbeatError,
            participant: name,
            message: 'Ledger file not found',
          ),
        );
        return;
      }

      _heartbeatController.add(result);

      // Check for abort
      if (result.abortFlag) {
        printer.log(
          depth: depth,
          participant: name,
          message: '♥ DETECTED: Abort flag set!',
        );
        _signalFailure(
          FailureDetection(
            type: DetectedFailureType.abortRequested,
            participant: name,
            message: 'Abort flag set',
          ),
        );
        return;
      }

      // Check for stale heartbeat from OTHER participants (means a participant crashed)
      if (result.hasStaleChildren) {
        final staleList = result.staleParticipants.join(', ');
        final staleAges = result.staleParticipants
            .map((p) => '$p: ${result.participantHeartbeatAges[p]}ms')
            .join(', ');
        printer.log(
          depth: depth,
          participant: name,
          message:
              '♥ DETECTED: Stale participant(s): [$staleList] - crash detected! Ages: $staleAges',
        );
        _signalFailure(
          FailureDetection(
            type: DetectedFailureType.staleHeartbeat,
            participant: name,
            message: 'Stale participants: $staleList (ages: $staleAges)',
          ),
        );
        return;
      }

      // Check if expected children are still in the call frames
      if (result.callFrameCount < expectedCallFrameCount) {
        printer.log(
          depth: depth,
          participant: name,
          message:
              '♥ DETECTED: Child frame missing! Expected $expectedCallFrameCount, found ${result.callFrameCount}',
        );
        _signalFailure(
          FailureDetection(
            type: DetectedFailureType.childDisappeared,
            participant: name,
            message:
                'Expected call frame count $expectedCallFrameCount, found ${result.callFrameCount}',
          ),
        );
        return;
      }

      // Log successful heartbeat
      printer.log(
        depth: depth,
        participant: name,
        message:
            '♥ heartbeat OK (frames: ${result.callFrameCount}, age: ${result.heartbeatAgeMs}ms)',
      );
    } catch (e) {
      // Heartbeat failed (ledger file gone, etc.)
      _signalFailure(
        FailureDetection(
          type: DetectedFailureType.heartbeatError,
          participant: name,
          message: e.toString(),
        ),
      );
    }
  }

  void _signalFailure(FailureDetection failure) {
    if (!_failureDetected.isCompleted) {
      _failureDetected.complete(failure);
    }
  }

  /// Stop heartbeat.
  void stopHeartbeat({required int depth}) {
    printer.log(depth: depth, participant: name, message: 'stopHeartbeat()');
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Simulate a crash: stop heartbeat and hang indefinitely.
  ///
  /// This is the key difference from the old simulation:
  /// - The participant stops updating heartbeats
  /// - Returns a Future that never completes (simulating hung process)
  /// - Other participants will detect this via stale heartbeats
  ///
  /// Note: This future only completes when forceStop() is called for test cleanup.
  Future<void> crash({required int depth}) async {
    printer.log(
      depth: depth,
      participant: name,
      message: '💥 CRASH (stopping heartbeat, hanging indefinitely...)',
    );
    _isCrashed = true;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    // Wait forever until forceStop() is called for cleanup
    _crashCompleter = Completer<void>();
    await _crashCompleter!.future;
    // After forceStop() completes the completer, we just return silently
  }

  /// Cleanup after detecting a failure.
  Future<void> cleanupOnFailure({required int depth}) async {
    printer.log(
      depth: depth,
      participant: name,
      message: 'cleanup on failure detection',
    );
    stopHeartbeat(depth: depth);
    // Additional cleanup would go here (temp resources, etc.)
  }

  /// Force stop this participant (for test cleanup).
  void forceStop() {
    _isCrashed = true;
    _heartbeatTimer?.cancel();
    _crashCompleter?.complete();
    if (!_heartbeatController.isClosed) {
      _heartbeatController.close();
    }
  }
}

// ─────────────────────────────────────────────────────────────
// ConcurrentScenarioRunner
// ─────────────────────────────────────────────────────────────

/// Runs scenarios with truly concurrent participants.
///
/// Each participant runs in its own async context, updating heartbeats
/// independently. Crash detection happens through heartbeat monitoring,
/// not through flags checked in a main loop.
class ConcurrentScenarioRunner {
  final String ledgerPath;
  final void Function(String)? onLog;

  late AsyncSimulationPrinter _printer;
  final Map<String, IndependentParticipant> _participants = {};

  /// Current operation ID (set by initiator).
  String? _currentOperationId;

  ConcurrentScenarioRunner({required this.ledgerPath, this.onLog});

  /// Initialize participants for a scenario.
  void _initialize({
    required int heartbeatIntervalMs,
    required int heartbeatTimeoutMs,
  }) {
    _printer = AsyncSimulationPrinter(onLog: onLog);

    _participants.clear();
    _currentOperationId = null;

    void Function(String) onBackupCreatedFor(String participantName) {
      return (path) {
        final relativePath = path.replaceFirst('$ledgerPath/', '');
        _printer.log(
          depth: 0,
          participant: participantName,
          message: 'backup → $relativePath',
        );
      };
    }

    _participants['CLI'] = IndependentParticipant(
      name: 'CLI',
      pid: 1001,
      basePath: ledgerPath,
      printer: _printer,
      heartbeatIntervalMs: heartbeatIntervalMs,
      heartbeatTimeoutMs: heartbeatTimeoutMs,
      onBackupCreated: onBackupCreatedFor('CLI'),
    );

    _participants['Bridge'] = IndependentParticipant(
      name: 'Bridge',
      pid: 2001,
      basePath: ledgerPath,
      printer: _printer,
      heartbeatIntervalMs: heartbeatIntervalMs,
      heartbeatTimeoutMs: heartbeatTimeoutMs,
      onBackupCreated: onBackupCreatedFor('Bridge'),
    );

    _participants['VSCode'] = IndependentParticipant(
      name: 'VSCode',
      pid: 3001,
      basePath: ledgerPath,
      printer: _printer,
      heartbeatIntervalMs: heartbeatIntervalMs,
      heartbeatTimeoutMs: heartbeatTimeoutMs,
      onBackupCreated: onBackupCreatedFor('VSCode'),
    );
  }

  /// Dispose all participant ledgers.
  void dispose() {
    for (final participant in _participants.values) {
      participant.dispose();
    }
  }

  /// Run a crash detection test.
  ///
  /// This demonstrates actual async failure detection:
  /// 1. CLI starts operation, starts heartbeat
  /// 2. Bridge joins, starts heartbeat
  /// 3. Bridge crashes (stops heartbeat, hangs)
  /// 4. CLI's heartbeat detects stale heartbeat
  /// 5. CLI performs cleanup
  Future<ConcurrentScenarioResult> runCrashDetectionScenario({
    required String crashingParticipant,
    required int crashAfterMs,
    int heartbeatIntervalMs = 1000,
    int heartbeatTimeoutMs = 3000,
    int maxWaitMs = 15000,
  }) async {
    _initialize(
      heartbeatIntervalMs: heartbeatIntervalMs,
      heartbeatTimeoutMs: heartbeatTimeoutMs,
    );

    final stopwatch = Stopwatch()..start();
    final events = <ScenarioEvent>[];

    try {
      _printer.printHeader('Crash Detection Scenario');
      _printer.log(
        depth: 0,
        participant: 'Runner',
        message: 'Crash target: $crashingParticipant after ${crashAfterMs}ms',
      );
      _printer.log(
        depth: 0,
        participant: 'Runner',
        message:
            'Heartbeat interval: ${heartbeatIntervalMs}ms, timeout: ${heartbeatTimeoutMs}ms',
      );

      final cli = _participants['CLI']!;
      final bridge = _participants['Bridge']!;

      // Phase 1: CLI starts operation
      events.add(
        ScenarioEvent(stopwatch.elapsedMilliseconds, 'CLI starts operation'),
      );
      final operation = await cli.startOperation(depth: 1);
      _currentOperationId = operation.operationId;
      await cli.createCallFrame(callId: 'cli-main', depth: 1);
      cli.startHeartbeat(depth: 1, expectedCallFrameCount: 1);

      // Small delay before bridge joins
      await Future.delayed(Duration(milliseconds: heartbeatIntervalMs ~/ 2));

      // Phase 2: Bridge joins
      events.add(
        ScenarioEvent(stopwatch.elapsedMilliseconds, 'Bridge joins operation'),
      );
      await bridge.joinOperation(operationId: _currentOperationId!, depth: 2);
      await bridge.createCallFrame(callId: 'bridge-process', depth: 2);
      bridge.startHeartbeat(depth: 2, expectedCallFrameCount: 2);

      // Now CLI should monitor for 2 call frames
      cli.stopHeartbeat(depth: 1);
      cli.startHeartbeat(depth: 1, expectedCallFrameCount: 2);

      // Schedule crash
      final crashParticipant = _participants[crashingParticipant]!;
      Timer(Duration(milliseconds: crashAfterMs), () {
        events.add(
          ScenarioEvent(
            stopwatch.elapsedMilliseconds,
            '$crashingParticipant crashes',
          ),
        );
        // Fire and forget - crash() never returns
        crashParticipant.crash(depth: crashingParticipant == 'CLI' ? 1 : 2);
      });

      // Wait for failure detection from non-crashed participants
      final detectionTimeout = Duration(milliseconds: maxWaitMs);
      final detectors = _participants.values
          .where((p) => p.name != crashingParticipant)
          .map((p) => p.onFailureDetected)
          .toList();

      _printer.log(
        depth: 0,
        participant: 'Runner',
        message: 'Waiting for failure detection (timeout: ${maxWaitMs}ms)...',
      );

      try {
        final detection = await Future.any(detectors).timeout(detectionTimeout);
        events.add(
          ScenarioEvent(
            stopwatch.elapsedMilliseconds,
            '${detection.participant} detected: ${detection.type}',
          ),
        );

        _printer.printPhase('Failure Detected!');
        _printer.log(
          depth: 0,
          participant: detection.participant,
          message: 'Detected ${detection.type}: ${detection.message}',
        );

        // Cleanup
        for (final p in _participants.values) {
          if (!p.isCrashed && p.hasOperation) {
            await p.cleanupOnFailure(depth: p.name == 'CLI' ? 1 : 2);
          }
        }

        stopwatch.stop();
        return ConcurrentScenarioResult(
          success: true,
          detectedFailure: detection,
          events: events,
          elapsed: stopwatch.elapsed,
          log: _printer.output,
        );
      } on TimeoutException {
        events.add(
          ScenarioEvent(
            stopwatch.elapsedMilliseconds,
            'TIMEOUT: No failure detected',
          ),
        );
        stopwatch.stop();
        return ConcurrentScenarioResult(
          success: false,
          errorMessage: 'Timeout: No failure detected within ${maxWaitMs}ms',
          events: events,
          elapsed: stopwatch.elapsed,
          log: _printer.output,
        );
      }
    } finally {
      // Force cleanup all participants
      for (final p in _participants.values) {
        p.forceStop();
      }
      dispose();
    }
  }

  /// Run a simple happy path to verify normal operation works.
  Future<ConcurrentScenarioResult> runHappyPath({
    int processingMs = 2000,
    int heartbeatIntervalMs = 500,
    int heartbeatTimeoutMs = 2000,
  }) async {
    _initialize(
      heartbeatIntervalMs: heartbeatIntervalMs,
      heartbeatTimeoutMs: heartbeatTimeoutMs,
    );

    final stopwatch = Stopwatch()..start();
    final events = <ScenarioEvent>[];

    try {
      _printer.printHeader('Happy Path Scenario (Concurrent)');

      final cli = _participants['CLI']!;
      final bridge = _participants['Bridge']!;

      // CLI starts
      events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'CLI starts'));
      final operation = await cli.startOperation(depth: 1);
      _currentOperationId = operation.operationId;
      await cli.createCallFrame(callId: 'cli-main', depth: 1);
      cli.startHeartbeat(depth: 1, expectedCallFrameCount: 1);

      await Future.delayed(Duration(milliseconds: heartbeatIntervalMs));

      // Bridge joins
      events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'Bridge joins'));
      await bridge.joinOperation(operationId: _currentOperationId!, depth: 2);
      await bridge.createCallFrame(callId: 'bridge-process', depth: 2);
      bridge.startHeartbeat(depth: 2, expectedCallFrameCount: 2);

      // Simulate work
      await Future.delayed(Duration(milliseconds: processingMs));

      // Bridge completes
      events.add(
        ScenarioEvent(stopwatch.elapsedMilliseconds, 'Bridge completes'),
      );
      bridge.stopHeartbeat(depth: 2);
      await bridge.deleteCallFrame(callId: 'bridge-process', depth: 2);

      // CLI completes
      events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'CLI completes'));
      cli.stopHeartbeat(depth: 1);
      await cli.deleteCallFrame(callId: 'cli-main', depth: 1);
      await cli.completeOperation(depth: 1);

      stopwatch.stop();
      return ConcurrentScenarioResult(
        success: true,
        events: events,
        elapsed: stopwatch.elapsed,
        log: _printer.output,
      );
    } finally {
      for (final p in _participants.values) {
        p.forceStop();
      }
      dispose();
    }
  }

  /// Run a user abort scenario.
  ///
  /// Demonstrates abort flag propagation:
  /// 1. CLI starts operation, Bridge joins
  /// 2. User triggers abort (sets abort flag in ledger)
  /// 3. Participants detect abort via heartbeat
  /// 4. All participants clean up
  Future<ConcurrentScenarioResult> runAbortScenario({
    required int abortAfterMs,
    int heartbeatIntervalMs = 500,
    int heartbeatTimeoutMs = 2000,
    int maxWaitMs = 10000,
  }) async {
    _initialize(
      heartbeatIntervalMs: heartbeatIntervalMs,
      heartbeatTimeoutMs: heartbeatTimeoutMs,
    );

    final stopwatch = Stopwatch()..start();
    final events = <ScenarioEvent>[];

    try {
      _printer.printHeader('User Abort Scenario');
      _printer.log(
        depth: 0,
        participant: 'Runner',
        message: 'Abort after ${abortAfterMs}ms',
      );

      final cli = _participants['CLI']!;
      final bridge = _participants['Bridge']!;

      // Phase 1: CLI starts operation
      events.add(
        ScenarioEvent(stopwatch.elapsedMilliseconds, 'CLI starts operation'),
      );
      final operation = await cli.startOperation(depth: 1);
      _currentOperationId = operation.operationId;
      await cli.createCallFrame(callId: 'cli-main', depth: 1);
      cli.startHeartbeat(depth: 1, expectedCallFrameCount: 1);

      await Future.delayed(Duration(milliseconds: heartbeatIntervalMs ~/ 2));

      // Phase 2: Bridge joins
      events.add(
        ScenarioEvent(stopwatch.elapsedMilliseconds, 'Bridge joins operation'),
      );
      await bridge.joinOperation(operationId: _currentOperationId!, depth: 2);
      await bridge.createCallFrame(callId: 'bridge-process', depth: 2);
      bridge.startHeartbeat(depth: 2, expectedCallFrameCount: 2);

      // Schedule abort (like user pressing Ctrl+C)
      Timer(Duration(milliseconds: abortAfterMs), () async {
        events.add(
          ScenarioEvent(stopwatch.elapsedMilliseconds, 'USER ABORT (Ctrl+C)'),
        );
        _printer.logEvent(message: 'USER ABORT (Ctrl+C)');
        // Set abort flag in ledger
        await cli.operation.setAbortFlag(true);
      });

      // Wait for failure detection
      final detectionTimeout = Duration(milliseconds: maxWaitMs);
      final detectors = _participants.values
          .map((p) => p.onFailureDetected)
          .toList();

      _printer.log(
        depth: 0,
        participant: 'Runner',
        message: 'Waiting for abort detection...',
      );

      try {
        final detection = await Future.any(detectors).timeout(detectionTimeout);
        events.add(
          ScenarioEvent(
            stopwatch.elapsedMilliseconds,
            '${detection.participant} detected: ${detection.type}',
          ),
        );

        _printer.printPhase('Abort Detected!');
        _printer.log(
          depth: 0,
          participant: detection.participant,
          message: 'Detected ${detection.type}: ${detection.message}',
        );

        // Cleanup
        for (final p in _participants.values) {
          if (p.hasOperation) {
            await p.cleanupOnFailure(depth: p.name == 'CLI' ? 1 : 2);
          }
        }

        stopwatch.stop();
        return ConcurrentScenarioResult(
          success: true,
          detectedFailure: detection,
          events: events,
          elapsed: stopwatch.elapsed,
          log: _printer.output,
        );
      } on TimeoutException {
        events.add(
          ScenarioEvent(
            stopwatch.elapsedMilliseconds,
            'TIMEOUT: No abort detected',
          ),
        );
        stopwatch.stop();
        return ConcurrentScenarioResult(
          success: false,
          errorMessage: 'Timeout: No abort detected within ${maxWaitMs}ms',
          events: events,
          elapsed: stopwatch.elapsed,
          log: _printer.output,
        );
      }
    } finally {
      for (final p in _participants.values) {
        p.forceStop();
      }
      dispose();
    }
  }
}
