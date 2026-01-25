import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:tom_dist_ledger/test_simulator.dart';

void main() {
  late Directory tempDir;
  final random = Random();

  /// Generate random heartbeat interval between 2-5 seconds (in ms).
  int randomHeartbeatMs() => 2000 + random.nextInt(3001); // 2000-5000ms

  /// Generate random operation delay between 5-10 seconds (in ms).
  int randomOperationDelayMs() => 5000 + random.nextInt(5001); // 5000-10000ms

  /// Heartbeat timeout is typically 2x the heartbeat interval.
  int heartbeatTimeoutMs(int heartbeatMs) => heartbeatMs * 2;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('isolate_scenario_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('IsolateScenarioRunner', () {
    test(
      'happy path completes without failure detection',
      () async {
        final heartbeatMs = randomHeartbeatMs();
        final processingMs = randomOperationDelayMs();
        final timeoutMs = heartbeatTimeoutMs(heartbeatMs);

        print('');
        print('Test parameters:');
        print('  Heartbeat interval: ${heartbeatMs}ms');
        print('  Heartbeat timeout: ${timeoutMs}ms');
        print('  Processing delay: ${processingMs}ms');
        print('');

        final runner = IsolateScenarioRunner(
          ledgerPath: tempDir.path,
          onLog: (msg) => print(msg),
        );

        final result = await runner.runHappyPath(
          processingMs: processingMs,
          heartbeatIntervalMs: heartbeatMs,
          heartbeatTimeoutMs: timeoutMs,
        );

        print('');
        print('Happy path completed in ${result.elapsed.inMilliseconds}ms');
        print('Events:');
        for (final event in result.events) {
          print('  $event');
        }

        expect(result.success, isTrue);
        expect(result.detectedFailure, isNull);
        expect(
          result.events.length,
          greaterThanOrEqualTo(4),
        ); // start, join, complete x2
      },
      timeout: Timeout(Duration(seconds: 90)),
    );

    test(
      'detects Bridge crash through stale heartbeat (config-driven)',
      () async {
        final heartbeatMs = randomHeartbeatMs();
        final crashAfterMs = randomOperationDelayMs();
        final timeoutMs = heartbeatTimeoutMs(heartbeatMs);
        final maxWaitMs = crashAfterMs + timeoutMs + (heartbeatMs * 3);

        print('');
        print('Test parameters:');
        print('  Heartbeat interval: ${heartbeatMs}ms');
        print('  Heartbeat timeout: ${timeoutMs}ms');
        print('  Crash after: ${crashAfterMs}ms');
        print('  Max wait: ${maxWaitMs}ms');
        print('');

        final runner = IsolateScenarioRunner(
          ledgerPath: tempDir.path,
          onLog: (msg) => print(msg),
        );

        // Crash is now configured, not commanded
        final result = await runner.runCrashDetectionScenario(
          crashingParticipant: 'Bridge',
          crashAfterMs: crashAfterMs,
          heartbeatIntervalMs: heartbeatMs,
          heartbeatTimeoutMs: timeoutMs,
          workDurationMs: crashAfterMs + maxWaitMs,
          maxWaitMs: maxWaitMs,
        );

        print('');
        print(
          'Crash detection completed in ${result.elapsed.inMilliseconds}ms',
        );
        print('Events:');
        for (final event in result.events) {
          print('  $event');
        }
        print('');
        print('Detected: ${result.detectedFailure}');

        expect(result.success, isTrue);
        expect(result.detectedFailure, isNotNull);
        expect(
          result.detectedFailure!.type,
          DetectedFailureType.staleHeartbeat,
        );
        expect(result.detectedFailure!.participant, 'CLI');
      },
      timeout: Timeout(Duration(seconds: 90)),
    );

    test(
      'detects CLI crash through stale heartbeat (config-driven)',
      () async {
        final heartbeatMs = randomHeartbeatMs();
        final crashAfterMs = randomOperationDelayMs();
        final timeoutMs = heartbeatTimeoutMs(heartbeatMs);
        final maxWaitMs = crashAfterMs + timeoutMs + (heartbeatMs * 3);

        print('');
        print('Test parameters:');
        print('  Heartbeat interval: ${heartbeatMs}ms');
        print('  Heartbeat timeout: ${timeoutMs}ms');
        print('  Crash after: ${crashAfterMs}ms');
        print('  Max wait: ${maxWaitMs}ms');
        print('');

        final runner = IsolateScenarioRunner(
          ledgerPath: tempDir.path,
          onLog: (msg) => print(msg),
        );

        final result = await runner.runCrashDetectionScenario(
          crashingParticipant: 'CLI',
          crashAfterMs: crashAfterMs,
          heartbeatIntervalMs: heartbeatMs,
          heartbeatTimeoutMs: timeoutMs,
          workDurationMs: crashAfterMs + maxWaitMs,
          maxWaitMs: maxWaitMs,
        );

        print('');
        print(
          'CLI crash detection completed in ${result.elapsed.inMilliseconds}ms',
        );
        print('Events:');
        for (final event in result.events) {
          print('  $event');
        }
        print('');
        print('Detected: ${result.detectedFailure}');

        expect(result.success, isTrue);
        expect(result.detectedFailure, isNotNull);
        expect(
          result.detectedFailure!.type,
          DetectedFailureType.staleHeartbeat,
        );
        expect(result.detectedFailure!.participant, 'Bridge');
      },
      timeout: Timeout(Duration(seconds: 90)),
    );

    test(
      'detects user abort through abort flag',
      () async {
        final heartbeatMs = randomHeartbeatMs();
        final abortAfterMs = randomOperationDelayMs();
        final timeoutMs = heartbeatTimeoutMs(heartbeatMs);
        final maxWaitMs = abortAfterMs + (heartbeatMs * 3);

        print('');
        print('Test parameters:');
        print('  Heartbeat interval: ${heartbeatMs}ms');
        print('  Heartbeat timeout: ${timeoutMs}ms');
        print('  Abort after: ${abortAfterMs}ms');
        print('  Max wait: ${maxWaitMs}ms');
        print('');

        final runner = IsolateScenarioRunner(
          ledgerPath: tempDir.path,
          onLog: (msg) => print(msg),
        );

        final result = await runner.runAbortScenario(
          abortAfterMs: abortAfterMs,
          heartbeatIntervalMs: heartbeatMs,
          heartbeatTimeoutMs: timeoutMs,
          maxWaitMs: maxWaitMs,
        );

        print('');
        print(
          'Abort detection completed in ${result.elapsed.inMilliseconds}ms',
        );
        print('Events:');
        for (final event in result.events) {
          print('  $event');
        }
        print('');
        print('Detected: ${result.detectedFailure}');

        expect(result.success, isTrue);
        expect(result.detectedFailure, isNotNull);
        expect(
          result.detectedFailure!.type,
          DetectedFailureType.abortRequested,
        );
      },
      timeout: Timeout(Duration(seconds: 90)),
    );

    test(
      'crash detection timing is realistic',
      () async {
        // This test verifies that crash detection happens within expected time bounds
        // Detection should occur after: crashTime + ~heartbeatTimeout
        // Detection should occur before: crashTime + heartbeatTimeout + extra margin

        final heartbeatMs = randomHeartbeatMs();
        final crashAfterMs = randomOperationDelayMs();
        final timeoutMs = heartbeatTimeoutMs(heartbeatMs);

        print('');
        print('Test parameters:');
        print('  Heartbeat interval: ${heartbeatMs}ms');
        print('  Heartbeat timeout: ${timeoutMs}ms');
        print('  Crash after: ${crashAfterMs}ms');
        print('');

        final runner = IsolateScenarioRunner(
          ledgerPath: tempDir.path,
          onLog: (msg) => print(msg),
        );

        final result = await runner.runCrashDetectionScenario(
          crashingParticipant: 'Bridge',
          crashAfterMs: crashAfterMs,
          heartbeatIntervalMs: heartbeatMs,
          heartbeatTimeoutMs: timeoutMs,
          workDurationMs: crashAfterMs + timeoutMs + (heartbeatMs * 4),
          maxWaitMs: crashAfterMs + timeoutMs + (heartbeatMs * 4),
        );

        final detectionMs = result.elapsed.inMilliseconds;

        // Detection should happen after crash + some monitoring delay
        // and before crash + timeout + 2x interval (worst case)
        final minExpected = crashAfterMs;
        final maxExpected = crashAfterMs + timeoutMs + (2 * heartbeatMs);

        print('');
        print('Detection timing test:');
        print('  Expected: ${minExpected}ms - ${maxExpected}ms');
        print('  Actual: ${detectionMs}ms');
        print('Events:');
        for (final event in result.events) {
          print('  $event');
        }

        expect(result.success, isTrue);
        expect(detectionMs, greaterThanOrEqualTo(minExpected));
        expect(detectionMs, lessThanOrEqualTo(maxExpected));
      },
      timeout: Timeout(Duration(seconds: 90)),
    );

    test(
      'detects error during processing (config-driven)',
      () async {
        final heartbeatMs = randomHeartbeatMs();
        final errorAfterMs = randomOperationDelayMs();
        final timeoutMs = heartbeatTimeoutMs(heartbeatMs);
        final maxWaitMs = errorAfterMs + (heartbeatMs * 3);

        print('');
        print('Test parameters:');
        print('  Heartbeat interval: ${heartbeatMs}ms');
        print('  Heartbeat timeout: ${timeoutMs}ms');
        print('  Error after: ${errorAfterMs}ms');
        print('  Max wait: ${maxWaitMs}ms');
        print('');

        final runner = IsolateScenarioRunner(
          ledgerPath: tempDir.path,
          onLog: (msg) => print(msg),
        );

        // Error scenario - processing fails cleanly
        final result = await runner.runErrorScenario(
          erroringParticipant: 'Bridge',
          errorAfterMs: errorAfterMs,
          errorMessage: 'Simulated processing failure',
          heartbeatIntervalMs: heartbeatMs,
          heartbeatTimeoutMs: timeoutMs,
          maxWaitMs: maxWaitMs,
        );

        print('');
        print(
          'Error detection completed in ${result.elapsed.inMilliseconds}ms',
        );
        print('Events:');
        for (final event in result.events) {
          print('  $event');
        }
        print('');
        print('Detected: ${result.detectedFailure}');

        expect(result.success, isTrue);
        expect(result.detectedFailure, isNotNull);
        // Error is detected either via abort flag (by CLI) or self-reported (by Bridge)
        // Both are valid - depends on timing
        expect(
          result.detectedFailure!.type,
          anyOf(
            DetectedFailureType.abortRequested,
            DetectedFailureType.heartbeatError,
          ),
        );
      },
      timeout: Timeout(Duration(seconds: 90)),
    );

    test(
      'chain scenario: crash in last participant (VSBridge)',
      () async {
        final heartbeatMs = randomHeartbeatMs();
        final crashAfterMs = randomOperationDelayMs();
        final timeoutMs = heartbeatTimeoutMs(heartbeatMs);
        final maxWaitMs = crashAfterMs + timeoutMs + (heartbeatMs * 3);

        print('');
        print('Test parameters:');
        print('  Heartbeat interval: ${heartbeatMs}ms');
        print('  Heartbeat timeout: ${timeoutMs}ms');
        print('  Crash after: ${crashAfterMs}ms');
        print('  Max wait: ${maxWaitMs}ms');
        print('');

        final runner = IsolateScenarioRunner(
          ledgerPath: tempDir.path,
          onLog: (msg) => print(msg),
        );

        final result = await runner.runChainScenario(
          failingParticipant: 'VSBridge',
          failureType: SimulatedFailure.crash,
          failAfterMs: crashAfterMs,
          heartbeatIntervalMs: heartbeatMs,
          heartbeatTimeoutMs: timeoutMs,
          workDurationMs: crashAfterMs + maxWaitMs,
          maxWaitMs: maxWaitMs,
        );

        print('');
        print(
          'Chain crash detection completed in ${result.elapsed.inMilliseconds}ms',
        );
        print('Events:');
        for (final event in result.events) {
          print('  $event');
        }
        print('');
        print('Detected: ${result.detectedFailure}');

        expect(result.success, isTrue);
        expect(result.detectedFailure, isNotNull);
        expect(
          result.detectedFailure!.type,
          DetectedFailureType.staleHeartbeat,
        );
        // Either CLI or Bridge should detect the VSBridge crash
        expect([
          'CLI',
          'Bridge',
        ], contains(result.detectedFailure!.participant));
      },
      timeout: Timeout(Duration(seconds: 120)),
    );

    test(
      'chain scenario: error in last participant (VSBridge)',
      () async {
        final heartbeatMs = randomHeartbeatMs();
        final errorAfterMs = randomOperationDelayMs();
        final timeoutMs = heartbeatTimeoutMs(heartbeatMs);
        final maxWaitMs = errorAfterMs + (heartbeatMs * 3);

        print('');
        print('Test parameters:');
        print('  Heartbeat interval: ${heartbeatMs}ms');
        print('  Heartbeat timeout: ${timeoutMs}ms');
        print('  Error after: ${errorAfterMs}ms');
        print('  Max wait: ${maxWaitMs}ms');
        print('');

        final runner = IsolateScenarioRunner(
          ledgerPath: tempDir.path,
          onLog: (msg) => print(msg),
        );

        final result = await runner.runChainScenario(
          failingParticipant: 'VSBridge',
          failureType: SimulatedFailure.error,
          failAfterMs: errorAfterMs,
          errorMessage: 'VSBridge processing failed',
          heartbeatIntervalMs: heartbeatMs,
          heartbeatTimeoutMs: timeoutMs,
          workDurationMs: errorAfterMs + maxWaitMs,
          maxWaitMs: maxWaitMs,
        );

        print('');
        print(
          'Chain error detection completed in ${result.elapsed.inMilliseconds}ms',
        );
        print('Events:');
        for (final event in result.events) {
          print('  $event');
        }
        print('');
        print('Detected: ${result.detectedFailure}');

        expect(result.success, isTrue);
        expect(result.detectedFailure, isNotNull);
        // VSBridge detects its own error
        expect(result.detectedFailure!.participant, 'VSBridge');
        expect(result.detectedFailure!.message, contains('Error'));
      },
      timeout: Timeout(Duration(seconds: 120)),
    );

    test(
      'chain scenario with VSCode callback: crash in Bridge',
      () async {
        final heartbeatMs = randomHeartbeatMs();
        final crashAfterMs = randomOperationDelayMs();
        final timeoutMs = heartbeatTimeoutMs(heartbeatMs);
        final maxWaitMs = crashAfterMs + timeoutMs + (heartbeatMs * 3);

        print('');
        print('Test parameters:');
        print('  Heartbeat interval: ${heartbeatMs}ms');
        print('  Heartbeat timeout: ${timeoutMs}ms');
        print('  Crash after: ${crashAfterMs}ms');
        print('  Max wait: ${maxWaitMs}ms');
        print('  Chain: CLI -> Bridge -> VSBridge -> VSCode callback');
        print('');

        final runner = IsolateScenarioRunner(
          ledgerPath: tempDir.path,
          onLog: (msg) => print(msg),
        );

        // Bridge crashes while VSCode is calling back through it
        final result = await runner.runChainScenario(
          failingParticipant: 'Bridge',
          failureType: SimulatedFailure.crash,
          failAfterMs: crashAfterMs,
          heartbeatIntervalMs: heartbeatMs,
          heartbeatTimeoutMs: timeoutMs,
          workDurationMs: crashAfterMs + maxWaitMs,
          maxWaitMs: maxWaitMs,
          includeVSCodeCallback: true,
        );

        print('');
        print(
          'Chain with callback crash detection completed in ${result.elapsed.inMilliseconds}ms',
        );
        print('Events:');
        for (final event in result.events) {
          print('  $event');
        }
        print('');
        print('Detected: ${result.detectedFailure}');

        expect(result.success, isTrue);
        expect(result.detectedFailure, isNotNull);
        expect(
          result.detectedFailure!.type,
          DetectedFailureType.staleHeartbeat,
        );
        // CLI, VSBridge, or VSCode should detect the Bridge crash
        expect([
          'CLI',
          'VSBridge',
          'VSCode',
        ], contains(result.detectedFailure!.participant));
      },
      timeout: Timeout(Duration(seconds: 120)),
    );

    test(
      'chain scenario with VSCode callback: error in VSCode',
      () async {
        final heartbeatMs = randomHeartbeatMs();
        final errorAfterMs = randomOperationDelayMs();
        final timeoutMs = heartbeatTimeoutMs(heartbeatMs);
        final maxWaitMs = errorAfterMs + (heartbeatMs * 3);

        print('');
        print('Test parameters:');
        print('  Heartbeat interval: ${heartbeatMs}ms');
        print('  Heartbeat timeout: ${timeoutMs}ms');
        print('  Error after: ${errorAfterMs}ms');
        print('  Max wait: ${maxWaitMs}ms');
        print('  Chain: CLI -> Bridge -> VSBridge -> VSCode callback');
        print('');

        final runner = IsolateScenarioRunner(
          ledgerPath: tempDir.path,
          onLog: (msg) => print(msg),
        );

        // VSCode (the callback) errors during processing
        final result = await runner.runChainScenario(
          failingParticipant: 'VSCode',
          failureType: SimulatedFailure.error,
          failAfterMs: errorAfterMs,
          errorMessage: 'VSCode callback processing failed',
          heartbeatIntervalMs: heartbeatMs,
          heartbeatTimeoutMs: timeoutMs,
          workDurationMs: errorAfterMs + maxWaitMs,
          maxWaitMs: maxWaitMs,
          includeVSCodeCallback: true,
        );

        print('');
        print(
          'VSCode error detection completed in ${result.elapsed.inMilliseconds}ms',
        );
        print('Events:');
        for (final event in result.events) {
          print('  $event');
        }
        print('');
        print('Detected: ${result.detectedFailure}');

        expect(result.success, isTrue);
        expect(result.detectedFailure, isNotNull);
        // VSCode detects its own error
        expect(result.detectedFailure!.participant, 'VSCode');
        expect(result.detectedFailure!.message, contains('Error'));
      },
      timeout: Timeout(Duration(seconds: 120)),
    );
  });

  group('IsolateParticipantHandle', () {
    test(
      'can spawn CLI isolate and complete operation',
      () async {
        final heartbeatMs = randomHeartbeatMs();
        final processingMs = 1000; // Short processing for this test
        final timeoutMs = heartbeatTimeoutMs(heartbeatMs);

        print('');
        print('Test parameters:');
        print('  Heartbeat interval: ${heartbeatMs}ms');
        print('  Heartbeat timeout: ${timeoutMs}ms');
        print('  Processing delay: ${processingMs}ms');
        print('');

        final handle = await IsolateParticipantHandle.spawn(
          name: 'TestCLI',
          pid: 9999,
          basePath: tempDir.path,
          isolateType: IsolateType.cli,
          heartbeatIntervalMs: heartbeatMs,
          heartbeatTimeoutMs: timeoutMs,
          workDurationMs: processingMs,
          onLog: (msg) => print(msg),
        );

        // Behavior auto-starts on spawn

        // Wait for completion
        final result = await handle.onCompleted.timeout(Duration(seconds: 30));

        expect(result, isNotNull);
        expect(result['operationId'], isNotNull);
        expect(handle.operationId, isNotEmpty);

        // Cleanup
        await handle.shutdown();
      },
      timeout: Timeout(Duration(seconds: 60)),
    );

    test(
      'config-driven crash stops heartbeat (no Isolate.kill)',
      () async {
        final heartbeatMs = 500; // Shorter for faster test
        final timeoutMs = heartbeatTimeoutMs(heartbeatMs);
        final crashAfterMs = 1000;

        print('');
        print('Test parameters:');
        print('  Heartbeat interval: ${heartbeatMs}ms');
        print('  Heartbeat timeout: ${timeoutMs}ms');
        print('  Crash after: ${crashAfterMs}ms');
        print('');

        final handle = await IsolateParticipantHandle.spawn(
          name: 'CrashTest',
          pid: 8888,
          basePath: tempDir.path,
          isolateType: IsolateType.cli,
          heartbeatIntervalMs: heartbeatMs,
          heartbeatTimeoutMs: timeoutMs,
          workDurationMs: 30000, // Long enough
          scenarioConfig: ScenarioConfig.crash(afterMs: crashAfterMs),
          onLog: (msg) => print(msg),
        );

        // Behavior auto-starts on spawn

        // Wait for operation to start
        await handle.responses
            .firstWhere(
              (r) =>
                  r.type == IsolateResponseType.event &&
                  r.message == 'operationStarted',
            )
            .timeout(Duration(seconds: 10));

        // Wait for crash notification (comes from config timer)
        final crashMsg = await handle.onCrashed.timeout(Duration(seconds: 10));
        expect(crashMsg, contains('crash'));
        expect(handle.isCrashed, isTrue);

        // Cleanup
        handle.forceKill();
      },
      timeout: Timeout(Duration(seconds: 30)),
    );

    test('IsolateType determines behavior', () async {
      final heartbeatMs = 500; // Shorter for this test
      final timeoutMs = 1000;
      final processingMs = 500;

      print('');
      print('Test: IsolateType determines behavior');
      print('');

      // Test CLI isolate type - creates operation
      final cliHandle = await IsolateParticipantHandle.spawn(
        name: 'CLI',
        pid: 1001,
        basePath: tempDir.path,
        isolateType: IsolateType.cli,
        heartbeatIntervalMs: heartbeatMs,
        heartbeatTimeoutMs: timeoutMs,
        workDurationMs: processingMs * 3,
        onLog: (msg) => print(msg),
      );

      // Behavior auto-starts on spawn

      // Wait for CLI to create operation
      await cliHandle.responses
          .firstWhere(
            (r) =>
                r.type == IsolateResponseType.event &&
                r.message == 'operationStarted',
          )
          .timeout(Duration(seconds: 5));

      final operationId = cliHandle.operationId!;
      expect(operationId, isNotEmpty);
      print('CLI created operation: $operationId');

      // Test Bridge isolate type - joins operation
      final bridgeHandle = await IsolateParticipantHandle.spawn(
        name: 'Bridge',
        pid: 2001,
        basePath: tempDir.path,
        isolateType: IsolateType.bridge,
        heartbeatIntervalMs: heartbeatMs,
        heartbeatTimeoutMs: timeoutMs,
        workDurationMs: processingMs,
        operationId: operationId,
        onLog: (msg) => print(msg),
      );

      // Behavior auto-starts on spawn

      // Wait for Bridge to join
      await bridgeHandle.responses
          .firstWhere(
            (r) =>
                r.type == IsolateResponseType.event &&
                r.message == 'operationJoined',
          )
          .timeout(Duration(seconds: 5));
      print('Bridge joined operation');

      // Wait for Bridge to complete
      await bridgeHandle.onCompleted.timeout(Duration(seconds: 10));
      print('Bridge completed');

      // Wait for CLI to complete
      await cliHandle.onCompleted.timeout(Duration(seconds: 10));
      print('CLI completed');

      // Cleanup
      await bridgeHandle.shutdown();
      await cliHandle.shutdown();
    }, timeout: Timeout(Duration(seconds: 30)));

    test(
      'FailureConfig.error causes clean failure',
      () async {
        final heartbeatMs = 500;
        final timeoutMs = 1000;
        final errorAfterMs = 800;

        print('');
        print('Test: FailureConfig.error causes clean failure');
        print('');

        final handle = await IsolateParticipantHandle.spawn(
          name: 'ErrorTest',
          pid: 7777,
          basePath: tempDir.path,
          isolateType: IsolateType.cli,
          heartbeatIntervalMs: heartbeatMs,
          heartbeatTimeoutMs: timeoutMs,
          workDurationMs: 30000,
          scenarioConfig: ScenarioConfig.error(
            afterMs: errorAfterMs,
            message: 'Test error message',
          ),
          onLog: (msg) => print(msg),
        );

        // Behavior auto-starts on spawn

        // Wait for failure detection
        final failure = await handle.onFailureDetected.timeout(
          Duration(seconds: 10),
        );

        expect(failure.message, contains('Error'));
        print('Failure detected: ${failure.message}');

        // Cleanup
        handle.forceKill();
      },
      timeout: Timeout(Duration(seconds: 30)),
    );
  });
}
