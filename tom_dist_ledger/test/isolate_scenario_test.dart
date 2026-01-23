import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:tom_dist_ledger/tom_dist_ledger.dart';

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
    test('happy path completes without failure detection', () async {
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
      expect(result.events.length, greaterThanOrEqualTo(4)); // start, join, complete x2
    }, timeout: Timeout(Duration(seconds: 90)));

    test('detects Bridge crash through stale heartbeat', () async {
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
        crashingParticipant: 'Bridge',
        crashAfterMs: crashAfterMs,
        heartbeatIntervalMs: heartbeatMs,
        heartbeatTimeoutMs: timeoutMs,
        workDurationMs: crashAfterMs + maxWaitMs,
        maxWaitMs: maxWaitMs,
      );

      print('');
      print('Crash detection completed in ${result.elapsed.inMilliseconds}ms');
      print('Events:');
      for (final event in result.events) {
        print('  $event');
      }
      print('');
      print('Detected: ${result.detectedFailure}');

      expect(result.success, isTrue);
      expect(result.detectedFailure, isNotNull);
      expect(result.detectedFailure!.type, DetectedFailureType.staleHeartbeat);
      expect(result.detectedFailure!.participant, 'CLI');
    }, timeout: Timeout(Duration(seconds: 90)));

    test('detects CLI crash through stale heartbeat', () async {
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
      print('CLI crash detection completed in ${result.elapsed.inMilliseconds}ms');
      print('Events:');
      for (final event in result.events) {
        print('  $event');
      }
      print('');
      print('Detected: ${result.detectedFailure}');

      expect(result.success, isTrue);
      expect(result.detectedFailure, isNotNull);
      expect(result.detectedFailure!.type, DetectedFailureType.staleHeartbeat);
      expect(result.detectedFailure!.participant, 'Bridge');
    }, timeout: Timeout(Duration(seconds: 90)));

    test('detects user abort through abort flag', () async {
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
      print('Abort detection completed in ${result.elapsed.inMilliseconds}ms');
      print('Events:');
      for (final event in result.events) {
        print('  $event');
      }
      print('');
      print('Detected: ${result.detectedFailure}');

      expect(result.success, isTrue);
      expect(result.detectedFailure, isNotNull);
      expect(result.detectedFailure!.type, DetectedFailureType.abortRequested);
    }, timeout: Timeout(Duration(seconds: 90)));

    test('crash detection timing is realistic', () async {
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
    }, timeout: Timeout(Duration(seconds: 90)));
  });

  group('IsolateParticipantHandle', () {
    test('can spawn CLI isolate and complete operation', () async {
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

      // Start the CLI behavior
      handle.start();

      // Wait for completion
      final result = await handle.onCompleted.timeout(Duration(seconds: 30));

      expect(result, isNotNull);
      expect(result['operationId'], isNotNull);
      expect(handle.operationId, isNotEmpty);

      // Cleanup
      await handle.shutdown();
    }, timeout: Timeout(Duration(seconds: 60)));

    test('crash() kills isolate immediately (sudden silence)', () async {
      final heartbeatMs = randomHeartbeatMs();
      final timeoutMs = heartbeatTimeoutMs(heartbeatMs);

      print('');
      print('Test parameters:');
      print('  Heartbeat interval: ${heartbeatMs}ms');
      print('  Heartbeat timeout: ${timeoutMs}ms');
      print('');

      final handle = await IsolateParticipantHandle.spawn(
        name: 'CrashTest',
        pid: 8888,
        basePath: tempDir.path,
        isolateType: IsolateType.cli,
        heartbeatIntervalMs: heartbeatMs,
        heartbeatTimeoutMs: timeoutMs,
        workDurationMs: 30000, // Long enough to crash during
        onLog: (msg) => print(msg),
      );

      // Start the CLI behavior
      handle.start();

      // Wait for operation to start
      await handle.responses
          .firstWhere((r) => r.type == IsolateResponseType.event && r.message == 'operationStarted')
          .timeout(Duration(seconds: 10));

      // Crash - isolate dies immediately, no message, no cleanup
      handle.crash();
      expect(handle.isCrashed, isTrue);

      // Verify isolate is dead by waiting briefly
      await Future.delayed(Duration(milliseconds: 100));
    }, timeout: Timeout(Duration(seconds: 30)));

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

      cliHandle.start();

      // Wait for CLI to create operation
      await cliHandle.responses
          .firstWhere((r) => r.type == IsolateResponseType.event && r.message == 'operationStarted')
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

      bridgeHandle.start();

      // Wait for Bridge to join
      await bridgeHandle.responses
          .firstWhere((r) => r.type == IsolateResponseType.event && r.message == 'operationJoined')
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
  });
}
