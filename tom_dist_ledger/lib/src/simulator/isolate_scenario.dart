/// Isolate-based Scenario Runner
///
/// Provides true parallel execution by running each participant in a separate
/// Dart Isolate. This more accurately simulates real-world distributed systems
/// where CLI, Bridge, and VS Code are separate processes.
///
/// Key differences from [ConcurrentScenarioRunner]:
/// - Each participant runs in its own [Isolate] with true parallelism
/// - Communication happens via [SendPort]/[ReceivePort]
/// - Ledger files are the shared state (file system)
/// - Crashes and hangs are real (isolate stops responding)
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import '../ledger_api/ledger_api.dart';
import '../local_ledger/file_ledger.dart' show HeartbeatResult;
import 'concurrent_scenario.dart';

// ─────────────────────────────────────────────────────────────
// Message Protocol
// ─────────────────────────────────────────────────────────────

/// Commands sent from main isolate to participant isolates.
enum ParticipantCommand {
  /// Start a new operation (initiator only).
  startOperation,

  /// Join an existing operation.
  joinOperation,

  /// Push a stack frame.
  pushStackFrame,

  /// Pop a stack frame.
  popStackFrame,

  /// Start heartbeat monitoring.
  startHeartbeat,

  /// Stop heartbeat monitoring.
  stopHeartbeat,

  /// Complete the operation.
  completeOperation,

  /// Simulate a crash (stop heartbeat, hang forever).
  crash,

  /// Clean shutdown.
  shutdown,

  /// Set abort flag in ledger.
  setAbortFlag,
}

/// A message sent to a participant isolate.
class ParticipantMessage {
  final ParticipantCommand command;
  final Map<String, dynamic> params;

  ParticipantMessage(this.command, [this.params = const {}]);
}

/// Response types from participant isolates.
enum ParticipantResponseType {
  /// Command completed successfully.
  success,

  /// Command failed with error.
  error,

  /// Operation started, includes operationId.
  operationStarted,

  /// Heartbeat performed, includes result.
  heartbeat,

  /// Failure detected through heartbeat.
  failureDetected,

  /// Log message for display.
  log,
}

/// A response from a participant isolate.
class ParticipantResponse {
  final ParticipantResponseType type;
  final String? message;
  final Map<String, dynamic>? data;

  ParticipantResponse(this.type, {this.message, this.data});
}

// ─────────────────────────────────────────────────────────────
// Isolate Entry Point
// ─────────────────────────────────────────────────────────────

/// Configuration passed to participant isolate on spawn.
class IsolateParticipantConfig {
  final String name;
  final int pid;
  final String basePath;
  final int heartbeatIntervalMs;
  final int heartbeatTimeoutMs;
  final SendPort sendPort;

  IsolateParticipantConfig({
    required this.name,
    required this.pid,
    required this.basePath,
    required this.heartbeatIntervalMs,
    required this.heartbeatTimeoutMs,
    required this.sendPort,
  });
}

/// Entry point for participant isolate.
///
/// This function runs in a separate isolate and manages a single participant.
Future<void> _participantIsolateEntry(IsolateParticipantConfig config) async {
  final receivePort = ReceivePort();
  config.sendPort.send(receivePort.sendPort);

  final runner = _IsolateParticipantRunner(config);
  await runner.run(receivePort);
}

/// Internal runner that executes in the participant isolate.
class _IsolateParticipantRunner {
  final IsolateParticipantConfig config;
  late final Ledger _ledger;
  Operation? _operation;
  Timer? _heartbeatTimer;
  bool _isCrashed = false;
  int _expectedStackDepth = 1;

  _IsolateParticipantRunner(this.config);

  void _log(String message) {
    config.sendPort.send(ParticipantResponse(
      ParticipantResponseType.log,
      message: '[${config.name}] $message',
    ));
  }

  void _sendResponse(ParticipantResponseType type,
      {String? message, Map<String, dynamic>? data}) {
    config.sendPort.send(ParticipantResponse(type, message: message, data: data));
  }

  Future<void> run(ReceivePort receivePort) async {
    _ledger = Ledger(
      basePath: config.basePath,
      participantId: config.name.toLowerCase(),
      participantPid: config.pid,
      onBackupCreated: (path) {
        final relativePath = path.replaceFirst('${config.basePath}/', '');
        _log('backup → $relativePath');
      },
    );

    await for (final message in receivePort) {
      if (message is! ParticipantMessage) continue;

      try {
        await _handleCommand(message);
      } catch (e, st) {
        _sendResponse(
          ParticipantResponseType.error,
          message: 'Error handling ${message.command}: $e\n$st',
        );
      }
    }
  }

  Future<void> _handleCommand(ParticipantMessage message) async {
    switch (message.command) {
      case ParticipantCommand.startOperation:
        _log('startOperation()');
        _operation = await _ledger.createOperation(
          description: message.params['description'] as String?,
        );
        _operation?.stalenessThresholdMs = config.heartbeatTimeoutMs;
        _log('  → operationId: "${_operation!.operationId}"');
        _sendResponse(
          ParticipantResponseType.operationStarted,
          data: {'operationId': _operation!.operationId},
        );

      case ParticipantCommand.joinOperation:
        final operationId = message.params['operationId'] as String;
        _log('joinOperation($operationId)');
        _operation = await _ledger.joinOperation(operationId: operationId);
        _operation?.stalenessThresholdMs = config.heartbeatTimeoutMs;
        _sendResponse(ParticipantResponseType.success);

      case ParticipantCommand.pushStackFrame:
        final callId = message.params['callId'] as String;
        _log('pushStackFrame($callId)');
        await _operation?.pushStackFrame(callId: callId);
        _sendResponse(ParticipantResponseType.success);

      case ParticipantCommand.popStackFrame:
        final callId = message.params['callId'] as String;
        _log('popStackFrame($callId)');
        await _operation?.popStackFrame(callId: callId);
        _sendResponse(ParticipantResponseType.success);

      case ParticipantCommand.startHeartbeat:
        _expectedStackDepth = message.params['expectedStackDepth'] as int? ?? 1;
        _log('startHeartbeat(interval: ${config.heartbeatIntervalMs}ms, timeout: ${config.heartbeatTimeoutMs}ms)');
        _startHeartbeat();
        _sendResponse(ParticipantResponseType.success);

      case ParticipantCommand.stopHeartbeat:
        _log('stopHeartbeat()');
        _stopHeartbeat();
        _sendResponse(ParticipantResponseType.success);

      case ParticipantCommand.completeOperation:
        _log('completeOperation()');
        await _operation?.complete();
        _sendResponse(ParticipantResponseType.success);

      case ParticipantCommand.crash:
        _log('💥 CRASH (stopping heartbeat, hanging indefinitely...)');
        _isCrashed = true;
        _stopHeartbeat();
        // Don't send response - we're simulating a crash
        // The isolate stays alive but stops responding
        await Completer<void>().future; // Hang forever

      case ParticipantCommand.shutdown:
        _log('shutdown()');
        _stopHeartbeat();
        _ledger.dispose();
        _sendResponse(ParticipantResponseType.success);
        // Exit the isolate
        Isolate.exit();

      case ParticipantCommand.setAbortFlag:
        final value = message.params['value'] as bool? ?? true;
        _log('setAbortFlag($value)');
        await _operation?.setAbortFlag(value);
        _sendResponse(ParticipantResponseType.success);
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(milliseconds: config.heartbeatIntervalMs),
      (_) => _performHeartbeat(),
    );
    // Initial heartbeat immediately
    _performHeartbeat();
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  final _random = Random();

  /// Get the operation file path.
  String? get _operationFilePath {
    if (_operation == null) return null;
    return '${config.basePath}/${_operation!.operationId}.operation.json';
  }

  Future<void> _performHeartbeat() async {
    if (_isCrashed || _operation == null) return;

    try {
      // Retry loop for lock contention
      HeartbeatResult? maybeResult;
      while (maybeResult == null) {
        if (_isCrashed || _operation == null) return;
        
        maybeResult = await _operation!.heartbeat();
        if (maybeResult == null) {
          // Check if file still exists - if not, operation is gone
          final filePath = _operationFilePath;
          if (filePath != null && !File(filePath).existsSync()) {
            // File is gone - stop heartbeat and notify
            _log('♥ DETECTED: Operation file gone!');
            _stopHeartbeat();
            _sendResponse(
              ParticipantResponseType.failureDetected,
              data: {
                'type': DetectedFailureType.heartbeatError.name,
                'participant': config.name,
                'message': 'Operation file no longer exists',
              },
            );
            return;
          }
          // Lock contention - wait 50ms +/- 10ms jitter and retry
          final jitterMs = 50 + _random.nextInt(21) - 10; // 40-60ms
          await Future.delayed(Duration(milliseconds: jitterMs));
        }
      }
      final result = maybeResult; // Now non-null

      // Send heartbeat result
      _sendResponse(
        ParticipantResponseType.heartbeat,
        data: {
          'stackDepth': result.stackDepth,
          'heartbeatAgeMs': result.heartbeatAgeMs,
          'abortFlag': result.abortFlag,
          'hasStaleChildren': result.hasStaleChildren,
          'staleParticipants': result.staleParticipants,
        },
      );

      // Check for abort
      if (result.abortFlag) {
        _log('♥ DETECTED: Abort flag set!');
        _sendResponse(
          ParticipantResponseType.failureDetected,
          data: {
            'type': DetectedFailureType.abortRequested.name,
            'participant': config.name,
            'message': 'Abort flag set',
          },
        );
        return;
      }

      // Check for stale heartbeats
      if (result.hasStaleChildren) {
        final staleList = result.staleParticipants.join(', ');
        final staleAges = result.staleParticipants
            .map((p) => '$p: ${result.participantHeartbeatAges[p]}ms')
            .join(', ');
        _log('♥ DETECTED: Stale participant(s): [$staleList] - crash detected! Ages: $staleAges');
        _sendResponse(
          ParticipantResponseType.failureDetected,
          data: {
            'type': DetectedFailureType.staleHeartbeat.name,
            'participant': config.name,
            'message': 'Stale participants: $staleList (ages: $staleAges)',
          },
        );
        return;
      }

      // Check if expected children are still in the stack
      if (result.stackDepth < _expectedStackDepth) {
        _log('♥ DETECTED: Child disappeared from stack! Expected $_expectedStackDepth, found ${result.stackDepth}');
        _sendResponse(
          ParticipantResponseType.failureDetected,
          data: {
            'type': DetectedFailureType.childDisappeared.name,
            'participant': config.name,
            'message': 'Expected stack depth $_expectedStackDepth, found ${result.stackDepth}',
          },
        );
        return;
      }

      // Success
      _log('♥ heartbeat OK (stack: ${result.stackDepth}, age: ${result.heartbeatAgeMs}ms)');
    } catch (e) {
      _sendResponse(
        ParticipantResponseType.failureDetected,
        data: {
          'type': DetectedFailureType.heartbeatError.name,
          'participant': config.name,
          'message': e.toString(),
        },
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────
// IsolateParticipantHandle
// ─────────────────────────────────────────────────────────────

/// Handle to control a participant running in a separate isolate.
class IsolateParticipantHandle {
  final String name;
  final Isolate isolate;
  final SendPort sendPort;
  final Stream<ParticipantResponse> responses;
  final StreamController<ParticipantResponse> _responseController;
  final void Function(String)? _onLog;

  String? _currentOperationId;
  String? get currentOperationId => _currentOperationId;

  bool _isCrashed = false;
  bool get isCrashed => _isCrashed;

  final Completer<FailureDetection> _failureDetected = Completer<FailureDetection>();
  Future<FailureDetection> get onFailureDetected => _failureDetected.future;

  IsolateParticipantHandle._({
    required this.name,
    required this.isolate,
    required this.sendPort,
    required StreamController<ParticipantResponse> responseController,
    void Function(String)? onLog,
  })  : _responseController = responseController,
        _onLog = onLog,
        responses = responseController.stream.asBroadcastStream();

  /// Spawn a new participant in a separate isolate.
  static Future<IsolateParticipantHandle> spawn({
    required String name,
    required int pid,
    required String basePath,
    required int heartbeatIntervalMs,
    required int heartbeatTimeoutMs,
    void Function(String)? onLog,
  }) async {
    final receivePort = ReceivePort();
    final responseController = StreamController<ParticipantResponse>.broadcast();

    final config = IsolateParticipantConfig(
      name: name,
      pid: pid,
      basePath: basePath,
      heartbeatIntervalMs: heartbeatIntervalMs,
      heartbeatTimeoutMs: heartbeatTimeoutMs,
      sendPort: receivePort.sendPort,
    );

    final isolate = await Isolate.spawn(
      _participantIsolateEntry,
      config,
      debugName: 'Participant-$name',
    );

    // Convert to broadcast stream so we can get first item and continue listening
    final broadcastStream = receivePort.asBroadcastStream();

    // First message is the isolate's send port
    final isolateSendPort = await broadcastStream.first as SendPort;

    // Listen for responses from the isolate
    broadcastStream.listen((message) {
      if (responseController.isClosed) return;
      if (message is ParticipantResponse) {
        if (message.type == ParticipantResponseType.log && onLog != null) {
          onLog(message.message ?? '');
        }
        responseController.add(message);
      }
    });

    final handle = IsolateParticipantHandle._(
      name: name,
      isolate: isolate,
      sendPort: isolateSendPort,
      responseController: responseController,
      onLog: onLog,
    );

    // Listen for failure detections
    responseController.stream.listen((response) {
      if (response.type == ParticipantResponseType.failureDetected &&
          !handle._failureDetected.isCompleted) {
        final data = response.data!;
        handle._failureDetected.complete(FailureDetection(
          type: DetectedFailureType.values.byName(data['type'] as String),
          participant: data['participant'] as String,
          message: data['message'] as String,
        ));
      }
    });

    return handle;
  }

  void _send(ParticipantCommand command, [Map<String, dynamic> params = const {}]) {
    if (_isCrashed) return;
    sendPort.send(ParticipantMessage(command, params));
  }

  /// Wait for a response of the given type.
  Future<ParticipantResponse> _waitFor(ParticipantResponseType type,
      {Duration timeout = const Duration(seconds: 10)}) {
    return responses
        .where((r) => r.type == type || r.type == ParticipantResponseType.error)
        .first
        .timeout(timeout);
  }

  /// Start a new operation.
  Future<String> startOperation({String? description}) async {
    _send(ParticipantCommand.startOperation, {'description': description});
    final response = await _waitFor(ParticipantResponseType.operationStarted);
    _currentOperationId = response.data!['operationId'] as String;
    return _currentOperationId!;
  }

  /// Join an existing operation.
  Future<void> joinOperation(String operationId) async {
    _currentOperationId = operationId;
    _send(ParticipantCommand.joinOperation, {'operationId': operationId});
    await _waitFor(ParticipantResponseType.success);
  }

  /// Push a stack frame.
  Future<void> pushStackFrame(String callId) async {
    _send(ParticipantCommand.pushStackFrame, {'callId': callId});
    await _waitFor(ParticipantResponseType.success);
  }

  /// Pop a stack frame.
  Future<void> popStackFrame(String callId) async {
    _send(ParticipantCommand.popStackFrame, {'callId': callId});
    await _waitFor(ParticipantResponseType.success);
  }

  /// Start heartbeat monitoring.
  void startHeartbeat({int expectedStackDepth = 1}) {
    _send(ParticipantCommand.startHeartbeat, {'expectedStackDepth': expectedStackDepth});
  }

  /// Stop heartbeat monitoring.
  void stopHeartbeat() {
    _send(ParticipantCommand.stopHeartbeat);
  }

  /// Complete the operation.
  Future<void> completeOperation() async {
    _send(ParticipantCommand.completeOperation);
    await _waitFor(ParticipantResponseType.success);
  }

  /// Set abort flag in ledger.
  Future<void> setAbortFlag(bool value) async {
    _send(ParticipantCommand.setAbortFlag, {'value': value});
    await _waitFor(ParticipantResponseType.success);
  }

  /// Simulate a crash - kill the isolate immediately without warning.
  /// 
  /// This is realistic: the process dies suddenly with no cleanup or message.
  /// Other participants detect this through stale heartbeats.
  void crash() {
    _onLog?.call('[$name] 💥 CRASH');
    _isCrashed = true;
    // Kill immediately - no message, no warning, just silence
    isolate.kill(priority: Isolate.immediate);
  }

  /// Shutdown the participant gracefully.
  Future<void> shutdown() async {
    if (_isCrashed) {
      isolate.kill(priority: Isolate.immediate);
      return;
    }
    _send(ParticipantCommand.shutdown);
    // Give it a moment then kill
    await Future.delayed(const Duration(milliseconds: 100));
    isolate.kill(priority: Isolate.immediate);
  }

  /// Force kill the isolate.
  void forceKill() {
    _isCrashed = true;
    isolate.kill(priority: Isolate.immediate);
    _responseController.close();
  }
}

// ─────────────────────────────────────────────────────────────
// IsolateScenarioRunner
// ─────────────────────────────────────────────────────────────

/// Runs scenarios with true parallel execution using Dart Isolates.
///
/// Each participant runs in its own isolate, providing real parallelism.
/// This is the closest simulation to actual multi-process distributed
/// systems like CLI + Bridge + VS Code.
class IsolateScenarioRunner {
  final String ledgerPath;
  final void Function(String)? onLog;

  final List<String> _logOutput = [];
  final Map<String, IsolateParticipantHandle> _participants = {};

  IsolateScenarioRunner({
    required this.ledgerPath,
    this.onLog,
  });

  void _log(String message) {
    _logOutput.add(message);
    onLog?.call(message);
  }

  /// Initialize participants as separate isolates.
  Future<void> _initialize({
    required int heartbeatIntervalMs,
    required int heartbeatTimeoutMs,
  }) async {
    _participants.clear();
    _logOutput.clear();

    // Spawn each participant in its own isolate
    _participants['CLI'] = await IsolateParticipantHandle.spawn(
      name: 'CLI',
      pid: 1001,
      basePath: ledgerPath,
      heartbeatIntervalMs: heartbeatIntervalMs,
      heartbeatTimeoutMs: heartbeatTimeoutMs,
      onLog: _log,
    );

    _participants['Bridge'] = await IsolateParticipantHandle.spawn(
      name: 'Bridge',
      pid: 2001,
      basePath: ledgerPath,
      heartbeatIntervalMs: heartbeatIntervalMs,
      heartbeatTimeoutMs: heartbeatTimeoutMs,
      onLog: _log,
    );

    _participants['VSCode'] = await IsolateParticipantHandle.spawn(
      name: 'VSCode',
      pid: 3001,
      basePath: ledgerPath,
      heartbeatIntervalMs: heartbeatIntervalMs,
      heartbeatTimeoutMs: heartbeatTimeoutMs,
      onLog: _log,
    );
  }

  /// Cleanup all isolates.
  Future<void> _cleanup() async {
    for (final p in _participants.values) {
      p.forceKill();
    }
    _participants.clear();
  }

  /// Run a crash detection test with true parallel execution.
  Future<ConcurrentScenarioResult> runCrashDetectionScenario({
    required String crashingParticipant,
    required int crashAfterMs,
    int heartbeatIntervalMs = 1000,
    int heartbeatTimeoutMs = 3000,
    int maxWaitMs = 15000,
  }) async {
    await _initialize(
      heartbeatIntervalMs: heartbeatIntervalMs,
      heartbeatTimeoutMs: heartbeatTimeoutMs,
    );

    final stopwatch = Stopwatch()..start();
    final events = <ScenarioEvent>[];

    try {
      _log('════════════════════════════════════════════════════════════════════');
      _log('Crash Detection Scenario (Isolate-based)');
      _log('════════════════════════════════════════════════════════════════════');
      _log('Crash target: $crashingParticipant after ${crashAfterMs}ms');
      _log('Heartbeat interval: ${heartbeatIntervalMs}ms, timeout: ${heartbeatTimeoutMs}ms');
      _log('');

      final cli = _participants['CLI']!;
      final bridge = _participants['Bridge']!;

      // Phase 1: CLI starts operation
      events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'CLI starts operation'));
      final operationId = await cli.startOperation();
      await cli.pushStackFrame('cli-main');
      cli.startHeartbeat(expectedStackDepth: 1);

      // Small delay before bridge joins
      await Future.delayed(Duration(milliseconds: heartbeatIntervalMs ~/ 2));

      // Phase 2: Bridge joins
      events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'Bridge joins operation'));
      await bridge.joinOperation(operationId);
      await bridge.pushStackFrame('bridge-process');
      bridge.startHeartbeat(expectedStackDepth: 2);

      // Update CLI's expected stack depth
      cli.stopHeartbeat();
      cli.startHeartbeat(expectedStackDepth: 2);

      // Schedule crash
      final crashParticipant = _participants[crashingParticipant]!;
      Timer(Duration(milliseconds: crashAfterMs), () {
        events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, '$crashingParticipant crashes'));
        crashParticipant.crash();
      });

      // Wait for failure detection
      _log('Waiting for failure detection (timeout: ${maxWaitMs}ms)...');
      final detectors = _participants.values
          .where((p) => p.name != crashingParticipant)
          .map((p) => p.onFailureDetected)
          .toList();

      try {
        final detection = await Future.any(detectors)
            .timeout(Duration(milliseconds: maxWaitMs));

        events.add(ScenarioEvent(
          stopwatch.elapsedMilliseconds,
          '${detection.participant} detected: ${detection.type}',
        ));

        _log('');
        _log('────────────────────────────────────────');
        _log('Failure Detected!');
        _log('────────────────────────────────────────');
        _log('${detection.participant} detected ${detection.type}: ${detection.message}');

        // Cleanup non-crashed participants
        for (final p in _participants.values) {
          if (!p.isCrashed) {
            p.stopHeartbeat();
          }
        }

        stopwatch.stop();
        return ConcurrentScenarioResult(
          success: true,
          detectedFailure: detection,
          events: events,
          elapsed: stopwatch.elapsed,
          log: List.from(_logOutput),
        );
      } on TimeoutException {
        events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'TIMEOUT: No failure detected'));
        stopwatch.stop();
        return ConcurrentScenarioResult(
          success: false,
          errorMessage: 'Timeout: No failure detected within ${maxWaitMs}ms',
          events: events,
          elapsed: stopwatch.elapsed,
          log: List.from(_logOutput),
        );
      }
    } finally {
      await _cleanup();
    }
  }

  /// Run a happy path scenario with true parallel execution.
  Future<ConcurrentScenarioResult> runHappyPath({
    int processingMs = 500,
    int heartbeatIntervalMs = 100,
    int heartbeatTimeoutMs = 2000,
  }) async {
    await _initialize(
      heartbeatIntervalMs: heartbeatIntervalMs,
      heartbeatTimeoutMs: heartbeatTimeoutMs,
    );

    final stopwatch = Stopwatch()..start();
    final events = <ScenarioEvent>[];

    try {
      _log('════════════════════════════════════════════════════════════════════');
      _log('Happy Path Scenario (Isolate-based)');
      _log('════════════════════════════════════════════════════════════════════');
      _log('');

      final cli = _participants['CLI']!;
      final bridge = _participants['Bridge']!;

      // CLI starts
      events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'CLI starts'));
      final operationId = await cli.startOperation();
      await cli.pushStackFrame('cli-main');
      cli.startHeartbeat(expectedStackDepth: 1);

      await Future.delayed(Duration(milliseconds: heartbeatIntervalMs));

      // Bridge joins
      events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'Bridge joins'));
      await bridge.joinOperation(operationId);
      await bridge.pushStackFrame('bridge-process');
      bridge.startHeartbeat(expectedStackDepth: 2);

      // Simulate work
      await Future.delayed(Duration(milliseconds: processingMs));

      // Bridge completes
      events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'Bridge completes'));
      bridge.stopHeartbeat();
      await bridge.popStackFrame('bridge-process');

      // CLI completes
      events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'CLI completes'));
      cli.stopHeartbeat();
      await cli.popStackFrame('cli-main');
      await cli.completeOperation();

      stopwatch.stop();
      _log('');
      _log('Happy path completed in ${stopwatch.elapsedMilliseconds}ms');

      return ConcurrentScenarioResult(
        success: true,
        events: events,
        elapsed: stopwatch.elapsed,
        log: List.from(_logOutput),
      );
    } finally {
      await _cleanup();
    }
  }

  /// Run a user abort scenario with true parallel execution.
  Future<ConcurrentScenarioResult> runAbortScenario({
    required int abortAfterMs,
    int heartbeatIntervalMs = 200,
    int heartbeatTimeoutMs = 1000,
    int maxWaitMs = 10000,
  }) async {
    await _initialize(
      heartbeatIntervalMs: heartbeatIntervalMs,
      heartbeatTimeoutMs: heartbeatTimeoutMs,
    );

    final stopwatch = Stopwatch()..start();
    final events = <ScenarioEvent>[];

    try {
      _log('════════════════════════════════════════════════════════════════════');
      _log('User Abort Scenario (Isolate-based)');
      _log('════════════════════════════════════════════════════════════════════');
      _log('Abort after ${abortAfterMs}ms');
      _log('');

      final cli = _participants['CLI']!;
      final bridge = _participants['Bridge']!;

      // CLI starts
      events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'CLI starts operation'));
      final operationId = await cli.startOperation();
      await cli.pushStackFrame('cli-main');
      cli.startHeartbeat(expectedStackDepth: 1);

      await Future.delayed(Duration(milliseconds: heartbeatIntervalMs ~/ 2));

      // Bridge joins
      events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'Bridge joins operation'));
      await bridge.joinOperation(operationId);
      await bridge.pushStackFrame('bridge-process');
      bridge.startHeartbeat(expectedStackDepth: 2);

      // Schedule abort
      Timer(Duration(milliseconds: abortAfterMs), () async {
        events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'USER ABORT (Ctrl+C)'));
        _log('');
        _log('>>> USER ABORT (Ctrl+C) <<<');
        _log('');
        await cli.setAbortFlag(true);
      });

      // Wait for abort detection
      _log('Waiting for abort detection...');
      final detectors = _participants.values.map((p) => p.onFailureDetected).toList();

      try {
        final detection = await Future.any(detectors)
            .timeout(Duration(milliseconds: maxWaitMs));

        events.add(ScenarioEvent(
          stopwatch.elapsedMilliseconds,
          '${detection.participant} detected: ${detection.type}',
        ));

        _log('');
        _log('────────────────────────────────────────');
        _log('Abort Detected!');
        _log('────────────────────────────────────────');
        _log('${detection.participant} detected ${detection.type}: ${detection.message}');

        // Cleanup
        for (final p in _participants.values) {
          p.stopHeartbeat();
        }

        stopwatch.stop();
        return ConcurrentScenarioResult(
          success: true,
          detectedFailure: detection,
          events: events,
          elapsed: stopwatch.elapsed,
          log: List.from(_logOutput),
        );
      } on TimeoutException {
        events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'TIMEOUT: No abort detected'));
        stopwatch.stop();
        return ConcurrentScenarioResult(
          success: false,
          errorMessage: 'Timeout: No abort detected within ${maxWaitMs}ms',
          events: events,
          elapsed: stopwatch.elapsed,
          log: List.from(_logOutput),
        );
      }
    } finally {
      await _cleanup();
    }
  }
}
