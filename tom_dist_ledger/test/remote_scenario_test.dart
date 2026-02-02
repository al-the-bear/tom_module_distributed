/// Remote Participant Scenario Tests
///
/// Tests scenarios where some participants connect via LedgerServer (remote)
/// while others may use local file-based access. This simulates real-world
/// deployments where processes may run on different machines.
///
/// Architecture:
/// - Main test process starts a LedgerServer
/// - Isolates connect via RemoteLedgerClient
/// - All behavior uses standard ledger API (createOperation, startCall, etc.)
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:tom_dist_ledger/tom_dist_ledger.dart';

void main() {
  group('Remote Participant Scenarios', () {
    late Directory tempDir;
    late LedgerServer server;
    late int serverPort;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('remote_scenario_test_');
      server = await LedgerServer.start(
        basePath: tempDir.path,
        port: 0, // OS assigns port
      );
      serverPort = server.port;
    });

    tearDownAll(() async {
      await server.stop();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('CLI initiator with remote Bridge participant', () async {
      // CLI runs locally, creates operation
      final cliLedger = LocalLedger(
        basePath: tempDir.path,
        participantId: 'cli',
        heartbeatInterval: const Duration(milliseconds: 200),
        staleThreshold: const Duration(seconds: 2),
      );

      final cliOperation = await cliLedger.createOperation(
        description: 'Mixed local/remote test',
      );
      final operationId = cliOperation.operationId;

      // CLI starts its own call
      final cliCall = await cliOperation.startCall<void>(description: 'cli-main');

      // Bridge runs remotely (via server) in an isolate
      final bridgeResult = await _runRemoteBridgeInIsolate(
        serverPort: serverPort,
        operationId: operationId,
        workDurationMs: 500,
      );

      expect(bridgeResult['success'], isTrue);
      expect(bridgeResult['operationId'], equals(operationId));

      // CLI completes
      await cliCall.end();
      await cliOperation.complete();

      cliLedger.dispose();
    });

    test('Remote CLI initiator with remote Bridge participant', () async {
      // Both CLI and Bridge connect remotely
      final cliClient = RemoteLedgerClient(
        serverUrl: 'http://localhost:$serverPort',
        participantId: 'remote_cli',
        heartbeatInterval: const Duration(milliseconds: 200),
        staleThreshold: const Duration(seconds: 2),
      );

      final cliOperation = await cliClient.createOperation(
        description: 'Fully remote test',
      );
      final operationId = cliOperation.operationId;

      final cliCall = await cliOperation.startCall<void>(description: 'cli-main');

      // Bridge runs remotely in an isolate
      final bridgeResult = await _runRemoteBridgeInIsolate(
        serverPort: serverPort,
        operationId: operationId,
        workDurationMs: 500,
      );

      expect(bridgeResult['success'], isTrue);

      await cliCall.end();
      await cliOperation.complete();

      cliClient.dispose();
    });

    test('Remote participants with heartbeat monitoring', () async {
      final cliClient = RemoteLedgerClient(
        serverUrl: 'http://localhost:$serverPort',
        participantId: 'heartbeat_cli',
        heartbeatInterval: const Duration(milliseconds: 100),
        staleThreshold: const Duration(seconds: 1),
      );

      final cliOperation = await cliClient.createOperation(
        description: 'Heartbeat test',
      );
      final operationId = cliOperation.operationId;

      // Start heartbeat with explicit short interval
      var heartbeatCount = 0;
      cliOperation.startHeartbeat(
        interval: const Duration(milliseconds: 100),
        onSuccess: (response, operation) => heartbeatCount++,
      );

      final cliCall = await cliOperation.startCall<void>(description: 'cli-main');

      // Wait for some heartbeats to occur before starting bridge
      await Future.delayed(const Duration(milliseconds: 500));

      // Bridge runs remotely
      await _runRemoteBridgeInIsolate(
        serverPort: serverPort,
        operationId: operationId,
        workDurationMs: 500,
      );

      // Verify heartbeats occurred (should have at least 5+ with 100ms interval over ~1s)
      expect(heartbeatCount, greaterThan(0));

      await cliCall.end();
      await cliOperation.complete();

      cliClient.dispose();
    });

    test('Multiple remote participants join same operation', () async {
      final initiator = RemoteLedgerClient(
        serverUrl: 'http://localhost:$serverPort',
        participantId: 'initiator',
      );

      final operation = await initiator.createOperation(
        description: 'Multi-participant test',
      );
      final operationId = operation.operationId;

      final call = await operation.startCall<void>();

      // Spawn multiple remote workers
      final futures = <Future<Map<String, dynamic>>>[];
      for (var i = 0; i < 3; i++) {
        futures.add(_runRemoteBridgeInIsolate(
          serverPort: serverPort,
          operationId: operationId,
          workDurationMs: 200 + (i * 100),
          participantId: 'worker_$i',
        ));
      }

      final results = await Future.wait(futures);

      for (final result in results) {
        expect(result['success'], isTrue);
      }

      await call.end();
      await operation.complete();

      initiator.dispose();
    });

    test('Remote participant spawns calls correctly', () async {
      final client = RemoteLedgerClient(
        serverUrl: 'http://localhost:$serverPort',
        participantId: 'spawn_test_cli',
      );

      final operation = await client.createOperation();

      // Spawn multiple calls
      final spawned1 = operation.spawnCall<int>(
        work: (call, op) async {
          await Future.delayed(const Duration(milliseconds: 100));
          return 42;
        },
      );

      final spawned2 = operation.spawnCall<String>(
        work: (call, op) async {
          await Future.delayed(const Duration(milliseconds: 150));
          return 'hello';
        },
      );

      // Wait for both
      final result = await operation.sync([spawned1, spawned2]);

      expect(result.allSucceeded, isTrue);
      expect(spawned1.result, equals(42));
      expect(spawned2.result, equals('hello'));

      await operation.complete();
      client.dispose();
    });

    test('Abort propagates to remote participants', () async {
      final initiator = RemoteLedgerClient(
        serverUrl: 'http://localhost:$serverPort',
        participantId: 'abort_initiator',
      );

      final operation = await initiator.createOperation();
      final operationId = operation.operationId;

      // Start a call
      final call = await operation.startCall<void>();

      // Start a remote worker that checks for abort
      final workerFuture = _runRemoteWorkerWithAbortCheck(
        serverPort: serverPort,
        operationId: operationId,
      );

      // Give worker time to join
      await Future.delayed(const Duration(milliseconds: 200));

      // Set abort flag
      await operation.setAbortFlag(true);

      // Wait for worker result
      final result = await workerFuture;

      expect(result['abortDetected'], isTrue);

      await call.end();
      // Don't complete - operation is aborted

      initiator.dispose();
    });
  });
}

/// Run a remote bridge participant in an isolate.
Future<Map<String, dynamic>> _runRemoteBridgeInIsolate({
  required int serverPort,
  required String operationId,
  int workDurationMs = 500,
  String participantId = 'bridge',
}) async {
  final receivePort = ReceivePort();

  await Isolate.spawn(
    _remoteBridgeEntry,
    _RemoteBridgeConfig(
      serverPort: serverPort,
      operationId: operationId,
      workDurationMs: workDurationMs,
      participantId: participantId,
      sendPort: receivePort.sendPort,
    ),
  );

  final result = await receivePort.first as Map<String, dynamic>;
  receivePort.close();
  return result;
}

/// Configuration for remote bridge isolate.
class _RemoteBridgeConfig {
  final int serverPort;
  final String operationId;
  final int workDurationMs;
  final String participantId;
  final SendPort sendPort;

  _RemoteBridgeConfig({
    required this.serverPort,
    required this.operationId,
    required this.workDurationMs,
    required this.participantId,
    required this.sendPort,
  });
}

/// Isolate entry point for remote bridge.
Future<void> _remoteBridgeEntry(_RemoteBridgeConfig config) async {
  try {
    final client = RemoteLedgerClient(
      serverUrl: 'http://localhost:${config.serverPort}',
      participantId: config.participantId,
      heartbeatInterval: const Duration(milliseconds: 200),
    );

    final operation = await client.joinOperation(
      operationId: config.operationId,
    );

    final call = await operation.startCall<String>(
      description: '${config.participantId}-work',
    );

    // Simulate work
    await Future.delayed(Duration(milliseconds: config.workDurationMs));

    await call.end('completed');
    operation.leave();
    client.dispose();

    config.sendPort.send({
      'success': true,
      'operationId': config.operationId,
      'participantId': config.participantId,
    });
  } catch (e, st) {
    config.sendPort.send({
      'success': false,
      'error': e.toString(),
      'stackTrace': st.toString(),
    });
  }
}

/// Run a remote worker that checks for abort.
Future<Map<String, dynamic>> _runRemoteWorkerWithAbortCheck({
  required int serverPort,
  required String operationId,
}) async {
  final receivePort = ReceivePort();

  await Isolate.spawn(
    _remoteAbortCheckEntry,
    _RemoteBridgeConfig(
      serverPort: serverPort,
      operationId: operationId,
      workDurationMs: 2000, // Long enough for abort to be set
      participantId: 'abort_worker',
      sendPort: receivePort.sendPort,
    ),
  );

  final result = await receivePort.first as Map<String, dynamic>;
  receivePort.close();
  return result;
}

/// Isolate entry point for abort-checking worker.
Future<void> _remoteAbortCheckEntry(_RemoteBridgeConfig config) async {
  try {
    final client = RemoteLedgerClient(
      serverUrl: 'http://localhost:${config.serverPort}',
      participantId: config.participantId,
      heartbeatInterval: const Duration(milliseconds: 100),
    );

    final operation = await client.joinOperation(
      operationId: config.operationId,
    );

    final call = await operation.startCall<void>(
      description: '${config.participantId}-work',
    );

    // Check for abort periodically
    var abortDetected = false;
    for (var i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (await operation.checkAbort()) {
        abortDetected = true;
        break;
      }
    }

    await call.end();
    operation.leave();
    client.dispose();

    config.sendPort.send({
      'success': true,
      'abortDetected': abortDetected,
    });
  } catch (e, st) {
    config.sendPort.send({
      'success': false,
      'error': e.toString(),
      'stackTrace': st.toString(),
    });
  }
}
