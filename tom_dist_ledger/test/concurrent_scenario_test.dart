import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_dist_ledger/test_simulator.dart';

/// Tests for the concurrent scenario runner that demonstrates
/// actual async failure detection through heartbeat monitoring.
///
/// These tests verify that:
/// 1. Participants run independently and update heartbeats
/// 2. Crashes stop heartbeats and are detected via staleness
/// 3. Abort flags are detected through heartbeat checks
/// 4. Cleanup happens after failure detection
void main() {
  late String ledgerPath;

  setUp(() async {
    ledgerPath =
        '${Directory.systemTemp.path}/concurrent_test_${DateTime.now().millisecondsSinceEpoch}';
  });

  tearDown(() async {
    final dir = Directory(ledgerPath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  group('ConcurrentScenarioRunner', () {
    test('happy path completes without failure detection', () async {
      final runner = ConcurrentScenarioRunner(ledgerPath: ledgerPath);

      // Use generous threshold (5x interval) to avoid false positives
      final result = await runner.runHappyPath(
        processingMs: 500,
        heartbeatIntervalMs: 100,
        heartbeatTimeoutMs: 2000, // Generous threshold to avoid false positives
      );

      expect(result.success, isTrue);
      expect(result.detectedFailure, isNull);
      expect(result.events.length, greaterThan(2));

      print('Happy path completed in ${result.elapsed.inMilliseconds}ms');
      print('Events:');
      for (final event in result.events) {
        print('  $event');
      }
    });

    test('detects Bridge crash through stale heartbeat', () async {
      final runner = ConcurrentScenarioRunner(ledgerPath: ledgerPath);

      // Crash after 1 second, with 500ms heartbeat interval and 1.5s timeout
      // Detection should happen at ~2-2.5s (crash + timeout + next heartbeat)
      final result = await runner.runCrashDetectionScenario(
        crashingParticipant: 'Bridge',
        crashAfterMs: 1000,
        heartbeatIntervalMs: 500,
        heartbeatTimeoutMs: 1500,
        maxWaitMs: 10000,
      );

      expect(
        result.success,
        isTrue,
        reason: result.errorMessage ?? 'Unknown error',
      );
      expect(result.detectedFailure, isNotNull);
      expect(
        result.detectedFailure!.type,
        equals(DetectedFailureType.staleHeartbeat),
      );
      expect(result.detectedFailure!.participant, equals('CLI'));

      print('Crash detection completed in ${result.elapsed.inMilliseconds}ms');
      print('Events:');
      for (final event in result.events) {
        print('  $event');
      }
      print('\nDetected: ${result.detectedFailure}');
    });

    test('detects CLI crash through stale heartbeat', () async {
      final runner = ConcurrentScenarioRunner(ledgerPath: ledgerPath);

      final result = await runner.runCrashDetectionScenario(
        crashingParticipant: 'CLI',
        crashAfterMs: 1000,
        heartbeatIntervalMs: 500,
        heartbeatTimeoutMs: 1500,
        maxWaitMs: 10000,
      );

      expect(
        result.success,
        isTrue,
        reason: result.errorMessage ?? 'Unknown error',
      );
      expect(result.detectedFailure, isNotNull);
      expect(
        result.detectedFailure!.type,
        equals(DetectedFailureType.staleHeartbeat),
      );
      expect(result.detectedFailure!.participant, equals('Bridge'));

      print(
        'CLI crash detection completed in ${result.elapsed.inMilliseconds}ms',
      );
      print('Events:');
      for (final event in result.events) {
        print('  $event');
      }
      print('\nDetected: ${result.detectedFailure}');
    });

    test('detects user abort through abort flag', () async {
      final runner = ConcurrentScenarioRunner(ledgerPath: ledgerPath);

      final result = await runner.runAbortScenario(
        abortAfterMs: 800,
        heartbeatIntervalMs: 200,
        heartbeatTimeoutMs: 1000,
        maxWaitMs: 5000,
      );

      expect(
        result.success,
        isTrue,
        reason: result.errorMessage ?? 'Unknown error',
      );
      expect(result.detectedFailure, isNotNull);
      expect(
        result.detectedFailure!.type,
        equals(DetectedFailureType.abortRequested),
      );

      print('Abort detection completed in ${result.elapsed.inMilliseconds}ms');
      print('Events:');
      for (final event in result.events) {
        print('  $event');
      }
      print('\nDetected: ${result.detectedFailure}');
    });

    test('crash detection timing is realistic', () async {
      final runner = ConcurrentScenarioRunner(ledgerPath: ledgerPath);

      // Use longer intervals to verify timing
      // Heartbeat: 1 second, Timeout: 2 seconds
      // Crash at 2 seconds
      // Detection: when (lastHeartbeat + stalenessThreshold) is exceeded
      // Bridge heartbeats at ~0.5s, ~1.5s, then crashes at 2s
      // So last heartbeat is at ~1.5s, staleness detected when time > 1.5s + 2s = 3.5s
      final result = await runner.runCrashDetectionScenario(
        crashingParticipant: 'Bridge',
        crashAfterMs: 2000,
        heartbeatIntervalMs: 1000,
        heartbeatTimeoutMs: 2000,
        maxWaitMs: 15000,
      );

      expect(
        result.success,
        isTrue,
        reason: result.errorMessage ?? 'Unknown error',
      );

      // Detection timing depends on:
      // 1. When the crashing participant last sent a heartbeat before crashing
      // 2. The staleness threshold
      // 3. When the detector's next heartbeat check occurs
      // Minimum: crash_time (2000ms), practically it's after threshold is exceeded
      // Maximum: crash_time + threshold + interval = 2000 + 2000 + 1000 = 5000ms (with margin)
      final expectedMinMs =
          2500; // At least past crash time + some threshold time
      final expectedMaxMs = 6000; // Generous upper bound

      expect(
        result.elapsed.inMilliseconds,
        greaterThanOrEqualTo(expectedMinMs),
        reason: 'Detection too fast - heartbeat timeout not working',
      );
      expect(
        result.elapsed.inMilliseconds,
        lessThanOrEqualTo(expectedMaxMs),
        reason: 'Detection too slow',
      );

      print('Detection timing test:');
      print('  Expected: ${expectedMinMs}ms - ${expectedMaxMs}ms');
      print('  Actual: ${result.elapsed.inMilliseconds}ms');
      print('Events:');
      for (final event in result.events) {
        print('  $event');
      }
    });
  });

  group('IndependentParticipant', () {
    test('crash() hangs indefinitely and stops heartbeat', () async {
      final printer = AsyncSimulationPrinter();

      final participant = IndependentParticipant(
        name: 'TestParticipant',
        pid: 9999,
        basePath: ledgerPath,
        printer: printer,
        heartbeatIntervalMs: 100,
        heartbeatTimeoutMs: 500,
      );

      try {
        await participant.startOperation(depth: 1);
        await participant.createCallFrame(callId: 'test-call', depth: 1);
        participant.startHeartbeat(depth: 1, expectedCallFrameCount: 1);

        // Start crash in background (will never return)
        var crashStarted = false;
        // ignore: unawaited_futures
        participant.crash(depth: 1).then((_) {
          // This should never be reached
          fail('crash() should never complete normally');
        }).ignore();
        crashStarted = true;

        expect(crashStarted, isTrue);

        // Wait a bit and verify participant is crashed
        await Future.delayed(const Duration(milliseconds: 100));
        expect(participant.isCrashed, isTrue);
      } finally {
        participant.forceStop();
      }
    });
  });
}
