/// Isolate-based Scenario Runner
///
/// Provides true parallel execution by running each participant in a separate
/// Dart Isolate. This more accurately simulates real-world distributed systems
/// where CLI, Bridge, and VS Code are separate processes.
///
/// Key architecture:
/// - Each participant runs in its own [Isolate] with its own [Ledger] instance
/// - Isolates run normal code (like in examples) not step-by-step commands
/// - All behavior is config-driven - no commands except shutdown
/// - Crashes, errors, and aborts are scheduled via configuration
/// - Ledger files are the shared state (file system)
library;

import 'dart:async';
import 'dart:isolate';

import '../ledger_api/ledger_api.dart';
import 'concurrent_scenario.dart';

// ─────────────────────────────────────────────────────────────
// Isolate Types
// ─────────────────────────────────────────────────────────────

/// The type of participant behavior to run in an isolate.
enum IsolateType {
  /// CLI-like behavior: Creates operation, waits for work to complete, completes.
  cli,

  /// Bridge/VSCode-like behavior: Joins operation, waits for events, acts, waits.
  /// Runs in an event-driven loop until shutdown or failure.
  bridge,

  /// Custom behavior defined by the test.
  custom,
}

// ─────────────────────────────────────────────────────────────
// Scenario Configuration
// ─────────────────────────────────────────────────────────────

/// Type of failure to simulate.
enum SimulatedFailure {
  /// No failure - normal operation.
  none,

  /// Crash: stop heartbeat and become unresponsive (long delay).
  crash,

  /// Error: clean failure with error result, operation cleanup.
  error,
}

/// Configuration for scenario events (failures, aborts).
class ScenarioConfig {
  /// Type of failure to simulate.
  final SimulatedFailure failureType;

  /// Time after start when failure occurs (milliseconds). 0 = no failure.
  final int failAfterMs;

  /// Error message for error failures.
  final String? errorMessage;

  /// Time after start when abort flag is set (milliseconds). 0 = no abort.
  /// Only meaningful for the participant that owns the operation (CLI).
  final int abortAfterMs;

  const ScenarioConfig({
    this.failureType = SimulatedFailure.none,
    this.failAfterMs = 0,
    this.errorMessage,
    this.abortAfterMs = 0,
  });

  static const none = ScenarioConfig();

  /// Create a crash scenario config.
  factory ScenarioConfig.crash({required int afterMs}) =>
      ScenarioConfig(failureType: SimulatedFailure.crash, failAfterMs: afterMs);

  /// Create an error scenario config.
  factory ScenarioConfig.error({required int afterMs, String? message}) =>
      ScenarioConfig(
        failureType: SimulatedFailure.error,
        failAfterMs: afterMs,
        errorMessage: message ?? 'Simulated error',
      );

  /// Create an abort scenario config.
  factory ScenarioConfig.abort({required int afterMs}) =>
      ScenarioConfig(abortAfterMs: afterMs);

  bool get hasFailure => failureType != SimulatedFailure.none;
  bool get hasAbort => abortAfterMs > 0;
}

// ─────────────────────────────────────────────────────────────
// Message Protocol
// ─────────────────────────────────────────────────────────────

/// Commands sent from main isolate to participant.
/// Only shutdown - all other behavior is config-driven.
enum IsolateCommand {
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
  /// Isolate started and behavior is running.
  started,

  /// Work completed successfully.
  completed,

  /// Work failed with error.
  error,

  /// Failure detected through heartbeat/monitoring.
  failureDetected,

  /// Simulated crash occurred (for test coordination).
  crashed,

  /// Abort flag was set (for test coordination).
  abortSet,

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

  /// Scenario configuration (failures, aborts).
  final ScenarioConfig scenarioConfig;

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
    this.scenarioConfig = const ScenarioConfig(),
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
  late final LocalLedger _ledger;
  Operation? _operation;
  bool _crashed = false;
  bool _hasError = false;
  String? _errorMessage;
  Timer? _failureTimer;
  Timer? _abortTimer;

  /// Completer that signals an error occurred (for behavior to handle).
  final _errorCompleter = Completer<String>();

  /// Completer that signals wait should be interrupted (crash/error).
  final _waitCompleter = Completer<void>();

  _IsolateRunner(this.config);

  String get name => config.name;

  /// Map HeartbeatErrorType to DetectedFailureType for consistent reporting.
  DetectedFailureType _mapHeartbeatError(HeartbeatErrorType type) {
    return switch (type) {
      HeartbeatErrorType.heartbeatStale => DetectedFailureType.staleHeartbeat,
      HeartbeatErrorType.abortFlagSet => DetectedFailureType.abortRequested,
      HeartbeatErrorType.ledgerNotFound => DetectedFailureType.heartbeatError,
      HeartbeatErrorType.ioError => DetectedFailureType.heartbeatError,
      HeartbeatErrorType.lockFailed => DetectedFailureType.heartbeatError,
    };
  }

  void _log(String message) {
    config.sendPort.send(
      IsolateResponse(IsolateResponseType.log, message: '[$name] $message'),
    );
  }

  void _event(String event, [Map<String, dynamic>? data]) {
    config.sendPort.send(
      IsolateResponse(IsolateResponseType.event, message: event, data: data),
    );
  }

  void _sendResponse(
    IsolateResponseType type, {
    String? message,
    Map<String, dynamic>? data,
  }) {
    config.sendPort.send(IsolateResponse(type, message: message, data: data));
  }

  Future<void> run(ReceivePort receivePort) async {
    // Signal started
    _sendResponse(IsolateResponseType.started);

    // Create ledger instance
    _ledger = LocalLedger(
      basePath: config.basePath,
      participantId: name.toLowerCase(),
      participantPid: config.pid,
      heartbeatInterval: Duration(milliseconds: config.heartbeatIntervalMs),
      staleThreshold: Duration(milliseconds: config.heartbeatTimeoutMs),
      callback: LedgerCallback(
        onBackupCreated: (path) {
          final relativePath = path.replaceFirst('${config.basePath}/', '');
          _log('backup → $relativePath');
        },
      ),
    );

    // Auto-start behavior (non-blocking to allow shutdown command)
    // Scheduled events (failures, aborts) are triggered inside behavior execution
    unawaited(_executeParticipantBehavior());

    // Wait for shutdown command only
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
      case IsolateCommand.shutdown:
        _log('shutdown()');
        _failureTimer?.cancel();
        _abortTimer?.cancel();
        await _cleanup();
        _sendResponse(IsolateResponseType.completed);
        Isolate.exit();
    }
  }

  void _scheduleConfiguredEvents() {
    // Schedule failure if configured
    if (config.scenarioConfig.hasFailure) {
      _failureTimer = Timer(
        Duration(milliseconds: config.scenarioConfig.failAfterMs),
        _executeConfiguredFailure,
      );
    }

    // Schedule abort if configured
    if (config.scenarioConfig.hasAbort) {
      _abortTimer = Timer(
        Duration(milliseconds: config.scenarioConfig.abortAfterMs),
        _executeConfiguredAbort,
      );
    }
  }

  void _executeConfiguredFailure() {
    switch (config.scenarioConfig.failureType) {
      case SimulatedFailure.none:
        break;

      case SimulatedFailure.crash:
        _simulateCrash();

      case SimulatedFailure.error:
        _simulateError(config.scenarioConfig.errorMessage ?? 'Simulated error');
    }
  }

  Future<void> _executeConfiguredAbort() async {
    if (_crashed || _hasError || _operation == null) return;

    _log('setAbortFlag(true) [scheduled]');
    await _operation!.setAbortFlag(true);
    _sendResponse(IsolateResponseType.abortSet, message: 'Abort flag set');
  }

  /// Simulate a crash: stop heartbeat and become unresponsive.
  /// Does NOT kill the isolate - just stops participating.
  void _simulateCrash() {
    if (_crashed) return;
    _crashed = true;
    _log('💥 CRASH (stopping heartbeat, becoming unresponsive)');
    _operation?.stopHeartbeat();
    _sendResponse(IsolateResponseType.crashed, message: 'Simulated crash');
    // Stay alive but unresponsive - don't exit isolate
    // The heartbeat staleness will be detected by other participants
    // Complete the wait completer to interrupt any wait
    if (!_waitCompleter.isCompleted) {
      _waitCompleter.complete();
    }
  }

  /// Simulate an error: signal error for behavior to handle cleanly.
  void _simulateError(String errorMessage) {
    if (_hasError || _crashed) return;
    _hasError = true;
    _errorMessage = errorMessage;
    _log('❌ ERROR: $errorMessage');

    // Signal error to behavior (it will end the call properly)
    if (!_errorCompleter.isCompleted) {
      _errorCompleter.complete(errorMessage);
    }

    // Complete the wait completer to interrupt any wait
    if (!_waitCompleter.isCompleted) {
      _waitCompleter.complete();
    }

    // Send error response for test coordination
    _sendResponse(
      IsolateResponseType.error,
      message: errorMessage,
      data: {'errorType': 'simulated'},
    );
  }

  Future<void> _cleanup() async {
    _failureTimer?.cancel();
    _abortTimer?.cancel();
    _ledger.dispose();
  }

  /// Execute behavior based on isolate type.
  Future<void> _executeParticipantBehavior() async {
    switch (config.isolateType) {
      case IsolateType.cli:
        await _runCliParticipant();
      case IsolateType.bridge:
        await _runBridgeParticipant();
      case IsolateType.custom:
        await _runCustomParticipant();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // CLI Participant Behavior
  // ─────────────────────────────────────────────────────────────

  /// CLI behavior: Create operation, wait for children, complete.
  Future<void> _runCliParticipant() async {
    if (_crashed || _hasError) return;

    _log('startOperation()');
    _operation = await _ledger.createOperation(
      description: 'CLI initiated operation',
      callback: OperationCallback(
        onHeartbeatSuccess: (op, result) {
          _log(
            '♥ heartbeat OK (frames: ${result.callFrameCount}, age: ${result.heartbeatAgeMs}ms)',
          );
        },
        onHeartbeatError: (op, error) {
          _log('♥ heartbeat ERROR: ${error.type} - ${error.message}');
          final failureType = _mapHeartbeatError(error.type);
          _sendResponse(
            IsolateResponseType.failureDetected,
            data: {
              'type': failureType.name,
              'participant': name,
              'message': error.message,
            },
          );
          // Complete the wait to interrupt current work
          if (!_waitCompleter.isCompleted) {
            _waitCompleter.complete();
          }
        },
      ),
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

    // Schedule configured events (failures, aborts) AFTER call starts
    _scheduleConfiguredEvents();

    // Wait for work duration or crash/error
    final workComplete = await _waitForDurationOrInterrupt(
      Duration(milliseconds: config.workDurationMs),
    );

    if (_hasError) {
      // Error occurred - end call with fail result
      await call.fail(
        Exception(_errorMessage ?? 'Unknown error'),
        StackTrace.current,
      );
      _log('call failed with error');
      _sendResponse(IsolateResponseType.error, message: _errorMessage);
    } else if (_crashed) {
      // Crash - heartbeat already stopped by _simulateCrash
      // Don't end call - let it be detected as stale
    } else if (workComplete) {
      // Normal completion - initiator uses complete()
      await call.end();
      await _operation!.complete();
      _log('operation completed');
      _sendResponse(
        IsolateResponseType.completed,
        data: {'operationId': operationId},
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Bridge Participant Behavior
  // ─────────────────────────────────────────────────────────────

  /// Bridge behavior: Join operation, wait for events, act, wait.
  /// Runs in an event-driven loop similar to VSCode.
  Future<void> _runBridgeParticipant() async {
    if (_crashed || _hasError) return;

    final operationId = config.operationId;
    if (operationId == null) {
      throw StateError('Bridge requires operationId to join');
    }

    _log('joinOperation($operationId)');
    _operation = await _ledger.joinOperation(
      operationId: operationId,
      callback: OperationCallback(
        onHeartbeatSuccess: (op, result) {
          _log(
            '♥ heartbeat OK (frames: ${result.callFrameCount}, age: ${result.heartbeatAgeMs}ms)',
          );
        },
        onHeartbeatError: (op, error) {
          _log('♥ heartbeat ERROR: ${error.type} - ${error.message}');
          final failureType = _mapHeartbeatError(error.type);
          _sendResponse(
            IsolateResponseType.failureDetected,
            data: {
              'type': failureType.name,
              'participant': name,
              'message': error.message,
            },
          );
          // Complete the wait to interrupt current work
          if (!_waitCompleter.isCompleted) {
            _waitCompleter.complete();
          }
        },
      ),
    );
    _operation!.stalenessThresholdMs = config.heartbeatTimeoutMs;

    _event('operationJoined', {'operationId': operationId});

    // Start a call for processing
    final call = await _operation!.startCall<String>(
      description: 'bridge-process',
      callback: CallCallback<String>(
        onCleanup: () async {
          _log('cleanup: bridge-process');
        },
      ),
    );

    // Schedule configured events (failures, aborts) AFTER call starts
    _scheduleConfiguredEvents();

    // Simulate work duration
    _log('processing for ${config.workDurationMs}ms...');
    final workComplete = await _waitForDurationOrInterrupt(
      Duration(milliseconds: config.workDurationMs),
    );

    if (_hasError) {
      // Error occurred - set abort flag so other participants detect failure,
      // then end call with fail result, then leave
      await _operation!.setAbortFlag(true);
      await call.fail(
        Exception(_errorMessage ?? 'Unknown error'),
        StackTrace.current,
      );
      _operation!.leave();
      _log('call failed with error');
      _sendResponse(IsolateResponseType.error, message: _errorMessage);
    } else if (_crashed) {
      // Crash - heartbeat already stopped by _simulateCrash
      // Don't end call - let it be detected as stale
    } else if (workComplete) {
      // Normal completion - participant uses leave()
      await call.end('Bridge work completed');
      _operation!.leave();
      _log('work completed');
      _sendResponse(
        IsolateResponseType.completed,
        data: {'result': 'success', 'operationId': operationId},
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Custom Participant Behavior
  // ─────────────────────────────────────────────────────────────

  /// Custom behavior: Defined by test via customParams.
  Future<void> _runCustomParticipant() async {
    final behaviorName = config.customParams['behavior'] as String?;
    _log('running custom behavior: $behaviorName');

    switch (behaviorName) {
      case 'initiator':
        await _runCliParticipant();
      case 'worker':
        await _runBridgeParticipant();
      case 'monitor':
        await _runMonitorParticipant();
      default:
        _log('unknown custom behavior: $behaviorName');
        _sendResponse(
          IsolateResponseType.error,
          message: 'Unknown behavior: $behaviorName',
        );
    }
  }

  /// Monitor-only behavior: Join, heartbeat, watch for failures.
  Future<void> _runMonitorParticipant() async {
    if (_crashed || _hasError) return;

    final operationId = config.operationId;
    if (operationId == null) {
      throw StateError('Monitor requires operationId to join');
    }

    _log('joinOperation($operationId) [monitor mode]');
    _operation = await _ledger.joinOperation(
      operationId: operationId,
      callback: OperationCallback(
        onHeartbeatSuccess: (op, result) {
          _log(
            '♥ heartbeat OK (frames: ${result.callFrameCount}, age: ${result.heartbeatAgeMs}ms)',
          );
        },
        onHeartbeatError: (op, error) {
          _log('♥ heartbeat ERROR: ${error.type} - ${error.message}');
          final failureType = _mapHeartbeatError(error.type);
          _sendResponse(
            IsolateResponseType.failureDetected,
            data: {
              'type': failureType.name,
              'participant': name,
              'message': error.message,
            },
          );
          // Complete the wait to interrupt
          if (!_waitCompleter.isCompleted) {
            _waitCompleter.complete();
          }
        },
      ),
    );
    _operation!.stalenessThresholdMs = config.heartbeatTimeoutMs;

    _event('operationJoined', {'operationId': operationId});

    // Schedule configured events (failures, aborts)
    _scheduleConfiguredEvents();

    // Wait indefinitely until shutdown or crash/error
    await _waitForDurationOrInterrupt(const Duration(hours: 1));

    // If not crashed, leave the operation
    if (!_crashed) {
      _operation!.leave();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Wait Utilities
  // ─────────────────────────────────────────────────────────────

  /// Wait for duration or until crash/error interrupts.
  /// Returns true if duration completed, false if interrupted.
  Future<bool> _waitForDurationOrInterrupt(Duration duration) async {
    final timeout = Future.delayed(duration);
    final result = await Future.any([
      timeout.then((_) => true),
      _waitCompleter.future.then((_) => false),
    ]);
    return result;
  }
}

// ─────────────────────────────────────────────────────────────
// IsolateParticipantHandle
// ─────────────────────────────────────────────────────────────

/// Handle to control a participant running in a separate isolate.
/// Behavior auto-starts on spawn - only shutdown command is available.
class IsolateParticipantHandle {
  final String name;
  final IsolateType isolateType;
  final Isolate isolate;
  final SendPort sendPort;
  final Stream<IsolateResponse> responses;
  final StreamController<IsolateResponse> _responseController;

  String? _operationId;
  String? get operationId => _operationId;

  bool _isCrashed = false;
  bool get isCrashed => _isCrashed;

  final Completer<FailureDetection> _failureDetected =
      Completer<FailureDetection>();
  Future<FailureDetection> get onFailureDetected => _failureDetected.future;

  final Completer<Map<String, dynamic>> _completed =
      Completer<Map<String, dynamic>>();
  Future<Map<String, dynamic>> get onCompleted => _completed.future;

  final Completer<String> _crashed = Completer<String>();
  Future<String> get onCrashed => _crashed.future;

  final Completer<String> _abortSet = Completer<String>();
  Future<String> get onAbortSet => _abortSet.future;

  IsolateParticipantHandle._({
    required this.name,
    required this.isolateType,
    required this.isolate,
    required this.sendPort,
    required StreamController<IsolateResponse> responseController,
  }) : _responseController = responseController,
       responses = responseController.stream.asBroadcastStream();

  /// Spawn a new participant in a separate isolate.
  /// Behavior auto-starts immediately based on configuration.
  static Future<IsolateParticipantHandle> spawn({
    required String name,
    required int pid,
    required String basePath,
    required IsolateType isolateType,
    required int heartbeatIntervalMs,
    required int heartbeatTimeoutMs,
    int workDurationMs = 1000,
    String? operationId,
    ScenarioConfig scenarioConfig = const ScenarioConfig(),
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
      scenarioConfig: scenarioConfig,
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
    );

    // Wait for started signal (behavior auto-starts)
    await responseController.stream.firstWhere(
      (r) => r.type == IsolateResponseType.started,
    );

    // Listen for events, failures, crashes, aborts, and completions
    responseController.stream.listen((response) {
      switch (response.type) {
        case IsolateResponseType.event:
          if (response.message == 'operationStarted') {
            handle._operationId = response.data?['operationId'] as String?;
          }

        case IsolateResponseType.failureDetected:
          if (!handle._failureDetected.isCompleted) {
            final data = response.data!;
            handle._failureDetected.complete(
              FailureDetection(
                type: DetectedFailureType.values.byName(data['type'] as String),
                participant: data['participant'] as String,
                message: data['message'] as String,
              ),
            );
          }

        case IsolateResponseType.completed:
          if (!handle._completed.isCompleted) {
            handle._completed.complete(response.data ?? {});
          }

        case IsolateResponseType.crashed:
          handle._isCrashed = true;
          if (!handle._crashed.isCompleted) {
            handle._crashed.complete(response.message ?? 'crashed');
          }

        case IsolateResponseType.abortSet:
          if (!handle._abortSet.isCompleted) {
            handle._abortSet.complete(response.message ?? 'abort set');
          }

        case IsolateResponseType.error:
          // Error from this participant - report as failure detection
          if (!handle._failureDetected.isCompleted) {
            handle._failureDetected.complete(
              FailureDetection(
                type: DetectedFailureType.heartbeatError,
                participant: handle.name,
                message: 'Error: ${response.message ?? 'unknown error'}',
              ),
            );
          }

        default:
          break;
      }
    });

    return handle;
  }

  void _send(IsolateCommand command, [Map<String, dynamic> params = const {}]) {
    sendPort.send(IsolateMessage(command, params));
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
/// All behavior is config-driven - isolates auto-start on spawn.
class IsolateScenarioRunner {
  final String ledgerPath;
  final void Function(String)? onLog;

  final List<String> _logOutput = [];
  final Map<String, IsolateParticipantHandle> _participants = {};

  IsolateScenarioRunner({required this.ledgerPath, this.onLog});

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

  /// Run a happy path scenario - no crashes or errors.
  Future<ConcurrentScenarioResult> runHappyPath({
    int processingMs = 1000,
    int heartbeatIntervalMs = 500,
    int heartbeatTimeoutMs = 1500,
  }) async {
    _logOutput.clear();
    _participants.clear();

    final stopwatch = Stopwatch()..start();
    final events = <ScenarioEvent>[];

    try {
      _log(
        '════════════════════════════════════════════════════════════════════',
      );
      _log('Happy Path Scenario (Isolate-based)');
      _log(
        '════════════════════════════════════════════════════════════════════',
      );
      _log('');

      // Spawn CLI (initiator) - auto-starts
      events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'CLI starts'));
      _participants['CLI'] = await IsolateParticipantHandle.spawn(
        name: 'CLI',
        pid: 1001,
        basePath: ledgerPath,
        isolateType: IsolateType.cli,
        heartbeatIntervalMs: heartbeatIntervalMs,
        heartbeatTimeoutMs: heartbeatTimeoutMs,
        workDurationMs: processingMs * 3, // CLI waits longer for children
        onLog: _log,
      );

      final cli = _participants['CLI']!;

      // Wait for CLI to create operation
      await cli.responses
          .firstWhere(
            (r) =>
                r.type == IsolateResponseType.event &&
                r.message == 'operationStarted',
          )
          .timeout(const Duration(seconds: 5));

      final operationId = cli.operationId!;

      // Small delay before bridge joins
      await Future.delayed(Duration(milliseconds: heartbeatIntervalMs ~/ 2));

      // Spawn Bridge (worker) - auto-starts
      events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'Bridge joins'));
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

      // Wait for Bridge to join
      await bridge.responses
          .firstWhere(
            (r) =>
                r.type == IsolateResponseType.event &&
                r.message == 'operationJoined',
          )
          .timeout(const Duration(seconds: 5));

      // Wait for Bridge to complete
      await bridge.onCompleted.timeout(
        Duration(milliseconds: processingMs + 5000),
      );
      events.add(
        ScenarioEvent(stopwatch.elapsedMilliseconds, 'Bridge completes'),
      );

      // Wait for CLI to complete
      await cli.onCompleted.timeout(
        Duration(milliseconds: processingMs * 3 + 5000),
      );
      events.add(ScenarioEvent(stopwatch.elapsedMilliseconds, 'CLI completes'));

      _log('');
      _log('Happy path completed in ${stopwatch.elapsedMilliseconds}ms');

      stopwatch.stop();
      return ConcurrentScenarioResult(
        success: true,
        events: events,
        elapsed: stopwatch.elapsed,
        log: List.from(_logOutput),
      );
    } catch (e) {
      stopwatch.stop();
      return ConcurrentScenarioResult(
        success: false,
        errorMessage: e.toString(),
        events: events,
        elapsed: stopwatch.elapsed,
        log: List.from(_logOutput),
      );
    } finally {
      await _cleanup();
    }
  }

  /// Run a crash detection scenario.
  /// The crashing participant stops heartbeating and becomes unresponsive.
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
      _log(
        '════════════════════════════════════════════════════════════════════',
      );
      _log('Crash Detection Scenario (Isolate-based)');
      _log(
        '════════════════════════════════════════════════════════════════════',
      );
      _log('Crash target: $crashingParticipant after ${crashAfterMs}ms');
      _log(
        'Heartbeat interval: ${heartbeatIntervalMs}ms, timeout: ${heartbeatTimeoutMs}ms',
      );
      _log('');

      // Determine which participant crashes
      final cliScenarioConfig = crashingParticipant == 'CLI'
          ? ScenarioConfig.crash(afterMs: crashAfterMs)
          : const ScenarioConfig();

      final bridgeScenarioConfig = crashingParticipant == 'Bridge'
          ? ScenarioConfig.crash(afterMs: crashAfterMs)
          : const ScenarioConfig();

      // Spawn CLI (initiator) - auto-starts
      events.add(
        ScenarioEvent(stopwatch.elapsedMilliseconds, 'CLI starts operation'),
      );
      _participants['CLI'] = await IsolateParticipantHandle.spawn(
        name: 'CLI',
        pid: 1001,
        basePath: ledgerPath,
        isolateType: IsolateType.cli,
        heartbeatIntervalMs: heartbeatIntervalMs,
        heartbeatTimeoutMs: heartbeatTimeoutMs,
        workDurationMs: workDurationMs + maxWaitMs,
        scenarioConfig: cliScenarioConfig,
        onLog: _log,
      );

      final cli = _participants['CLI']!;

      // Wait for CLI to create operation
      await cli.responses
          .firstWhere(
            (r) =>
                r.type == IsolateResponseType.event &&
                r.message == 'operationStarted',
          )
          .timeout(const Duration(seconds: 5));

      final operationId = cli.operationId!;

      // Small delay before bridge joins
      await Future.delayed(Duration(milliseconds: heartbeatIntervalMs ~/ 2));

      // Spawn Bridge - auto-starts
      events.add(
        ScenarioEvent(stopwatch.elapsedMilliseconds, 'Bridge joins operation'),
      );
      _participants['Bridge'] = await IsolateParticipantHandle.spawn(
        name: 'Bridge',
        pid: 2001,
        basePath: ledgerPath,
        isolateType: IsolateType.bridge,
        heartbeatIntervalMs: heartbeatIntervalMs,
        heartbeatTimeoutMs: heartbeatTimeoutMs,
        workDurationMs: workDurationMs + maxWaitMs,
        operationId: operationId,
        scenarioConfig: bridgeScenarioConfig,
        onLog: _log,
      );

      final bridge = _participants['Bridge']!;

      // Wait for Bridge to join
      await bridge.responses
          .firstWhere(
            (r) =>
                r.type == IsolateResponseType.event &&
                r.message == 'operationJoined',
          )
          .timeout(const Duration(seconds: 5));

      // Track when crash actually happens
      final crashFutures = _participants.values
          .where((p) => p.name == crashingParticipant)
          .map((p) => p.onCrashed)
          .toList();

      unawaited(
        Future.any(crashFutures).then((_) {
          events.add(
            ScenarioEvent(
              stopwatch.elapsedMilliseconds,
              '$crashingParticipant crashes',
            ),
          );
        }),
      );

      // Wait for failure detection from non-crashing participant
      _log('Waiting for failure detection (timeout: ${maxWaitMs}ms)...');
      final detectors = _participants.values
          .where((p) => p.name != crashingParticipant)
          .map((p) => p.onFailureDetected)
          .toList();

      try {
        final detection = await Future.any(
          detectors,
        ).timeout(Duration(milliseconds: maxWaitMs));

        events.add(
          ScenarioEvent(
            stopwatch.elapsedMilliseconds,
            '${detection.participant} detected: ${detection.type}',
          ),
        );

        _log('');
        _log('────────────────────────────────────────');
        _log('Failure Detected!');
        _log('────────────────────────────────────────');
        _log(
          '${detection.participant} detected ${detection.type}: ${detection.message}',
        );

        stopwatch.stop();
        return ConcurrentScenarioResult(
          success: true,
          detectedFailure: detection,
          events: events,
          elapsed: stopwatch.elapsed,
          log: List.from(_logOutput),
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
          log: List.from(_logOutput),
        );
      }
    } finally {
      await _cleanup();
    }
  }

  /// Run an abort scenario.
  /// Abort is scheduled via configuration - no commands sent.
  Future<ConcurrentScenarioResult> runAbortScenario({
    required int abortAfterMs,
    int heartbeatIntervalMs = 1000,
    int heartbeatTimeoutMs = 3000,
    int maxWaitMs = 10000,
  }) async {
    _logOutput.clear();
    _participants.clear();

    final stopwatch = Stopwatch()..start();
    final events = <ScenarioEvent>[];

    try {
      _log(
        '════════════════════════════════════════════════════════════════════',
      );
      _log('User Abort Scenario (Isolate-based)');
      _log(
        '════════════════════════════════════════════════════════════════════',
      );
      _log('Abort after ${abortAfterMs}ms');
      _log('');

      // CLI has abort scheduled
      final cliScenarioConfig = ScenarioConfig.abort(afterMs: abortAfterMs);

      // Spawn CLI (initiator) - auto-starts with abort scheduled
      events.add(
        ScenarioEvent(stopwatch.elapsedMilliseconds, 'CLI starts operation'),
      );
      _participants['CLI'] = await IsolateParticipantHandle.spawn(
        name: 'CLI',
        pid: 1001,
        basePath: ledgerPath,
        isolateType: IsolateType.cli,
        heartbeatIntervalMs: heartbeatIntervalMs,
        heartbeatTimeoutMs: heartbeatTimeoutMs,
        workDurationMs: maxWaitMs * 2,
        scenarioConfig: cliScenarioConfig,
        onLog: _log,
      );

      final cli = _participants['CLI']!;

      // Wait for CLI to create operation
      await cli.responses
          .firstWhere(
            (r) =>
                r.type == IsolateResponseType.event &&
                r.message == 'operationStarted',
          )
          .timeout(const Duration(seconds: 5));

      final operationId = cli.operationId!;

      // Small delay before bridge joins
      await Future.delayed(Duration(milliseconds: heartbeatIntervalMs ~/ 2));

      // Spawn Bridge - auto-starts
      events.add(
        ScenarioEvent(stopwatch.elapsedMilliseconds, 'Bridge joins operation'),
      );
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

      await bridge.responses
          .firstWhere(
            (r) =>
                r.type == IsolateResponseType.event &&
                r.message == 'operationJoined',
          )
          .timeout(const Duration(seconds: 5));

      // Track when abort is set
      unawaited(
        cli.onAbortSet.then((_) {
          events.add(
            ScenarioEvent(stopwatch.elapsedMilliseconds, 'USER ABORT (Ctrl+C)'),
          );
          _log('');
          _log('>>> USER ABORT (Ctrl+C) <<<');
          _log('');
        }),
      );

      // Wait for detection
      _log('Waiting for abort detection...');
      final detectors = _participants.values
          .map((p) => p.onFailureDetected)
          .toList();

      try {
        final detection = await Future.any(
          detectors,
        ).timeout(Duration(milliseconds: maxWaitMs));

        events.add(
          ScenarioEvent(
            stopwatch.elapsedMilliseconds,
            '${detection.participant} detected: ${detection.type}',
          ),
        );

        _log('');
        _log('────────────────────────────────────────');
        _log('Abort Detected!');
        _log('────────────────────────────────────────');
        _log(
          '${detection.participant} detected ${detection.type}: ${detection.message}',
        );

        stopwatch.stop();
        return ConcurrentScenarioResult(
          success: true,
          detectedFailure: detection,
          events: events,
          elapsed: stopwatch.elapsed,
          log: List.from(_logOutput),
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
          log: List.from(_logOutput),
        );
      }
    } finally {
      await _cleanup();
    }
  }

  /// Run an error scenario where processing fails cleanly.
  Future<ConcurrentScenarioResult> runErrorScenario({
    required String erroringParticipant,
    required int errorAfterMs,
    String errorMessage = 'Simulated processing error',
    int heartbeatIntervalMs = 1000,
    int heartbeatTimeoutMs = 3000,
    int maxWaitMs = 10000,
  }) async {
    _logOutput.clear();
    _participants.clear();

    final stopwatch = Stopwatch()..start();
    final events = <ScenarioEvent>[];

    try {
      _log(
        '════════════════════════════════════════════════════════════════════',
      );
      _log('Error Scenario (Isolate-based)');
      _log(
        '════════════════════════════════════════════════════════════════════',
      );
      _log('Error in: $erroringParticipant after ${errorAfterMs}ms');
      _log('');

      // Determine which participant errors
      final cliScenarioConfig = erroringParticipant == 'CLI'
          ? ScenarioConfig.error(afterMs: errorAfterMs, message: errorMessage)
          : const ScenarioConfig();

      final bridgeScenarioConfig = erroringParticipant == 'Bridge'
          ? ScenarioConfig.error(afterMs: errorAfterMs, message: errorMessage)
          : const ScenarioConfig();

      // Spawn CLI (initiator) - auto-starts
      events.add(
        ScenarioEvent(stopwatch.elapsedMilliseconds, 'CLI starts operation'),
      );
      _participants['CLI'] = await IsolateParticipantHandle.spawn(
        name: 'CLI',
        pid: 1001,
        basePath: ledgerPath,
        isolateType: IsolateType.cli,
        heartbeatIntervalMs: heartbeatIntervalMs,
        heartbeatTimeoutMs: heartbeatTimeoutMs,
        workDurationMs: maxWaitMs * 2,
        scenarioConfig: cliScenarioConfig,
        onLog: _log,
      );

      final cli = _participants['CLI']!;

      // Wait for CLI to create operation
      await cli.responses
          .firstWhere(
            (r) =>
                r.type == IsolateResponseType.event &&
                r.message == 'operationStarted',
          )
          .timeout(const Duration(seconds: 5));

      final operationId = cli.operationId!;

      // Small delay before bridge joins
      await Future.delayed(Duration(milliseconds: heartbeatIntervalMs ~/ 2));

      // Spawn Bridge - auto-starts
      events.add(
        ScenarioEvent(stopwatch.elapsedMilliseconds, 'Bridge joins operation'),
      );
      _participants['Bridge'] = await IsolateParticipantHandle.spawn(
        name: 'Bridge',
        pid: 2001,
        basePath: ledgerPath,
        isolateType: IsolateType.bridge,
        heartbeatIntervalMs: heartbeatIntervalMs,
        heartbeatTimeoutMs: heartbeatTimeoutMs,
        workDurationMs: maxWaitMs * 2,
        operationId: operationId,
        scenarioConfig: bridgeScenarioConfig,
        onLog: _log,
      );

      final bridge = _participants['Bridge']!;

      await bridge.responses
          .firstWhere(
            (r) =>
                r.type == IsolateResponseType.event &&
                r.message == 'operationJoined',
          )
          .timeout(const Duration(seconds: 5));

      // Wait for error detection
      _log('Waiting for error detection...');
      final detectors = _participants.values
          .map((p) => p.onFailureDetected)
          .toList();

      try {
        final detection = await Future.any(
          detectors,
        ).timeout(Duration(milliseconds: maxWaitMs));

        events.add(
          ScenarioEvent(
            stopwatch.elapsedMilliseconds,
            '${detection.participant} detected: ${detection.type}',
          ),
        );

        _log('');
        _log('────────────────────────────────────────');
        _log('Error Detected!');
        _log('────────────────────────────────────────');
        _log(
          '${detection.participant} detected ${detection.type}: ${detection.message}',
        );

        stopwatch.stop();
        return ConcurrentScenarioResult(
          success: true,
          detectedFailure: detection,
          events: events,
          elapsed: stopwatch.elapsed,
          log: List.from(_logOutput),
        );
      } on TimeoutException {
        events.add(
          ScenarioEvent(
            stopwatch.elapsedMilliseconds,
            'TIMEOUT: No error detected',
          ),
        );
        stopwatch.stop();
        return ConcurrentScenarioResult(
          success: false,
          errorMessage: 'Timeout: No error detected within ${maxWaitMs}ms',
          events: events,
          elapsed: stopwatch.elapsed,
          log: List.from(_logOutput),
        );
      }
    } finally {
      await _cleanup();
    }
  }

  /// Run a complex multi-participant chain scenario.
  ///
  /// Chain: CLI -> Bridge -> VSBridge (with optional VSCode callback to Bridge)
  ///
  /// Each participant joins after the previous one is ready.
  /// Failure can occur at any step in the chain.
  Future<ConcurrentScenarioResult> runChainScenario({
    required String failingParticipant,
    required SimulatedFailure failureType,
    required int failAfterMs,
    String? errorMessage,
    int heartbeatIntervalMs = 500,
    int heartbeatTimeoutMs = 1500,
    int workDurationMs = 3000,
    int maxWaitMs = 15000,
    bool includeVSCodeCallback = false,
  }) async {
    _logOutput.clear();
    _participants.clear();

    final stopwatch = Stopwatch()..start();
    final events = <ScenarioEvent>[];

    try {
      _log(
        '════════════════════════════════════════════════════════════════════',
      );
      _log('Chain Scenario (Isolate-based)');
      _log(
        '════════════════════════════════════════════════════════════════════',
      );
      _log(
        'Chain: CLI -> Bridge -> VSBridge${includeVSCodeCallback ? ' -> VSCode callback' : ''}',
      );
      _log(
        'Failure: $failureType in $failingParticipant after ${failAfterMs}ms',
      );
      _log('');

      // Create scenario configs for each participant
      ScenarioConfig configFor(String name) {
        if (name != failingParticipant) return const ScenarioConfig();
        return switch (failureType) {
          SimulatedFailure.none => const ScenarioConfig(),
          SimulatedFailure.crash => ScenarioConfig.crash(afterMs: failAfterMs),
          SimulatedFailure.error => ScenarioConfig.error(
            afterMs: failAfterMs,
            message: errorMessage,
          ),
        };
      }

      // 1. Spawn CLI (initiator)
      events.add(
        ScenarioEvent(stopwatch.elapsedMilliseconds, 'CLI starts operation'),
      );
      _participants['CLI'] = await IsolateParticipantHandle.spawn(
        name: 'CLI',
        pid: 1001,
        basePath: ledgerPath,
        isolateType: IsolateType.cli,
        heartbeatIntervalMs: heartbeatIntervalMs,
        heartbeatTimeoutMs: heartbeatTimeoutMs,
        workDurationMs: workDurationMs + maxWaitMs,
        scenarioConfig: configFor('CLI'),
        onLog: _log,
      );

      final cli = _participants['CLI']!;

      // Wait for CLI to create operation
      await cli.responses
          .firstWhere(
            (r) =>
                r.type == IsolateResponseType.event &&
                r.message == 'operationStarted',
          )
          .timeout(const Duration(seconds: 5));

      final operationId = cli.operationId!;
      events.add(
        ScenarioEvent(
          stopwatch.elapsedMilliseconds,
          'Operation created: $operationId',
        ),
      );

      // Small delay before Bridge joins
      await Future.delayed(Duration(milliseconds: heartbeatIntervalMs ~/ 2));

      // 2. Spawn Bridge (first worker)
      events.add(
        ScenarioEvent(stopwatch.elapsedMilliseconds, 'Bridge joins operation'),
      );
      _participants['Bridge'] = await IsolateParticipantHandle.spawn(
        name: 'Bridge',
        pid: 2001,
        basePath: ledgerPath,
        isolateType: IsolateType.bridge,
        heartbeatIntervalMs: heartbeatIntervalMs,
        heartbeatTimeoutMs: heartbeatTimeoutMs,
        workDurationMs: workDurationMs + maxWaitMs,
        operationId: operationId,
        scenarioConfig: configFor('Bridge'),
        onLog: _log,
      );

      final bridge = _participants['Bridge']!;

      await bridge.responses
          .firstWhere(
            (r) =>
                r.type == IsolateResponseType.event &&
                r.message == 'operationJoined',
          )
          .timeout(const Duration(seconds: 5));

      // Small delay before VSBridge joins
      await Future.delayed(Duration(milliseconds: heartbeatIntervalMs ~/ 2));

      // 3. Spawn VSBridge (second worker - simulates VS Code extension bridge)
      events.add(
        ScenarioEvent(
          stopwatch.elapsedMilliseconds,
          'VSBridge joins operation',
        ),
      );
      _participants['VSBridge'] = await IsolateParticipantHandle.spawn(
        name: 'VSBridge',
        pid: 3001,
        basePath: ledgerPath,
        isolateType: IsolateType.bridge,
        heartbeatIntervalMs: heartbeatIntervalMs,
        heartbeatTimeoutMs: heartbeatTimeoutMs,
        workDurationMs: workDurationMs + maxWaitMs,
        operationId: operationId,
        scenarioConfig: configFor('VSBridge'),
        onLog: _log,
      );

      final vsbridge = _participants['VSBridge']!;

      await vsbridge.responses
          .firstWhere(
            (r) =>
                r.type == IsolateResponseType.event &&
                r.message == 'operationJoined',
          )
          .timeout(const Duration(seconds: 5));

      // 4. Optional: Spawn VSCode callback participant
      if (includeVSCodeCallback) {
        await Future.delayed(Duration(milliseconds: heartbeatIntervalMs ~/ 2));

        events.add(
          ScenarioEvent(stopwatch.elapsedMilliseconds, 'VSCode callback joins'),
        );
        _participants['VSCode'] = await IsolateParticipantHandle.spawn(
          name: 'VSCode',
          pid: 4001,
          basePath: ledgerPath,
          isolateType: IsolateType.bridge,
          heartbeatIntervalMs: heartbeatIntervalMs,
          heartbeatTimeoutMs: heartbeatTimeoutMs,
          workDurationMs: workDurationMs + maxWaitMs,
          operationId: operationId,
          scenarioConfig: configFor('VSCode'),
          onLog: _log,
        );

        final vscode = _participants['VSCode']!;

        await vscode.responses
            .firstWhere(
              (r) =>
                  r.type == IsolateResponseType.event &&
                  r.message == 'operationJoined',
            )
            .timeout(const Duration(seconds: 5));
      }

      // Track crashes
      for (final p in _participants.values) {
        unawaited(
          p.onCrashed.then((_) {
            events.add(
              ScenarioEvent(stopwatch.elapsedMilliseconds, '${p.name} crashes'),
            );
          }),
        );
      }

      // Wait for failure detection
      _log('Waiting for failure detection (timeout: ${maxWaitMs}ms)...');
      final detectors = _participants.values
          .map((p) => p.onFailureDetected)
          .toList();

      try {
        final detection = await Future.any(
          detectors,
        ).timeout(Duration(milliseconds: maxWaitMs));

        events.add(
          ScenarioEvent(
            stopwatch.elapsedMilliseconds,
            '${detection.participant} detected: ${detection.type}',
          ),
        );

        _log('');
        _log('────────────────────────────────────────');
        _log('Failure Detected!');
        _log('────────────────────────────────────────');
        _log(
          '${detection.participant} detected ${detection.type}: ${detection.message}',
        );

        stopwatch.stop();
        return ConcurrentScenarioResult(
          success: true,
          detectedFailure: detection,
          events: events,
          elapsed: stopwatch.elapsed,
          log: List.from(_logOutput),
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
          log: List.from(_logOutput),
        );
      }
    } finally {
      await _cleanup();
    }
  }
}
