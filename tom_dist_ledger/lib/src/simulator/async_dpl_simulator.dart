import 'dart:async';
import 'dart:io';

import 'async_simulation.dart';
import 'participants/async_sim_copilot_chat.dart';
import 'participants/async_sim_dartscript_bridge.dart';
import 'participants/async_sim_tom_cli.dart';
import 'participants/async_sim_vscode_extension.dart';
import 'simulation_config.dart';

/// Async DPL Simulator - uses the Ledger API.
///
/// Each participant has its own Ledger instance with its own participantId.
class AsyncDPLSimulator {
  final SimulationConfig config;
  late final AsyncSimulationPrinter printer;

  late final AsyncSimTomCLI cli;
  late final AsyncSimDartScriptBridge bridge;
  late final AsyncSimVSCodeExtension vscode;
  late final AsyncSimCopilotChat copilotChat;

  String? _currentOperationId;

  void Function(String)? _onBackupCreated(String participantName) {
    return (path) {
      final relativePath = path.replaceFirst('${config.ledgerPath}/', '');
      print(
        '${printer.elapsedFormatted} | [$participantName] backup → $relativePath',
      );
    };
  }

  AsyncDPLSimulator({required this.config}) {
    printer = AsyncSimulationPrinter();
    cli = AsyncSimTomCLI(
      basePath: config.ledgerPath,
      printer: printer,
      config: config,
      onBackupCreated: _onBackupCreated('CLI'),
    );
    bridge = AsyncSimDartScriptBridge(
      basePath: config.ledgerPath,
      printer: printer,
      config: config,
      onBackupCreated: _onBackupCreated('Bridge'),
    );
    vscode = AsyncSimVSCodeExtension(
      basePath: config.ledgerPath,
      printer: printer,
      config: config,
      onBackupCreated: _onBackupCreated('VSCode'),
    );
    copilotChat = AsyncSimCopilotChat(
      basePath: config.ledgerPath,
      printer: printer,
      config: config,
      onBackupCreated: _onBackupCreated('Copilot'),
    );
  }

  /// Get the current operation ID.
  String? get currentOperationId => _currentOperationId;

  /// Helper to add configurable delay between calls.
  Future<void> _callDelay() async {
    await Future.delayed(Duration(milliseconds: config.callDelayMs));
  }

  /// Save the log output to a file.
  Future<void> saveLog() async {
    if (_currentOperationId == null) return;

    final logPath = '${config.ledgerPath}/${_currentOperationId}_log.txt';
    final logFile = File(logPath);
    await logFile.writeAsString(printer.output.join('\n'));
    print('\nLog saved to: $logPath');
  }

  /// Run the normal flow simulation.
  Future<void> runNormalFlow() async {
    printer.printHeader('Normal Flow - File Operation with DPL (Ledger API)');

    try {
      // Phase 1: CLI initiates operation (operation ID is auto-generated)
      await _cliInitiatesPhase(_currentOperationId ?? '');

      // Phase 2: Bridge receives request and starts work
      await _bridgeProcessesPhase();

      // Phase 3: VSCode extension calls Copilot
      await _vscodeCallsCopilotPhase();

      // Phase 4: Response bubbles up
      await _responseReturnsPhase();

      // Phase 5: CLI completes
      await _cliCompletesPhase();

      printer.printPhaseComplete('SUCCESS', 'Normal flow completed');

      // Save the log
      await saveLog();
    } catch (e) {
      printer.printPhaseComplete('ERROR', 'Normal flow failed: $e');
      await saveLog();
      rethrow;
    }
  }

  /// Run the abort flow simulation (user presses Ctrl-C).
  Future<void> runAbortFlow() async {
    printer.printHeader('Abort Flow - Ctrl-C During Operation (Ledger API)');

    try {
      // Phase 1: CLI initiates operation (operation ID is auto-generated)
      await _cliInitiatesPhase(_currentOperationId ?? '');

      // Phase 2: Bridge starts processing
      await _bridgeProcessesPhase();

      // Phase 3: VSCode calls Copilot - but we'll abort during this
      await _vscodeCallsCopilotWithAbortPhase();

      printer.printPhaseComplete(
        'SUCCESS',
        'Abort flow completed - cleanup done',
      );

      // Save the log
      await saveLog();
    } catch (e) {
      printer.printPhaseComplete('ERROR', 'Abort flow failed: $e');
      await saveLog();
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Phase implementations
  // ─────────────────────────────────────────────────────────────

  Future<void> _cliInitiatesPhase(String operationId) async {
    printer.printPhase('Phase 1: CLI Initiates Operation');

    final operation = await cli.startOperation(depth: 1);
    _currentOperationId = operation.operationId;
    await _callDelay();
    await cli.createCallFrame(depth: 1, callId: 'cli-invoke-1');
    cli.startHeartbeat(depth: 1);

    // Simulate CLI doing some work before calling bridge
    await _callDelay();
  }

  Future<void> _bridgeProcessesPhase() async {
    printer.printPhase('Phase 2: Bridge Receives Request');

    await bridge.joinOperation(depth: 2, operationId: _currentOperationId!);
    await bridge.createCallFrame(depth: 2, callId: 'bridge-handle-1');
    bridge.startHeartbeat(depth: 2);
    await _callDelay();

    // Create temp file
    await bridge.registerTempResource(depth: 2, path: '/tmp/dpl_work.tmp');

    // Simulate bridge processing
    await _callDelay();
  }

  Future<void> _vscodeCallsCopilotPhase() async {
    printer.printPhase('Phase 3: VSCode Extension Calls Copilot');

    await vscode.joinOperation(depth: 3, operationId: _currentOperationId!);
    await vscode.createCallFrame(depth: 3, callId: 'vscode-copilot-1');
    vscode.startHeartbeat(depth: 3);
    await _callDelay();

    // Make external call (this waits for response)
    try {
      await copilotChat.invoke(
        depth: 3,
        prompt: 'Generate file content',
        callerOperation: vscode.operation,
        abortSignal: null, // No abort signal for normal flow
      );
    } on TimeoutException {
      printer.log(depth: 3, participant: 'VSCode', message: 'Copilot timeout!');
      rethrow;
    }
  }

  Future<void> _vscodeCallsCopilotWithAbortPhase() async {
    printer.printPhase('Phase 3: VSCode Extension Calls Copilot (will abort)');

    await vscode.joinOperation(depth: 3, operationId: _currentOperationId!);
    await vscode.createCallFrame(depth: 3, callId: 'vscode-copilot-1');
    vscode.startHeartbeat(depth: 3);

    // Schedule abort after one call delay period
    Timer(Duration(milliseconds: config.callDelayMs), () async {
      printer.printPhase('Phase 3a: User presses Ctrl-C');
      cli.receiveSigint(depth: 1);
      await cli.setAbortFlag(depth: 1, value: true);
    });

    // Create a completer that the abort can signal
    final abortCompleter = Completer<void>();

    // Listen for abort on CLI operation
    cli.onAbort.then((_) {
      if (!abortCompleter.isCompleted) {
        abortCompleter.complete();
      }
    });

    // Make external call (this will be interrupted by abort)
    try {
      await copilotChat.invoke(
        depth: 3,
        prompt: 'Generate file content',
        callerOperation: vscode.operation,
        abortSignal: abortCompleter,
      );
    } on AbortedException {
      printer.log(
        depth: 3,
        participant: 'VSCode',
        message: 'Caught AbortedException',
      );
      await _handleAbortCleanup();
    }
  }

  Future<void> _handleAbortCleanup() async {
    printer.printPhase('Phase 4: Abort Cleanup');

    // VSCode detects abort and starts unwinding
    vscode.stopHeartbeat(depth: 3);
    vscode.cancelChatPolling(depth: 3);
    await vscode.deleteCallFrame(depth: 3, callId: 'vscode-copilot-1');
    await _callDelay();

    // Bridge cleans up temp resources
    await bridge.cleanupTempResources(depth: 2);
    bridge.stopHeartbeat(depth: 2);
    await bridge.deleteCallFrame(depth: 2, callId: 'bridge-handle-1');
    await _callDelay();

    // CLI finishes cleanup
    cli.stopHeartbeat(depth: 1);
    await cli.deleteCallFrame(depth: 1, callId: 'cli-invoke-1');
    await cli.completeOperation(depth: 1);
    cli.exit(depth: 1, code: 130); // 128 + SIGINT
  }

  Future<void> _responseReturnsPhase() async {
    printer.printPhase('Phase 4: Response Returns Up Stack');

    // VSCode processes response
    await vscode.applyEdits(depth: 3);
    vscode.stopHeartbeat(depth: 3);
    await vscode.deleteCallFrame(depth: 3, callId: 'vscode-copilot-1');
    await _callDelay();

    // Bridge finishes
    await bridge.unregisterTempResource(depth: 2, path: '/tmp/dpl_work.tmp');
    bridge.stopHeartbeat(depth: 2);
    await bridge.deleteCallFrame(depth: 2, callId: 'bridge-handle-1');
    await _callDelay();
  }

  Future<void> _cliCompletesPhase() async {
    printer.printPhase('Phase 5: CLI Completes');

    cli.stopHeartbeat(depth: 1);
    await cli.deleteCallFrame(depth: 1, callId: 'cli-invoke-1');
    await cli.completeOperation(depth: 1);
    cli.exit(depth: 1, code: 0);
  }

  /// Clean up ledger directory.
  Future<void> cleanup() async {
    final dir = Directory(config.ledgerPath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Dispose of all participant ledgers.
  void dispose() {
    cli.ledger.dispose();
    bridge.ledger.dispose();
    vscode.ledger.dispose();
    copilotChat.ledger.dispose();
  }
}
