import 'dart:async';

import 'async_simulation.dart';
import '../ledger_api/ledger_api.dart';
import 'simulation_config.dart';

export 'async_simulation.dart' show AbortedException;

/// Defines when a failure should occur in the simulation.
enum FailurePhase {
  /// Failure during operation initialization.
  initialization,

  /// Failure during call processing (after operation started).
  processing,

  /// Failure during response return phase.
  responseReturn,

  /// Failure during completion phase.
  completion,
}

/// Defines which participant should fail.
enum FailingParticipant {
  cli,
  bridge,
  vscode,
  copilot,
}

/// Defines the type of failure.
enum FailureType {
  /// Process dies unexpectedly (no cleanup).
  crash,

  /// Process hangs indefinitely.
  hang,

  /// Process times out waiting for response.
  timeout,

  /// Process encounters an error and throws.
  error,

  /// Process detects stale heartbeat from another participant.
  staleHeartbeat,

  /// User triggers abort (Ctrl+C).
  userAbort,
}

/// Describes a single failure injection point.
class FailureInjection {
  final FailingParticipant participant;
  final FailureType type;
  final FailurePhase phase;
  final String? callId;
  final int? delayMs;
  final String? errorMessage;

  const FailureInjection({
    required this.participant,
    required this.type,
    required this.phase,
    this.callId,
    this.delayMs,
    this.errorMessage,
  });

  @override
  String toString() =>
      'FailureInjection($participant.$type at $phase${callId != null ? ", call=$callId" : ""})';
}

/// Describes a simulated call in the scenario.
class ScenarioCall {
  /// Unique identifier for the call.
  final String callId;

  /// The participant making the call.
  final FailingParticipant caller;

  /// The participant receiving the call.
  final FailingParticipant? callee;

  /// Whether this call spawns a subprocess.
  final bool spawnsProcess;

  /// Whether this is an external call (like to Copilot).
  final bool isExternal;

  /// Simulated processing duration in ms.
  final int processingMs;

  /// Nested calls within this call.
  final List<ScenarioCall> nestedCalls;

  const ScenarioCall({
    required this.callId,
    required this.caller,
    this.callee,
    this.spawnsProcess = false,
    this.isExternal = false,
    this.processingMs = 100,
    this.nestedCalls = const [],
  });
}

/// Defines a complete simulation scenario.
class SimulationScenario {
  /// Unique name for this scenario.
  final String name;

  /// Human-readable description.
  final String description;

  /// Expected outcome of the scenario.
  final String expectedOutcome;

  /// The call tree for this scenario.
  final List<ScenarioCall> callTree;

  /// Failure injections for error scenarios.
  final List<FailureInjection> failures;

  /// Simulation timing configuration.
  final SimulationConfig config;

  /// Whether this scenario should succeed (no failures).
  bool get isHappyPath => failures.isEmpty;

  const SimulationScenario({
    required this.name,
    required this.description,
    required this.expectedOutcome,
    required this.callTree,
    this.failures = const [],
    this.config = const SimulationConfig(
      callDelayMs: 50,
      externalCallResponseMs: 200,
      copilotProcessingIntervalMs: 50,
      copilotPollingIntervalMs: 50,
    ),
  });

  /// Create a simple happy path scenario.
  static SimulationScenario happyPath({
    String name = 'happy_path',
    String description = 'All participants complete successfully',
  }) {
    return SimulationScenario(
      name: name,
      description: description,
      expectedOutcome: 'Operation completes with exit code 0',
      callTree: const [
        ScenarioCall(
          callId: 'cli-main',
          caller: FailingParticipant.cli,
          nestedCalls: [
            ScenarioCall(
              callId: 'bridge-process',
              caller: FailingParticipant.bridge,
              spawnsProcess: true,
              nestedCalls: [
                ScenarioCall(
                  callId: 'vscode-copilot',
                  caller: FailingParticipant.vscode,
                  callee: FailingParticipant.copilot,
                  isExternal: true,
                  processingMs: 200,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Result of running a simulation scenario.
class ScenarioResult {
  final String scenarioName;
  final bool success;
  final String? errorMessage;
  final Duration elapsed;
  final List<String> log;
  final int? exitCode;

  const ScenarioResult({
    required this.scenarioName,
    required this.success,
    this.errorMessage,
    required this.elapsed,
    required this.log,
    this.exitCode,
  });

  @override
  String toString() {
    final status = success ? 'PASS' : 'FAIL';
    final error = errorMessage != null ? ' ($errorMessage)' : '';
    return '[$status] $scenarioName (${elapsed.inMilliseconds}ms)$error';
  }
}

/// Runs simulation scenarios with configurable participants.
class ScenarioRunner {
  final String ledgerPath;
  final void Function(String)? onLog;

  late AsyncSimulationPrinter _printer;
  final Map<FailingParticipant, _SimulatedParticipant> _participants = {};

  Completer<void>? _abortCompleter;
  Completer<_CrashException>? _crashCompleter;
  Timer? _crashTimer;
  bool _isAborted = false;
  bool _isCrashed = false;
  _CrashException? _crashException;
  
  /// The current operation ID (set by initiator).
  String? _currentOperationId;

  ScenarioRunner({
    required this.ledgerPath,
    this.onLog,
  });

  /// Initialize the runner for a scenario.
  void _initialize(SimulationScenario scenario) {
    _printer = AsyncSimulationPrinter(onLog: onLog);
    // Note: _ledger is no longer used - each participant creates its own ledger

    _participants.clear();
    _abortCompleter = Completer<void>();
    _crashCompleter = Completer<_CrashException>();
    _crashTimer?.cancel();
    _crashTimer = null;
    _isAborted = false;
    _isCrashed = false;
    _crashException = null;

    void Function(String) _onBackupCreated(String participantName) {
      return (path) {
        final relativePath = path.replaceFirst('$ledgerPath/', '');
        _printer.log(
          depth: 0,
          participant: participantName,
          message: 'backup → $relativePath',
        );
      };
    }

    // Create participants - each with their own Ledger
    _participants[FailingParticipant.cli] = _SimulatedParticipant(
      name: 'CLI',
      pid: 1001,
      basePath: ledgerPath,
      printer: _printer,
      isInitiator: true,
      onBackupCreated: _onBackupCreated('CLI'),
    );
    _participants[FailingParticipant.bridge] = _SimulatedParticipant(
      name: 'Bridge',
      pid: 2001,
      basePath: ledgerPath,
      printer: _printer,
      onBackupCreated: _onBackupCreated('Bridge'),
    );
    _participants[FailingParticipant.vscode] = _SimulatedParticipant(
      name: 'VSCode',
      pid: 3001,
      basePath: ledgerPath,
      printer: _printer,
      onBackupCreated: _onBackupCreated('VSCode'),
    );
    _participants[FailingParticipant.copilot] = _SimulatedParticipant(
      name: 'Copilot',
      pid: 4001,
      basePath: ledgerPath,
      printer: _printer,
      onBackupCreated: _onBackupCreated('Copilot'),
    );
  }

  /// Run a scenario and return the result.
  Future<ScenarioResult> run(SimulationScenario scenario) async {
    _initialize(scenario);
    final stopwatch = Stopwatch()..start();

    try {
      _printer.printHeader('Scenario: ${scenario.name}');
      _printer.log(
        depth: 0,
        participant: 'Runner',
        message: scenario.description,
      );

      // Schedule failure injections
      for (final failure in scenario.failures) {
        _scheduleFailure(failure, scenario.config);
      }

      // Execute the call tree (operationId will be set by initiator)
      _currentOperationId = null;
      await _executeCallTree(
        calls: scenario.callTree,
        depth: 1,
        config: scenario.config,
      );

      stopwatch.stop();

      return ScenarioResult(
        scenarioName: scenario.name,
        success: true,
        elapsed: stopwatch.elapsed,
        log: _printer.output,
        exitCode: 0,
      );
    } on AbortedException catch (e) {
      stopwatch.stop();
      return ScenarioResult(
        scenarioName: scenario.name,
        success: true, // Abort is expected in abort scenarios
        errorMessage: 'Aborted: ${e.operationId}',
        elapsed: stopwatch.elapsed,
        log: _printer.output,
        exitCode: 130,
      );
    } on _CrashException catch (e) {
      stopwatch.stop();
      return ScenarioResult(
        scenarioName: scenario.name,
        success: false,
        errorMessage: 'Crash: ${e.participant} at ${e.message}',
        elapsed: stopwatch.elapsed,
        log: _printer.output,
        exitCode: 1,
      );
    } on _HangException catch (e) {
      stopwatch.stop();
      return ScenarioResult(
        scenarioName: scenario.name,
        success: false,
        errorMessage: 'Hang: ${e.participant} at ${e.callId}',
        elapsed: stopwatch.elapsed,
        log: _printer.output,
        exitCode: -1,
      );
    } on TimeoutException catch (e) {
      stopwatch.stop();
      return ScenarioResult(
        scenarioName: scenario.name,
        success: false,
        errorMessage: 'Timeout: ${e.message}',
        elapsed: stopwatch.elapsed,
        log: _printer.output,
        exitCode: 124,
      );
    } catch (e) {
      stopwatch.stop();
      return ScenarioResult(
        scenarioName: scenario.name,
        success: false,
        errorMessage: e.toString(),
        elapsed: stopwatch.elapsed,
        log: _printer.output,
        exitCode: 1,
      );
    } finally {
      _crashTimer?.cancel();
      dispose();
    }
  }

  void _scheduleFailure(FailureInjection failure, SimulationConfig config) {
    final delayMs = failure.delayMs ?? config.callDelayMs * 2;

    if (failure.type == FailureType.userAbort) {
      _crashTimer = Timer(Duration(milliseconds: delayMs), () {
        _printer.logEvent(message: 'USER ABORT (Ctrl+C)');
        _isAborted = true;
        _abortCompleter?.complete();
      });
    } else if (failure.type == FailureType.crash) {
      _crashTimer = Timer(Duration(milliseconds: delayMs), () {
        final participant = _participants[failure.participant]!;
        _printer.log(
          depth: 1,
          participant: participant.name,
          message: '💥 CRASH (simulated process death)',
        );
        _isCrashed = true;
        _crashException = _CrashException(participant.name, failure.phase.name);
        if (!_crashCompleter!.isCompleted) {
          _crashCompleter!.complete(_crashException);
        }
      });
    }
  }

  /// Check if a crash has been triggered.
  void _checkCrash() {
    if (_isCrashed && _crashException != null) {
      throw _crashException!;
    }
  }

  Future<void> _executeCallTree({
    required List<ScenarioCall> calls,
    required int depth,
    required SimulationConfig config,
  }) async {
    for (final call in calls) {
      await _executeCall(
        call: call,
        depth: depth,
        config: config,
      );
    }
  }

  Future<void> _executeCall({
    required ScenarioCall call,
    required int depth,
    required SimulationConfig config,
  }) async {
    final participant = _participants[call.caller]!;

    // Check for crash or abort
    _checkCrash();
    if (_isAborted) {
      throw AbortedException(_currentOperationId ?? 'unknown');
    }

    // Start or join operation
    if (participant.isInitiator && !participant.hasOperation) {
      final operation = await participant.startOperation(depth: depth);
      _currentOperationId = operation.operationId;
    } else if (!participant.hasOperation) {
      await participant.joinOperation(operationId: _currentOperationId!, depth: depth);
    }

    // Start call execution
    await participant.pushStackFrame(callId: call.callId, depth: depth);
    participant.startHeartbeat(depth: depth);

    // Simulate processing
    await Future.delayed(Duration(milliseconds: call.processingMs));

    // Check for crash or abort
    _checkCrash();
    if (_isAborted) {
      await _cleanupOnAbort(_currentOperationId!, depth);
      throw AbortedException(_currentOperationId!);
    }

    // Execute nested calls
    if (call.nestedCalls.isNotEmpty) {
      await _executeCallTree(
        calls: call.nestedCalls,
        depth: depth + 1,
        config: config,
      );
    }

    // Handle external calls (like Copilot)
    if (call.isExternal && call.callee == FailingParticipant.copilot) {
      await _executeCopilotCall(
        call: call,
        depth: depth,
        config: config,
      );
    }

    // End call execution
    participant.stopHeartbeat(depth: depth);
    await participant.popStackFrame(callId: call.callId, depth: depth);

    // Complete operation if initiator and at top level
    if (participant.isInitiator && depth == 1) {
      await participant.completeOperation(depth: depth);
    }
  }

  Future<void> _executeCopilotCall({
    required ScenarioCall call,
    required int depth,
    required SimulationConfig config,
  }) async {
    // Copilot participant reference for future use
    // ignore: unused_local_variable
    final copilot = _participants[FailingParticipant.copilot]!;

    _printer.log(
      depth: depth,
      participant: 'VSCode',
      message: '→ [Copilot] External call',
    );

    // Simulate Copilot processing
    for (var i = 0; i < 3; i++) {
      await Future.delayed(Duration(milliseconds: config.copilotProcessingIntervalMs));
      _checkCrash();
      if (_isAborted) break;
      _printer.log(
        depth: depth + 1,
        participant: 'Copilot',
        message: '... processing',
      );
    }

    _checkCrash();
    if (_isAborted) return;

    _printer.log(
      depth: depth,
      participant: 'Copilot',
      message: '✓ Response ready',
    );
  }

  Future<void> _cleanupOnAbort(String operationId, int depth) async {
    _printer.printPhase('Abort Cleanup');

    // Stop all heartbeats and cleanup
    for (final participant in _participants.values) {
      if (participant.hasOperation) {
        participant.stopHeartbeat(depth: depth);
        _printer.log(
          depth: depth,
          participant: participant.name,
          message: 'cleanup on abort',
        );
      }
    }
  }
  
  /// Dispose all participant ledgers.
  void dispose() {
    for (final participant in _participants.values) {
      participant.dispose();
    }
  }
}

/// Internal simulated participant for scenario execution.
class _SimulatedParticipant {
  final String name;
  final int pid;
  final Ledger ledger;
  final AsyncSimulationPrinter printer;
  final bool isInitiator;

  Operation? _operation;
  Timer? _heartbeatTimer;

  _SimulatedParticipant({
    required this.name,
    required this.pid,
    required String basePath,
    required this.printer,
    this.isInitiator = false,
    void Function(String)? onBackupCreated,
  }) : ledger = Ledger(
          basePath: basePath,
          participantId: name.toLowerCase(),
          participantPid: pid,
          onBackupCreated: onBackupCreated,
        );

  bool get hasOperation => _operation != null;
  Operation get operation => _operation!;

  Future<Operation> startOperation({
    required int depth,
  }) async {
    printer.log(depth: depth, participant: name, message: 'startOperation()');
    _operation = await ledger.createOperation();
    printer.log(depth: depth, participant: name, message: '  → operationId: "${_operation!.operationId}"');
    return _operation!;
  }

  Future<void> joinOperation({
    required String operationId,
    required int depth,
  }) async {
    printer.log(depth: depth, participant: name, message: 'joinOperation($operationId)');
    _operation = await ledger.joinOperation(
      operationId: operationId,
    );
  }

  Future<void> pushStackFrame({
    required String callId,
    required int depth,
  }) async {
    printer.log(depth: depth, participant: name, message: 'pushStackFrame($callId)');
    await _operation?.pushStackFrame(callId: callId);
  }

  Future<void> popStackFrame({
    required String callId,
    required int depth,
  }) async {
    printer.log(depth: depth, participant: name, message: 'popStackFrame($callId)');
    await _operation?.popStackFrame(callId: callId);
  }

  Future<void> completeOperation({required int depth}) async {
    printer.log(depth: depth, participant: name, message: 'completeOperation()');
    await _operation?.complete();
    _operation = null;
  }

  void startHeartbeat({required int depth}) {
    printer.log(depth: depth, participant: name, message: 'startHeartbeat()');
    // Simplified heartbeat for testing
    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      // Heartbeat tick (silent in tests)
    });
  }

  void stopHeartbeat({required int depth}) {
    printer.log(depth: depth, participant: name, message: 'stopHeartbeat()');
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
  
  void dispose() {
    ledger.dispose();
  }
}

class _CrashException implements Exception {
  final String participant;
  final String message;
  _CrashException(this.participant, this.message);
}

class _HangException implements Exception {
  final String participant;
  final String callId;
  _HangException(this.participant, this.callId);
}
