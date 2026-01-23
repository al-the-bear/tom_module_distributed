/// Isolate-based Scenario Runner
///
/// Provides true parallel execution by running each participant in a separate
/// Dart Isolate. This more accurately simulates real-world distributed systems
/// where CLI, Bridge, and VS Code are separate processes.
///
/// Key architecture:
/// - Each participant runs in its own [Isolate] with its own [Ledger] instance
/// - Isolates run normal code (like in examples) not step-by-step commands
/// - Communication happens via [SendPort]/[ReceivePort] for start/result/events
/// - Ledger files are the shared state (file system)
/// - Crashes are simulated with [Isolate.kill()]
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import '../ledger_api/ledger_api.dart';
import '../local_ledger/file_ledger.dart' show HeartbeatResult;
import 'concurrent_scenario.dart';

// ─────────────────────────────────────────────────────────────
// Isolate Types
// ─────────────────────────────────────────────────────────────

/// The type of participant behavior to run in an isolate.
enum IsolateType {
  /// CLI-like behavior: Creates operation, waits for work, completes.
  cli,

  /// Bridge-like behavior: Joins operation, does work, returns result.
  bridge,

  /// VS Code-like behavior: Joins operation, monitors, responds to events.
  vscode,

  /// Custom behavior defined by the test.
  custom,
}

// ─────────────────────────────────────────────────────────────
// Message Protocol
// ─────────────────────────────────────────────────────────────

/// Commands sent from main isolate to participant.
enum IsolateCommand {
  /// Start executing the participant's work.
  start,

  /// Simulate a crash (Isolate.kill).
  crash,

  /// Set abort flag in ledger.
  setAbortFlag,

  /// Clean shutdown.
  shutdown,
}

/// Message sent to a participant isolate.
class IsolateMessage {
  final IsolateCommand command;
  final Map<String, dynamic> params;

  IsolateMessage(this.command, [this.params = const {}]);
}

/// Response types from participant isolates.
enum IsolateResponseType {
  /// Ready to receive commands.
  ready,

  /// Work completed successfully.
  completed,

  /// Work failed with error.
  error,

  /// Failure detected through heartbeat/monitoring.
  failureDetected,

  /// Log message for display.
  log,

  /// Event notification (operation started, joined, etc).
  event,
}

/// A response from a participant isolate.
class IsolateResponse {
  final IsolateResponseType type;
  final String? message;
  final Map<String, dynamic>? data;

  IsolateResponse(this.type, {this.message, this.data});
}

// ─────────────────────────────────────────────────────────────
// Isolate Configuration
// ─────────────────────────────────────────────────────────────

/// Configuration passed to participant isolate on spawn.
class IsolateParticipantConfig {
  /// Participant name (e.g., 'CLI', 'Bridge').
  final String name;

  /// Process ID for this participant.
  final int pid;

  /// Path to ledger directory.
  final String basePath;

  /// Type of behavior to run.
  final IsolateType isolateType;

  /// Heartbeat interval in milliseconds.
  final int heartbeatIntervalMs;

  /// Heartbeat timeout/staleness threshold in milliseconds.
  final int heartbeatTimeoutMs;

  /// How long to simulate work (milliseconds).
  final int workDurationMs;

  /// Operation ID to join (for non-initiators).
  final String? operationId;

  /// Port to send responses back to parent.
  final SendPort sendPort;

  /// Custom parameters for the isolate.
  final Map<String, dynamic> customParams;

  IsolateParticipantConfig({
    required this.name,
    required this.pid,
    required this.basePath,
    required this.isolateType,
    required this.heartbeatIntervalMs,
    required this.heartbeatTimeoutMs,
    required this.sendPort,
    this.workDurationMs = 1000,
    this.operationId,
    this.customParams = const {},
  });
}

// ─────────────────────────────────────────────────────────────
// Isolate Entry Point
// ─────────────────────────────────────────────────────────────

/// Entry point for participant isolate.
Future<void> _participantIsolateEntry(IsolateParticipantConfig config) async {
  final receivePort = ReceivePort();
  config.sendPort.send(receivePort.sendPort);

  final runner = _IsolateRunner(config);
  await runner.run(receivePort);
}

/// Internal runner that executes in the participant isolate.
class _IsolateRunner {
  final IsolateParticipantConfig config;
  late final Ledger _ledger;
  Operation? _operation;
  bool _crashed = false;

  _IsolateRunner(this.config);

  String get name => config.name;

  void _log(String message) {
    config.sendPort.send(IsolateResponse(
      IsolateResponseType.log,
      message: '[$name] $message',
    ));
  }

  void _event(String event, [Map<String, dynamic>? data]) {
    config.sendPort.send(IsolateResponse(
      IsolateResponseType.event,
      message: event,
      data: data,
    ));
  }

  void _sendResponse(IsolateResponseType type, {String? message, Map<String, dynamic>? data}) {
    config.sendPort.send(IsolateResponse(type, message: message, data: data));
  }

  void _failureDetected(DetectedFailureType type, String message) {
    _sendResponse(
      IsolateResponseType.failureDetected,
      data: {
        'type': type.name,
        'participant': name,
        'message': message,
      },
    );
  }

  Future<void> run(ReceivePort receivePort) async {
    // Create ledger instance
    _ledger = Ledger(
      basePath: config.basePath,
      participantId: name.toLowerCase(),
      participantPid: config.pid,
      heartbeatInterval: Duration(milliseconds: config.heartbeatIntervalMs),
      staleThreshold: Duration(milliseconds: config.heartbeatTimeoutMs),
      onBackupCreated: (path) {
        final relativePath = path.replaceFirst('${config.basePath}/', '');
        _log('backup → $relativePath');
      },
    );

    // Signal ready
    _sendResponse(IsolateResponseType.ready);

    // Wait for commands
    await for (final message in receivePort) {
      if (message is! IsolateMessage) continue;

      try {
        await _handleCommand(message);
      } catch (e, st) {
        _log('ERROR: $e\n$st');
        _sendResponse(
          IsolateResponseType.error,
          message: 'Error handling ${message.command}: $e',
          data: {'stackTrace': st.toString()},
        );
      }
    }
  }

  Future<void> _handleCommand(IsolateMessage message) async {
    switch (message.command) {
      case IsolateCommand.start:
        // Run behavior non-blocking so we can still receive commands
        unawaited(_executeParticipantBehavior());

      case IsolateCommand.crash:
        _log('💥 CRASH');
        _crashed = true;
        // Kill immediately - no cleanup
        Isolate.exit();

      case IsolateCommand.setAbortFlag:
        final value = message.params['value'] as bool? ?? true;
        _log('setAbortFlag($value)');
        if (_operation != null) {
          await _operation!.setAbortFlag(value);
        }
        _sendResponse(IsolateResponseType.completed);

      case IsolateCommand.shutdown:
        _log('shutdown()');
        await _cleanup();
        _sendResponse(IsolateResponseType.completed);
        Isolate.exit();
    }
  }

  Future<void> _cleanup() async {
    _operation?.stopHeartbeat();
    _ledger.dispose();
  }

  /// Execute behavior based on isolate type.
  Future<void> _executeParticipantBehavior() async {
    switch (config.isolateType) {
      case IsolateType.cli:
        await _runCliParticipant();
      case IsolateType.bridge:
        await _runBridgeParticipant();
      case IsolateType.vscode:
        await _runVscodeParticipant();
      case IsolateType.custom:
        await _runCustomParticipant();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // CLI Participant Behavior
  // ─────────────────────────────────────────────────────────────

  /// CLI behavior: Create operation, wait for children, complete.
  Future<void> _runCliParticipant() async {
    _log('startOperation()');
    _operation = await _ledger.createOperation(
      description: 'CLI initiated operation',
    );
    _operation!.stalenessThresholdMs = config.heartbeatTimeoutMs;

    final operationId = _operation!.operationId;
    _log('  → operationId: "$operationId"');
    _event('operationStarted', {'operationId': operationId});

    // Start a call
    final call = await _operation!.startCall<void>(
      description: 'cli-main',
      callback: CallCallback(
        onCleanup: () async {
          _log('cleanup: cli-main');
        },
      ),
    );

    // Start heartbeat with failure detection
    _startHeartbeatWithDetection(expectedMinStack: 1);

    // Wait for work duration or failure
    final workComplete = await _waitWithFailureDetection(
      Duration(milliseconds: config.workDurationMs),
    );

    if (workComplete) {
      // End call and complete
      _stopHeartbeat();
      await call.end();
      await _operation!.complete();
      _log('operation completed');
      _sendResponse(IsolateResponseType.completed, data: {'operationId': operationId});
    }
    // If not complete, failure was already reported
  }

  // ─────────────────────────────────────────────────────────────
  // Bridge Participant Behavior
  // ─────────────────────────────────────────────────────────────

  /// Bridge behavior: Join operation, do work, return result.
  Future<void> _runBridgeParticipant() async {
    final operationId = config.operationId;
    if (operationId == null) {
      throw StateError('Bridge requires operationId to join');
    }

    _log('joinOperation($operationId)');
    _operation = await _ledger.joinOperation(operationId: operationId);
    _operation!.stalenessThresholdMs = config.heartbeatTimeoutMs;
    _event('operationJoined', {'operationId': operationId});

    // Start a call
    final call = await _operation!.startCall<String>(
      description: 'bridge-process',
      callback: CallCallback<String>(
        onCleanup: () async {
          _log('cleanup: bridge-process');
        },
      ),
    );

    // Start heartbeat with failure detection
    _startHeartbeatWithDetection(expectedMinStack: 2);

    // Simulate work
    _log('processing for ${config.workDurationMs}ms...');
    final workComplete = await _waitWithFailureDetection(
      Duration(milliseconds: config.workDurationMs),
    );

    if (workComplete) {
      // End call with result
      _stopHeartbeat();
      await call.end('Bridge work completed');
      _log('work completed');
      _sendResponse(IsolateResponseType.completed, data: {
        'result': 'success',
        'operationId': operationId,
      });
    }
  }

  // ─────────────────────────────────────────────────────────────
  // VS Code Participant Behavior
  // ─────────────────────────────────────────────────────────────

  /// VS Code behavior: Join, monitor, respond to events.
  Future<void> _runVscodeParticipant() async {
    final operationId = config.operationId;
    if (operationId == null) {
      throw StateError('VSCode requires operationId to join');
    }

    _log('joinOperation($operationId)');
    _operation = await _ledger.joinOperation(operationId: operationId);
    _operation!.stalenessThresholdMs = config.heartbeatTimeoutMs;
    _event('operationJoined', {'operationId': operationId});

    // Start monitoring heartbeat
    _startHeartbeatWithDetection(expectedMinStack: 1);

    // Wait indefinitely until shutdown or failure
    await _waitWithFailureDetection(const Duration(hours: 1));
  }

  // ─────────────────────────────────────────────────────────────
  // Custom Participant Behavior
  // ─────────────────────────────────────────────────────────────

  /// Custom behavior: Defined by test via customParams.
  Future<void> _runCustomParticipant() async {
    final behaviorName = config.customParams['behavior'] as String?;
    _log('running custom behavior: $behaviorName');

    // Custom behaviors can be added here
    switch (behaviorName) {
      case 'initiator':
        await _runCliParticipant();
      case 'worker':
        await _runBridgeParticipant();
      case 'monitor':
        await _runVscodeParticipant();
      default:
        _log('unknown custom behavior: $behaviorName');
        _sendResponse(IsolateResponseType.error, message: 'Unknown behavior: $behaviorName');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Heartbeat with Failure Detection
  // ─────────────────────────────────────────────────────────────

  Timer? _heartbeatTimer;
  final _random = Random();
  int _expectedMinStack = 1;
  bool _failureReported = false;
  final _failureCompleter = Completer<void>();

  void _startHeartbeatWithDetection({required int expectedMinStack}) {
    _expectedMinStack = expectedMinStack;
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

  String? get _operationFilePath {
    if (_operation == null) return null;
    return '${config.basePath}/${_operation!.operationId}.operation.json';
  }

  Future<void> _performHeartbeat() async {
    if (_crashed || _operation == null || _failureReported) return;

    try {
      // Retry loop for lock contention
      HeartbeatResult? maybeResult;
      while (maybeResult == null) {
        if (_crashed || _operation == null || _failureReported) return;

        maybeResult = await _operation!.heartbeat();
        if (maybeResult == null) {
          // Check if file still exists
          final filePath = _operationFilePath;
          if (filePath != null && !File(filePath).existsSync()) {
            _log('♥ DETECTED: Operation file gone!');
            _reportFailure(
              DetectedFailureType.heartbeatError,
              'Operation file no longer exists',
            );
            return;
          }
          // Lock contention - wait 50ms +/- 10ms jitter and retry
          final jitterMs = 50 + _random.nextInt(21) - 10;
          await Future.delayed(Duration(milliseconds: jitterMs));
        }
      }
      final result = maybeResult;

      // Check for abort
      if (result.abortFlag) {
        _log('♥ DETECTED: Abort flag set!');
        _reportFailure(DetectedFailureType.abortRequested, 'Abort flag set');
        return;
      }

      // Check for stale heartbeats
      if (result.hasStaleChildren) {
        final staleList = result.staleParticipants.join(', ');
        final staleAges = result.staleParticipants
            .map((p) => '$p: ${result.participantHeartbeatAges[p]}ms')
            .join(', ');
        _log('♥ DETECTED: Stale participant(s): [$staleList] - crash detected! Ages: $staleAges');
        _reportFailure(
          DetectedFailureType.staleHeartbeat,
          'Stale participants: $staleList (ages: $staleAges)',
        );
        return;
      }

      // Check stack depth
      if (result.stackDepth < _expectedMinStack) {
        _log('♥ DETECTED: Stack reduced! Expected $_expectedMinStack, found ${result.stackDepth}');
        _reportFailure(
          DetectedFailureType.childDisappeared,
          'Expected stack depth $_expectedMinStack, found ${result.stackDepth}',
        );
        return;
      }

      // Success
      _log('♥ heartbeat OK (stack: ${result.stackDepth}, age: ${result.heartbeatAgeMs}ms)');
    } catch (e) {
      _log('♥ ERROR: $e');
      _reportFailure(DetectedFailureType.heartbeatError, e.toString());
    }
  }

  void _reportFailure(DetectedFailureType type, String message) {
    if (_failureReported) return;
    _failureReported = true;
    _stopHeartbeat();
    _failureDetected(type, message);
    if (!_failureCompleter.isCompleted) {
      _failureCompleter.complete();
    }
  }

  /// Wait for duration or until failure detected.
  /// Returns true if duration completed, false if failure detected.
  Future<bool> _waitWithFailureDetection(Duration duration) async {
    final timeout = Future.delayed(duration);
    final result = await Future.any([
      timeout.then((_) => true),
      _failureCompleter.future.then((_) => false),
    ]);
    return result;
  }
}

// ─────────────────────────────────────────────────────────────
// IsolateParticipantHandle
// ─────────────────────────────────────────────────────────────

/// Handle to control a participant running in a separate isolate.
class IsolateParticipantHandle {
  final String name;
  final IsolateType isolateType;
  final Isolate isolate;
  final SendPort sendPort;
  final Stream<IsolateResponse> responses;
  final StreamController<IsolateResponse> _responseController;
  final void Function(String)? _onLog;

  String? _operationId;
  String? get operationId => _operationId;

  bool _isCrashed = false;
  bool get isCrashed => _isCrashed;

  final Completer<FailureDetection> _failureDetected = Completer<FailureDetection>();
  Future<FailureDetection> get onFailureDetected => _failureDetected.future;

  final Completer<Map<String, dynamic>> _completed = Completer<Map<String, dynamic>>();
  Future<Map<String, dynamic>> get onCompleted => _completed.future;

  IsolateParticipantHandle._({
    required this.name,
    required this.isolateType,
    required this.isolate,
    required this.sendPort,
    required StreamController<IsolateResponse> responseController,
    void Function(String)? onLog,
  })  : _responseController = responseController,
        _onLog = onLog,
        responses = responseController.stream.asBroadcastStream();

  /// Spawn a new participant in a separate isolate.
  static Future<IsolateParticipantHandle> spawn({
    required String name,
    required int pid,
    required String basePath,
    required IsolateType isolateType,
    required int heartbeatIntervalMs,
    required int heartbeatTimeoutMs,
    int workDurationMs = 1000,
    String? operationId,
    Map<String, dynamic> customParams = const {},
    void Function(String)? onLog,
  }) async {
    final receivePort = ReceivePort();
    final responseController = StreamController<IsolateResponse>.broadcast();

    final config = IsolateParticipantConfig(
      name: name,
      pid: pid,
      basePath: basePath,
      isolateType: isolateType,
      heartbeatIntervalMs: heartbeatIntervalMs,
      heartbeatTimeoutMs: heartbeatTimeoutMs,
      workDurationMs: workDurationMs,
      operationId: operationId,
      customParams: customParams,
      sendPort: receivePort.sendPort,
    );

    final isolate = await Isolate.spawn(
      _participantIsolateEntry,
      config,
      debugName: 'Participant-$name',
    );

    final broadcastStream = receivePort.asBroadcastStream();

    // First message is the isolate's send port
    final isolateSendPort = await broadcastStream.first as SendPort;

    // Listen for responses
    broadcastStream.listen((message) {
      if (responseController.isClosed) return;
      if (message is IsolateResponse) {
        if (message.type == IsolateResponseType.log && onLog != null) {
          onLog(message.message ?? '');
        }
        responseController.add(message);
      }
    });

    final handle = IsolateParticipantHandle._(
      name: name,
      isolateType: isolateType,
      isolate: isolate,
      sendPort: isolateSendPort,
      responseController: responseController,
      onLog: onLog,
    );

    // Wait for ready
    await responseController.stream
        .firstWhere((r) => r.type == IsolateResponseType.ready);

    // Listen for events, failures, and completions
    responseController.stream.listen((response) {
      switch (response.type) {
        case IsolateResponseType.event:
          if (response.message == 'operationStarted') {
            handle._operationId = response.data?['operationId'] as String?;
          }

        case IsolateResponseType.failureDetected:
          if (!handle._failureDetected.isCompleted) {
            final data = response.data!;
            handle._failureDetected.complete(FailureDetection(
              type: DetectedFailureType.values.byName(data['type'] as String),
              participant: data['participant'] as String,
              message: data['message'] as String,
            ));
          }

        case IsolateResponseType.completed:
          if (!handle._completed.isCompleted) {
            handle._completed.complete(response.data ?? {});
          }

        default:
          break;
      }
    });

    return handle;
  }

  void _send(IsolateCommand command, [Map<String, dynamic> params = const {}]) {
    if (_isCrashed) return;
    sendPort.send(IsolateMessage(command, params));
  }

  /// Start the participant's work.
  void start() {
    _send(IsolateCommand.start);
  }

  /// Set abort flag in ledger.
  void setAbortFlag(bool value) {
    _send(IsolateCommand.setAbortFlag, {'value': value});
  }

  /// Simulate a crash - kill the isolate immediately.
  void crash() {
    _onLog?.call('[$name] 💥 CRASH');
    _isCrashed = true;
    isolate.kill(priority: Isolate.immediate);
  }

  /// Shutdown the participant gracefully.
  Future<void> shutdown() async {
    if (_isCrashed) {
      isolate.kill(priority: Isolate.immediate);
      return;
    }
    _send(IsolateCommand.shutdown);
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

  Future<void> _cleanup() async {
    for (final p in _participants.values) {
      p.forceKill();
    }
    _participants.clear();
  }

  /// Run a crash detection scenario.
  Future<ConcurrentScenarioResult> runCrashDetectionScenario({
    required String crashingParticipant,
    required int crashAfterMs,
    int heartbeatIntervalMs = 1000,
    int heartbeatTimeoutMs = 3000,
    int workDurationMs = 5000,
    int maxWaitMs = 15000,
  }) async {
    _logOutput.clear();
    _participants.clear();

    final stopwatch = Stopwatch()..start();
    final events = <ScenarioEvent>[];

    try {
      _log('════════════════════════════════════════════════════════════════════');
      _log('Crash Detection Scenario (Isolate-based)');
      _log('════════════════════════════════════════════════════════════════════');
      _log('Crash target: $crashingParticipant after ${crashAfterMs}ms');
      _log('Heartbeat interval: ${heartbeatIntervalMs}ms, timeout: ${heartbeatTimeoutMs}ms');
      _log('');

      // Spawn CLI (initiator)
      _participants['CLI'] = await IsolateParticipantHandle.spawn(
        name: 'CLI',
        pid: 1001,
        basePath: ledgerPath,
        isolateType: IsolateType.cli,
        heartbeatIntervalMs: heartbeatIntervalMs,
        heartbeatTimeoutMs: heartbeatTimeoutMs,
        workDurationMs: workDurationMs + maxWaitMs,
        onLog: _log,
      );

      final cli = _participants['CLI']!;

      // Start CLI
      events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'CLI starts operation'));
      cli.start();

      // Wait for CLI to create operation
      await cli.responses
          .firstWhere((r) => r.type == IsolateResponseType.event && r.message == 'operationStarted')
          .timeout(const Duration(seconds: 5));

      final operationId = cli.operationId!;

      // Small delay before bridge joins
      await Future.delayed(Duration(milliseconds: heartbeatIntervalMs ~/ 2));

      // Spawn Bridge
      _participants['Bridge'] = await IsolateParticipantHandle.spawn(
        name: 'Bridge',
        pid: 2001,
        basePath: ledgerPath,
        isolateType: IsolateType.bridge,
        heartbeatIntervalMs: heartbeatIntervalMs,
        heartbeatTimeoutMs: heartbeatTimeoutMs,
        workDurationMs: workDurationMs + maxWaitMs,
        operationId: operationId,
        onLog: _log,
      );

      final bridge = _participants['Bridge']!;

      events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'Bridge joins operation'));
      bridge.start();

      // Wait for Bridge to join
      await bridge.responses
          .firstWhere((r) => r.type == IsolateResponseType.event && r.message == 'operationJoined')
          .timeout(const Duration(seconds: 5));

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

  /// Run a happy path scenario.
  Future<ConcurrentScenarioResult> runHappyPath({
    int processingMs = 500,
    int heartbeatIntervalMs = 100,
    int heartbeatTimeoutMs = 2000,
  }) async {
    _logOutput.clear();
    _participants.clear();

    final stopwatch = Stopwatch()..start();
    final events = <ScenarioEvent>[];

    try {
      _log('════════════════════════════════════════════════════════════════════');
      _log('Happy Path Scenario (Isolate-based)');
      _log('════════════════════════════════════════════════════════════════════');
      _log('');

      // Spawn CLI
      _participants['CLI'] = await IsolateParticipantHandle.spawn(
        name: 'CLI',
        pid: 1001,
        basePath: ledgerPath,
        isolateType: IsolateType.cli,
        heartbeatIntervalMs: heartbeatIntervalMs,
        heartbeatTimeoutMs: heartbeatTimeoutMs,
        workDurationMs: processingMs * 3,
        onLog: _log,
      );

      final cli = _participants['CLI']!;

      // Start CLI
      events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'CLI starts'));
      cli.start();

      // Wait for operation
      await cli.responses
          .firstWhere((r) => r.type == IsolateResponseType.event && r.message == 'operationStarted')
          .timeout(const Duration(seconds: 5));

      final operationId = cli.operationId!;

      await Future.delayed(Duration(milliseconds: heartbeatIntervalMs));

      // Spawn Bridge
      _participants['Bridge'] = await IsolateParticipantHandle.spawn(
        name: 'Bridge',
        pid: 2001,
        basePath: ledgerPath,
        isolateType: IsolateType.bridge,
        heartbeatIntervalMs: heartbeatIntervalMs,
        heartbeatTimeoutMs: heartbeatTimeoutMs,
        workDurationMs: processingMs,
        operationId: operationId,
        onLog: _log,
      );

      final bridge = _participants['Bridge']!;

      events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'Bridge joins'));
      bridge.start();

      // Wait for bridge to complete
      await bridge.onCompleted.timeout(const Duration(seconds: 30));
      events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'Bridge completes'));

      // Wait for CLI to complete
      await cli.onCompleted.timeout(const Duration(seconds: 30));
      events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'CLI completes'));

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

  /// Run a user abort scenario.
  Future<ConcurrentScenarioResult> runAbortScenario({
    required int abortAfterMs,
    int heartbeatIntervalMs = 200,
    int heartbeatTimeoutMs = 1000,
    int maxWaitMs = 10000,
  }) async {
    _logOutput.clear();
    _participants.clear();

    final stopwatch = Stopwatch()..start();
    final events = <ScenarioEvent>[];

    try {
      _log('════════════════════════════════════════════════════════════════════');
      _log('User Abort Scenario (Isolate-based)');
      _log('════════════════════════════════════════════════════════════════════');
      _log('Abort after ${abortAfterMs}ms');
      _log('');

      // Spawn CLI
      _participants['CLI'] = await IsolateParticipantHandle.spawn(
        name: 'CLI',
        pid: 1001,
        basePath: ledgerPath,
        isolateType: IsolateType.cli,
        heartbeatIntervalMs: heartbeatIntervalMs,
        heartbeatTimeoutMs: heartbeatTimeoutMs,
        workDurationMs: maxWaitMs * 2,
        onLog: _log,
      );

      final cli = _participants['CLI']!;

      events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'CLI starts operation'));
      cli.start();

      await cli.responses
          .firstWhere((r) => r.type == IsolateResponseType.event && r.message == 'operationStarted')
          .timeout(const Duration(seconds: 5));

      final operationId = cli.operationId!;

      await Future.delayed(Duration(milliseconds: heartbeatIntervalMs ~/ 2));

      // Spawn Bridge
      _participants['Bridge'] = await IsolateParticipantHandle.spawn(
        name: 'Bridge',
        pid: 2001,
        basePath: ledgerPath,
        isolateType: IsolateType.bridge,
        heartbeatIntervalMs: heartbeatIntervalMs,
        heartbeatTimeoutMs: heartbeatTimeoutMs,
        workDurationMs: maxWaitMs * 2,
        operationId: operationId,
        onLog: _log,
      );

      final bridge = _participants['Bridge']!;

      events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'Bridge joins operation'));
      bridge.start();

      await bridge.responses
          .firstWhere((r) => r.type == IsolateResponseType.event && r.message == 'operationJoined')
          .timeout(const Duration(seconds: 5));

      // Schedule abort
      Timer(Duration(milliseconds: abortAfterMs), () {
        events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'USER ABORT (Ctrl+C)'));
        _log('');
        _log('>>> USER ABORT (Ctrl+C) <<<');
        _log('');
        cli.setAbortFlag(true);
      });

      // Wait for detection
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
