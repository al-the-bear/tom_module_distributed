/// Happy Path Simulation Example
///
/// Demonstrates the complete DPL simulation with all participants:
/// - CLI (initiator)
/// - DartScript Bridge (subprocess supervisor)
/// - VS Code Extension
/// - Copilot Chat (external call)
///
/// This example shows the full multi-process coordination flow that
/// the DPL system is designed to handle.
///
/// Run with: dart run example/simulation_happy_path.dart
library;

import 'dart:io';

import 'package:tom_dist_ledger/test_simulator.dart';

void main() async {
  print('DPL Simulation - Happy Path');
  print('=' * 60);

  // Create temp directory for simulation
  final tempDir = Directory.systemTemp.createTempSync('dpl_simulation_');
  print('Ledger path: ${tempDir.path}');
  print('');

  // Create scenario runner
  final runner = ScenarioRunner(ledgerPath: tempDir.path);

  try {
    // Run the happy path scenario
    final result = await runner.run(Scenarios.happyPath);

    // Print summary
    print('');
    print('=' * 60);
    print('Simulation Result: ${result.success ? "SUCCESS" : "FAILURE"}');
    print('Exit Code: ${result.exitCode}');
    print('Duration: ${result.elapsed.inMilliseconds}ms');

    if (result.errorMessage != null) {
      print('Error: ${result.errorMessage}');
    }
  } finally {
    // Clean up
    tempDir.deleteSync(recursive: true);
  }
}
