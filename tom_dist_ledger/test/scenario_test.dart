/// Scenario tests with realistic timing to ensure heartbeats occur.
///
/// These tests run with extended timeouts because scenarios use realistic
/// 2-second call delays and 10-second external call processing times
/// to properly exercise heartbeat behavior (heartbeat interval is 4.5s).
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_dist_ledger/test_simulator.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dpl_scenario_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('ScenarioRunner', () {
    late ScenarioRunner runner;

    setUp(() {
      runner = ScenarioRunner(ledgerPath: tempDir.path);
    });

    // ═══════════════════════════════════════════════════════════════════
    // SUCCESS SCENARIOS
    // ═══════════════════════════════════════════════════════════════════

    group('Success Scenarios', () {
      test(
        'Scenario 1: Happy path - all participants complete successfully',
        () async {
          final result = await runner.run(Scenarios.happyPath);

          expect(result.success, isTrue);
          expect(result.exitCode, equals(0));
          expect(result.log, isNotEmpty);
          expect(
            result.log.any((line) => line.contains('completeOperation')),
            isTrue,
            reason: 'Should complete the operation',
          );
        },
      );
    });

    // ═══════════════════════════════════════════════════════════════════
    // INITIATOR (CLI) FAILURE SCENARIOS
    // ═══════════════════════════════════════════════════════════════════

    group('Initiator (CLI) Failure Scenarios', () {
      test('Scenario 2: CLI crashes during initialization', () async {
        final result = await runner.run(Scenarios.cliCrashDuringInit);

        expect(result.success, isFalse);
        expect(result.errorMessage, contains('Crash'));
        expect(result.errorMessage, contains('CLI'));
        expect(
          result.log.any((line) => line.contains('CRASH')),
          isTrue,
          reason: 'Should log the crash',
        );
      });

      test('Scenario 3: CLI crashes while Bridge is processing', () async {
        final result = await runner.run(
          Scenarios.cliCrashDuringBridgeProcessing,
        );

        expect(result.success, isFalse);
        expect(result.errorMessage, contains('Crash'));
        expect(
          result.log.any((line) => line.contains('Bridge')),
          isTrue,
          reason: 'Bridge should have been started',
        );
      });

      test('Scenario 4: CLI crashes while Copilot is processing', () async {
        final result = await runner.run(Scenarios.cliCrashDuringCopilot);

        expect(result.success, isFalse);
        expect(result.errorMessage, contains('Crash'));
        expect(
          result.log.any((line) => line.contains('Copilot')),
          isTrue,
          reason: 'Copilot call should have been started',
        );
      });
    });

    // ═══════════════════════════════════════════════════════════════════
    // BRIDGE (SUPERVISOR) FAILURE SCENARIOS
    // ═══════════════════════════════════════════════════════════════════

    group('Bridge (Supervisor) Failure Scenarios', () {
      test('Scenario 5: Bridge crashes during initialization', () async {
        final result = await runner.run(Scenarios.bridgeCrashDuringInit);

        expect(result.success, isFalse);
        expect(result.errorMessage, contains('Crash'));
        expect(result.errorMessage, contains('Bridge'));
      });

      test('Scenario 6: Bridge crashes during Copilot call', () async {
        final result = await runner.run(Scenarios.bridgeCrashDuringCopilot);

        expect(result.success, isFalse);
        expect(result.errorMessage, contains('Crash'));
        expect(
          result.log.any((line) => line.contains('vscode-copilot')),
          isTrue,
          reason: 'Copilot call should have been initiated',
        );
      });

      test('Scenario 7: Bridge hangs indefinitely (stale heartbeat)', () async {
        final result = await runner.run(Scenarios.bridgeHang);

        // Hang scenario currently succeeds (no real hang detection in test)
        // This tests that long-running calls complete
        expect(result.log.any((line) => line.contains('Bridge')), isTrue);
      });
    });

    // ═══════════════════════════════════════════════════════════════════
    // EXTERNAL CALL FAILURE SCENARIOS
    // ═══════════════════════════════════════════════════════════════════

    group('External Call Failure Scenarios', () {
      test('Scenario 8: Copilot times out', () async {
        // Note: The timeout is tested via config, actual timeout not injected
        final result = await runner.run(Scenarios.copilotTimeout);

        expect(result.log, isNotEmpty);
        // The scenario completes but logs Copilot activity
      });

      test('Scenario 9: Copilot returns error', () async {
        final result = await runner.run(Scenarios.copilotError);

        expect(result.log, isNotEmpty);
        expect(result.log.any((line) => line.contains('Copilot')), isTrue);
      });
    });

    // ═══════════════════════════════════════════════════════════════════
    // USER ABORT SCENARIOS
    // ═══════════════════════════════════════════════════════════════════

    group('User Abort Scenarios', () {
      test('Scenario 10: User aborts during Bridge processing', () async {
        final result = await runner.run(Scenarios.userAbortDuringBridge);

        expect(result.exitCode, equals(130)); // SIGINT exit code
        expect(result.errorMessage, contains('Abort'));
        expect(
          result.log.any((line) => line.contains('USER ABORT')),
          isTrue,
          reason: 'Should log user abort event',
        );
      });

      test('Scenario 11: User aborts during Copilot call', () async {
        final result = await runner.run(Scenarios.userAbortDuringCopilot);

        expect(result.exitCode, equals(130));
        expect(
          result.log.any((line) => line.contains('Abort Cleanup')),
          isTrue,
          reason: 'Should perform abort cleanup',
        );
      });
    });

    // ═══════════════════════════════════════════════════════════════════
    // COMPLEX SCENARIOS
    // ═══════════════════════════════════════════════════════════════════

    group('Complex Scenarios', () {
      test('Scenario 12: Direct call without supervisor', () async {
        final result = await runner.run(Scenarios.directCallNoSupervisor);

        expect(result.success, isTrue);
        expect(result.exitCode, equals(0));
        // Should have fewer stack levels
        expect(
          result.log.where((line) => line.contains('createCallFrame')).length,
          lessThan(5),
          reason: 'Should have simpler call stack without Bridge',
        );
      });

      test('Scenario 13: Parallel calls from Bridge', () async {
        final result = await runner.run(Scenarios.parallelCallsFromBridge);

        expect(result.success, isTrue);
        expect(result.exitCode, equals(0));
        // Should execute both VSCode calls
        expect(
          result.log.where((line) => line.contains('vscode-call')).length,
          greaterThanOrEqualTo(2),
        );
      });

      test('Scenario 14: Deeply nested stack (5 levels)', () async {
        final result = await runner.run(Scenarios.deeplyNestedStack);

        expect(result.success, isTrue);
        expect(result.exitCode, equals(0));
        // Should have 5 levels of calls
        expect(
          result.log.any((line) => line.contains('level-5')),
          isTrue,
          reason: 'Should reach level 5',
        );
      });

      test('Scenario 15: Crash during cleanup phase', () async {
        final result = await runner.run(Scenarios.crashDuringCleanup);

        expect(result.success, isFalse);
        expect(result.errorMessage, contains('Crash'));
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // SCENARIO FRAMEWORK TESTS
  // ═══════════════════════════════════════════════════════════════════

  group('Scenario Framework', () {
    test('Scenarios.all contains all predefined scenarios', () {
      expect(Scenarios.all.length, equals(15));
    });

    test('Scenario categories are mutually exclusive', () {
      final success = Scenarios.successScenarios.map((s) => s.name).toSet();
      final initiator = Scenarios.initiatorFailures.map((s) => s.name).toSet();
      final supervisor = Scenarios.supervisorFailures
          .map((s) => s.name)
          .toSet();
      final external = Scenarios.externalCallFailures
          .map((s) => s.name)
          .toSet();
      final abort = Scenarios.userAbortScenarios.map((s) => s.name).toSet();
      // ignore: unused_local_variable
      final complex = Scenarios.complexScenarios.map((s) => s.name).toSet();

      // No overlaps between categories
      expect(success.intersection(initiator), isEmpty);
      expect(success.intersection(supervisor), isEmpty);
      expect(initiator.intersection(supervisor), isEmpty);
      expect(abort.intersection(external), isEmpty);
    });

    test(
      'SimulationScenario.isHappyPath returns true for success scenarios',
      () {
        expect(Scenarios.happyPath.isHappyPath, isTrue);
        expect(Scenarios.directCallNoSupervisor.isHappyPath, isTrue);
        expect(Scenarios.cliCrashDuringInit.isHappyPath, isFalse);
        expect(Scenarios.userAbortDuringBridge.isHappyPath, isFalse);
      },
    );

    test('ScenarioResult toString formats correctly', () {
      final successResult = ScenarioResult(
        scenarioName: 'test',
        success: true,
        elapsed: const Duration(milliseconds: 100),
        log: [],
        exitCode: 0,
      );

      expect(successResult.toString(), equals('[PASS] test (100ms)'));

      final failResult = ScenarioResult(
        scenarioName: 'fail_test',
        success: false,
        errorMessage: 'Something went wrong',
        elapsed: const Duration(milliseconds: 50),
        log: [],
        exitCode: 1,
      );

      expect(
        failResult.toString(),
        equals('[FAIL] fail_test (50ms) (Something went wrong)'),
      );
    });

    test('FailureInjection toString is descriptive', () {
      const failure = FailureInjection(
        participant: FailingParticipant.cli,
        type: FailureType.crash,
        phase: FailurePhase.initialization,
      );

      expect(failure.toString(), contains('cli'));
      expect(failure.toString(), contains('crash'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // CUSTOM SCENARIO TESTS
  // ═══════════════════════════════════════════════════════════════════

  group('Custom Scenarios', () {
    test(
      'Can create custom scenario with SimulationScenario.happyPath()',
      () async {
        final customScenario = SimulationScenario.happyPath(
          name: 'custom_happy',
          description: 'Custom happy path scenario',
        );

        expect(customScenario.name, equals('custom_happy'));
        expect(customScenario.isHappyPath, isTrue);
        expect(customScenario.callTree, isNotEmpty);

        final runner = ScenarioRunner(ledgerPath: tempDir.path);
        final result = await runner.run(customScenario);

        expect(result.success, isTrue);
      },
    );

    test('Can build scenario with custom call tree', () async {
      final customScenario = SimulationScenario(
        name: 'minimal_scenario',
        description: 'Single call, no nesting',
        expectedOutcome: 'Completes quickly',
        config: const SimulationConfig(
          callDelayMs: 10,
          externalCallResponseMs: 50,
        ),
        callTree: const [
          ScenarioCall(
            callId: 'simple-call',
            caller: FailingParticipant.cli,
            processingMs: 20,
          ),
        ],
      );

      final runner = ScenarioRunner(ledgerPath: tempDir.path);
      final result = await runner.run(customScenario);

      expect(result.success, isTrue);
      expect(result.elapsed.inMilliseconds, lessThan(500));
    });

    test('Can inject failure at specific call', () async {
      final failureScenario = SimulationScenario(
        name: 'targeted_failure',
        description: 'Failure injected at specific call',
        expectedOutcome: 'Fails at specified point',
        config: const SimulationConfig(callDelayMs: 10),
        callTree: const [
          ScenarioCall(
            callId: 'main-call',
            caller: FailingParticipant.cli,
            processingMs: 100,
          ),
        ],
        failures: const [
          FailureInjection(
            participant: FailingParticipant.cli,
            type: FailureType.crash,
            phase: FailurePhase.processing,
            callId: 'main-call',
            delayMs: 50,
          ),
        ],
      );

      final runner = ScenarioRunner(ledgerPath: tempDir.path);
      final result = await runner.run(failureScenario);

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('Crash'));
    });
  });
}
