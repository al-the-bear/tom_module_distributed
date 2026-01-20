import 'dart:async';
import 'dart:io';

import '../async_simulation.dart';
import '../../ledger_api/ledger_api.dart';
import '../simulation_config.dart';

/// Async simulated Copilot Chat (external) using Ledger API.
/// 
/// Copilot runs as its own process:
/// 1. Receives request, starts processing
/// 2. Outputs "... Copilot is processing" every 2 seconds
/// 3. Writes response to a response file when done
/// 4. Caller polls for the response file
class AsyncSimCopilotChat {
  final Ledger ledger;
  final AsyncSimulationPrinter printer;
  final SimulationConfig config;

  Timer? _processingTimer;
  bool _isProcessing = false;

  AsyncSimCopilotChat({
    required this.ledger,
    required this.printer,
    required this.config,
  });

  /// Get the response file path for an operation.
  String _responseFilePath(String operationId) =>
      '${config.ledgerPath}/${operationId}_copilot_response.txt';

  /// Start the processing output timer.
  void _startProcessingOutput(int depth) {
    _isProcessing = true;
    _processingTimer = Timer.periodic(
      Duration(milliseconds: config.copilotProcessingIntervalMs),
      (_) {
        if (_isProcessing) {
          printer.log(
            depth: depth,
            participant: 'Copilot',
            message: '... Copilot is processing',
          );
        }
      },
    );
  }

  /// Stop the processing output timer.
  void _stopProcessingOutput() {
    _isProcessing = false;
    _processingTimer?.cancel();
    _processingTimer = null;
  }

  /// Simulate Copilot processing (runs in background).
  /// Writes response file when done.
  Future<void> _processRequest({
    required int depth,
    required String operationId,
    required String prompt,
  }) async {
    // Wait for processing time
    await Future.delayed(
      Duration(milliseconds: config.externalCallResponseMs),
    );

    // Write response file
    final responseFile = File(_responseFilePath(operationId));
    await responseFile.writeAsString(
      'Mock response from Copilot Chat\n'
      'Prompt: $prompt\n'
      'Timestamp: ${DateTime.now().toIso8601String()}\n',
    );

    printer.log(
      depth: depth,
      participant: 'Copilot',
      message: '✓ Response file written',
    );
  }

  /// Invoke the chat (external call).
  /// Copilot runs asynchronously, caller polls for response.
  Future<String> invoke({
    required int depth,
    required String prompt,
    required Operation callerOperation,
    required Completer<void>? abortSignal,
  }) async {
    printer.log(
      depth: depth,
      participant: 'VSCode',
      message:
          '→ [CopilotChat] invoke (EXTERNAL, timeout: ${config.externalCallTimeoutMs ~/ 1000}s)',
    );

    final operationId = callerOperation.operationId;

    if (config.externalCallFails) {
      // Simulate timeout
      await Future.delayed(
        Duration(milliseconds: config.externalCallTimeoutMs),
      );
      throw TimeoutException(
        'Copilot Chat timed out',
        Duration(milliseconds: config.externalCallTimeoutMs),
      );
    }

    // Start the processing output timer
    _startProcessingOutput(depth);

    // Start Copilot processing in background (will write response file)
    final processingFuture = _processRequest(
      depth: depth,
      operationId: operationId,
      prompt: prompt,
    );

    try {
      // Poll for response file
      final responseFile = File(_responseFilePath(operationId));
      final timeout = Duration(milliseconds: config.externalCallTimeoutMs);
      final startTime = DateTime.now();
      var pollCount = 0;

      while (!responseFile.existsSync()) {
        pollCount++;

        // Check for abort signal
        if (abortSignal != null && abortSignal.isCompleted) {
          throw AbortedException(operationId);
        }

        // Check abort flag via operation
        if (await callerOperation.checkAbort()) {
          throw AbortedException(operationId);
        }

        // Check timeout
        if (DateTime.now().difference(startTime) > timeout) {
          throw TimeoutException(
            'Copilot Chat timed out waiting for response file',
            timeout,
          );
        }

        // Log polling
        printer.log(
          depth: depth,
          participant: 'VSCode',
          message: '[Poll #$pollCount] Checking for Copilot response...',
        );

        // Wait before next poll
        await Future.delayed(
          Duration(milliseconds: config.copilotPollingIntervalMs),
        );
      }

      // Wait for processing to complete (should already be done)
      await processingFuture;

      // Read the response
      final response = await responseFile.readAsString();

      printer.log(
        depth: depth,
        participant: 'VSCode',
        message: '← [CopilotChat] response received (poll #$pollCount)',
      );

      // Clean up response file
      await responseFile.delete();

      return response;
    } finally {
      // Always stop the processing output
      _stopProcessingOutput();
    }
  }
}
