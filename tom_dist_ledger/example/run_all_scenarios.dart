/// Run All Simulation Scenarios Example
///
/// Runs all predefined DPL simulation scenarios and prints a summary.
/// This is useful for verifying the DPL system handles all failure modes
/// correctly.
///
/// Run with: dart run example/run_all_scenarios.dart
import 'dart:io';

import 'package:tom_dist_ledger/tom_dist_ledger.dart';

void main() async {
  print('DPL Simulation - Running All Scenarios');
  print('=' * 60);
  print('');

  final results = <ScenarioResult>[];

  for (final scenario in Scenarios.all) {
    // Create fresh temp directory for each scenario
    final tempDir = Directory.systemTemp.createTempSync('dpl_scenario_');

    try {
      print('Running: ${scenario.name}');
      print('  ${scenario.description}');

      final runner = ScenarioRunner(ledgerPath: tempDir.path);
      final result = await runner.run(scenario);

      results.add(result);
      print('  Result: ${result.success ? "✓ PASS" : "✗ FAIL"}');
      print('');
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  }

  // Print summary
  print('=' * 60);
  print('Summary');
  print('=' * 60);

  final passed = results.where((r) => r.success).length;
  final failed = results.where((r) => !r.success).length;

  print('Total scenarios: ${results.length}');
  print('Passed: $passed');
  print('Failed: $failed');
  print('');

  if (failed > 0) {
    print('Failed scenarios:');
    for (final result in results.where((r) => !r.success)) {
      print('  - ${result.scenarioName}: ${result.errorMessage}');
    }
  }

  // Exit with appropriate code
  exit(failed > 0 ? 1 : 0);
}
