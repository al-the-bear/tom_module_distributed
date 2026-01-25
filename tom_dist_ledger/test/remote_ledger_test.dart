import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_dist_ledger/tom_dist_ledger.dart';

void main() {
  late Directory tempDir;
  late LedgerServer server;
  late String serverUrl;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('remote_ledger_test_');
    server = await LedgerServer.start(
      basePath: tempDir.path,
      port: 0, // Let OS assign a free port
    );
    serverUrl = 'http://localhost:${server.port}';
  });

  tearDownAll(() async {
    await server.stop();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  // ═══════════════════════════════════════════════════════════════════
  // LEDGER SERVER TESTS
  // ═══════════════════════════════════════════════════════════════════

  group('LedgerServer', () {
    test('starts on specified port', () async {
      final customServer = await LedgerServer.start(
        basePath: tempDir.path,
        port: 0,
      );
      expect(customServer.port, greaterThan(0));
      await customServer.stop();
    });

    test('basePath is accessible', () {
      expect(server.basePath, equals(tempDir.path));
    });

    test('health endpoint returns ok', () async {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('$serverUrl/health'));
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      final data = jsonDecode(body) as Map<String, dynamic>;

      expect(response.statusCode, equals(200));
      expect(data['status'], equals('ok'));
      client.close();
    });

    test('unknown endpoint returns 404', () async {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('$serverUrl/unknown'));
      final response = await request.close();

      expect(response.statusCode, equals(404));
      client.close();
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // REMOTE LEDGER CLIENT TESTS
  // ═══════════════════════════════════════════════════════════════════

  group('RemoteLedgerClient', () {
    late RemoteLedgerClient client;

    setUp(() {
      client = RemoteLedgerClient(
        serverUrl: serverUrl,
        participantId: 'test_client',
        heartbeatInterval: const Duration(seconds: 1),
        staleThreshold: const Duration(seconds: 3),
      );
    });

    tearDown(() {
      client.dispose();
    });

    group('initialization', () {
      test('stores serverUrl and participantId', () {
        expect(client.serverUrl, equals(serverUrl));
        expect(client.participantId, equals('test_client'));
      });

      test('has default maxBackups', () {
        expect(client.maxBackups, equals(20));
      });

      test('participantPid defaults to current process', () {
        expect(client.participantPid, equals(pid));
      });
    });

    group('createOperation', () {
      test('creates operation and returns RemoteOperation', () async {
        final operation = await client.createOperation(
          description: 'Test operation',
        );

        expect(operation.operationId, isNotEmpty);
        expect(operation.participantId, equals('test_client'));
        expect(operation.isInitiator, isTrue);
        expect(operation.sessionId, greaterThan(0));
        expect(operation.startTime, isNotNull);

        // Verify file was created on server
        final opFile = File(
          '${tempDir.path}/${operation.operationId}.operation.json',
        );
        expect(opFile.existsSync(), isTrue);

        await operation.complete();
      });

      test('operation file contains correct data', () async {
        final operation = await client.createOperation(
          description: 'Data test',
        );

        final opFile = File(
          '${tempDir.path}/${operation.operationId}.operation.json',
        );
        final content =
            jsonDecode(opFile.readAsStringSync()) as Map<String, dynamic>;

        expect(content['operationId'], equals(operation.operationId));
        expect(content['initiatorId'], equals('test_client'));

        await operation.complete();
      });
    });

    group('joinOperation', () {
      test('joins existing operation', () async {
        // Create operation with first client
        final client1 = RemoteLedgerClient(
          serverUrl: serverUrl,
          participantId: 'initiator',
        );
        final op1 = await client1.createOperation();

        // Join with second client
        final client2 = RemoteLedgerClient(
          serverUrl: serverUrl,
          participantId: 'joiner',
        );
        final op2 = await client2.joinOperation(operationId: op1.operationId);

        expect(op2.operationId, equals(op1.operationId));
        expect(op2.participantId, equals('joiner'));
        expect(op2.isInitiator, isFalse);

        await op1.complete();
        client1.dispose();
        client2.dispose();
      });

      test('throws on non-existent operation', () async {
        expect(
          () => client.joinOperation(operationId: 'non_existent_operation'),
          throwsA(isA<RemoteLedgerException>()),
        );
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // REMOTE OPERATION TESTS
  // ═══════════════════════════════════════════════════════════════════

  group('RemoteOperation', () {
    late RemoteLedgerClient client;

    setUp(() {
      client = RemoteLedgerClient(
        serverUrl: serverUrl,
        participantId: 'test_client',
        heartbeatInterval: const Duration(seconds: 1),
      );
    });

    tearDown(() {
      client.dispose();
    });

    group('properties', () {
      test('exposes operationId', () async {
        final operation = await client.createOperation();
        expect(operation.operationId, isNotEmpty);
        expect(operation.operationId, contains('test_client'));
        await operation.complete();
      });

      test('exposes participantId', () async {
        final operation = await client.createOperation();
        expect(operation.participantId, equals('test_client'));
        await operation.complete();
      });

      test('exposes startTime', () async {
        final before = DateTime.now();
        final operation = await client.createOperation();
        final after = DateTime.now();

        expect(
          operation.startTime.isAfter(
            before.subtract(const Duration(seconds: 1)),
          ),
          isTrue,
        );
        expect(
          operation.startTime.isBefore(after.add(const Duration(seconds: 1))),
          isTrue,
        );
        await operation.complete();
      });

      test('exposes elapsed helpers', () async {
        final operation = await client.createOperation();
        await Future.delayed(const Duration(milliseconds: 10));

        expect(operation.elapsedFormatted, matches(RegExp(r'^\d{3}\.\d{3}$')));
        expect(operation.elapsedDuration.inMilliseconds, greaterThan(0));
        expect(operation.startTimeIso, contains('T'));
        expect(operation.startTimeMs, greaterThan(0));

        await operation.complete();
      });
    });

    group('startCall', () {
      test('returns Call<T> with callId', () async {
        final operation = await client.createOperation();

        final call = await operation.startCall<int>(description: 'Test call');

        expect(call.callId, isNotEmpty);
        expect(call.startedAt, isNotNull);
        expect(call.isCompleted, isFalse);

        await call.end(42);
        await operation.complete();
      });

      test('registers call frame on server', () async {
        final operation = await client.createOperation();
        final operationId = operation.operationId;

        final call = await operation.startCall<void>(
          description: 'Registered call',
        );

        // Verify call frame exists on server
        final opFile = File('${tempDir.path}/$operationId.operation.json');
        final content =
            jsonDecode(opFile.readAsStringSync()) as Map<String, dynamic>;
        final callFrames = content['callFrames'] as List;

        expect(callFrames.length, equals(1));
        expect(callFrames[0]['callId'], equals(call.callId));
        expect(callFrames[0]['description'], equals('Registered call'));

        await call.end();
        await operation.complete();
      });

      test('supports typed results', () async {
        final operation = await client.createOperation();

        final stringCall = await operation.startCall<String>();
        await stringCall.end('hello');

        final intCall = await operation.startCall<int>();
        await intCall.end(42);

        final mapCall = await operation.startCall<Map<String, dynamic>>();
        await mapCall.end({'key': 'value'});

        await operation.complete();
      });

      test('supports callbacks', () async {
        final operation = await client.createOperation();

        var completionCalled = false;
        String? completionResult;

        final call = await operation.startCall<String>(
          callback: CallCallback<String>(
            onCompletion: (result) async {
              completionCalled = true;
              completionResult = result;
            },
          ),
        );

        await call.end('done');
        await Future.delayed(const Duration(milliseconds: 10));

        expect(completionCalled, isTrue);
        expect(completionResult, equals('done'));

        await operation.complete();
      });
    });

    group('call.end', () {
      test('removes call frame from server', () async {
        final operation = await client.createOperation();
        final operationId = operation.operationId;

        final call = await operation.startCall<void>();

        // Verify call frame exists
        var opFile = File('${tempDir.path}/$operationId.operation.json');
        var content =
            jsonDecode(opFile.readAsStringSync()) as Map<String, dynamic>;
        expect((content['callFrames'] as List).length, equals(1));

        await call.end();

        // Verify call frame removed
        content = jsonDecode(opFile.readAsStringSync()) as Map<String, dynamic>;
        expect((content['callFrames'] as List), isEmpty);

        await operation.complete();
      });

      test('marks call as completed', () async {
        final operation = await client.createOperation();
        final call = await operation.startCall<int>();

        expect(call.isCompleted, isFalse);
        await call.end(42);
        expect(call.isCompleted, isTrue);

        await operation.complete();
      });
    });

    group('call.fail', () {
      test('removes call frame from server', () async {
        final operation = await client.createOperation();
        final operationId = operation.operationId;

        final call = await operation.startCall<void>(failOnCrash: false);

        // Verify call frame exists
        var opFile = File('${tempDir.path}/$operationId.operation.json');
        var content =
            jsonDecode(opFile.readAsStringSync()) as Map<String, dynamic>;
        expect((content['callFrames'] as List).length, equals(1));

        await call.fail('Test error');

        // Verify call frame removed
        content = jsonDecode(opFile.readAsStringSync()) as Map<String, dynamic>;
        expect((content['callFrames'] as List), isEmpty);

        await operation.complete();
      });

      test('triggers onCleanup callback', () async {
        final operation = await client.createOperation();

        var cleanupCalled = false;

        final call = await operation.startCall<void>(
          callback: CallCallback<void>(
            onCleanup: () async {
              cleanupCalled = true;
            },
          ),
          failOnCrash: false,
        );

        await call.fail('Test error');
        await Future.delayed(const Duration(milliseconds: 10));

        expect(cleanupCalled, isTrue);

        await operation.complete();
      });

      test('signals operation failure when failOnCrash=true', () async {
        final operation = await client.createOperation();

        OperationFailedInfo? failedInfo;
        operation.onFailure.then((info) {
          failedInfo = info;
        });

        final call = await operation.startCall<void>(failOnCrash: true);

        await call.fail('Crash!');
        await Future.delayed(const Duration(milliseconds: 10));

        expect(failedInfo, isNotNull);
        expect(failedInfo!.crashedCallIds, contains(call.callId));

        await operation.complete();
      });
    });

    group('spawnCall', () {
      test('returns SpawnedCall immediately', () async {
        final operation = await client.createOperation();

        final spawned = operation.spawnCall<int>(
          work: (_, __) async {
            await Future.delayed(const Duration(milliseconds: 100));
            return 42;
          },
        );

        expect(spawned.callId, isNotEmpty);
        expect(spawned.isCompleted, isFalse);

        await spawned.future;
        expect(spawned.isCompleted, isTrue);
        expect(spawned.result, equals(42));

        await operation.complete();
      });

      test('executes work function', () async {
        final operation = await client.createOperation();
        var workExecuted = false;

        final spawned = operation.spawnCall<String>(
          work: (_, __) async {
            workExecuted = true;
            return 'done';
          },
        );

        await spawned.future;

        expect(workExecuted, isTrue);
        expect(spawned.result, equals('done'));

        await operation.complete();
      });

      test('supports call and operation access', () async {
        final operation = await client.createOperation();

        final spawned = operation.spawnCall<String>(
          work: (call, op) async {
            return 'callId: ${call.callId}, opId: ${op.operationId}';
          },
        );

        await spawned.future;
        expect(spawned.result, startsWith('callId: spawn_'));
        expect(spawned.result, contains('opId:'));

        await operation.complete();
      });

      test('handles work failure', () async {
        final operation = await client.createOperation();

        final spawned = operation.spawnCall<int>(
          work: (_, __) async {
            throw Exception('Work failed');
          },
          failOnCrash: false,
        );

        await spawned.future;

        expect(spawned.isFailed, isTrue);
        expect(spawned.error, isNotNull);

        await operation.complete();
      });

      test('uses onCallCrashed for fallback', () async {
        final operation = await client.createOperation();

        final spawned = operation.spawnCall<String>(
          work: (_, __) async {
            throw Exception('Work failed');
          },
          callback: CallCallback<String>(onCallCrashed: () async => 'fallback'),
          failOnCrash: false,
        );

        await spawned.future;

        expect(spawned.isSuccess, isTrue);
        expect(spawned.result, equals('fallback'));

        await operation.complete();
      });

      test('triggers onCompletion callback', () async {
        final operation = await client.createOperation();

        var completionCalled = false;
        int? completionResult;

        final spawned = operation.spawnCall<int>(
          work: (_, __) async => 42,
          callback: CallCallback<int>(
            onCompletion: (result) async {
              completionCalled = true;
              completionResult = result;
            },
          ),
        );

        await spawned.future;
        await Future.delayed(const Duration(milliseconds: 10));

        expect(completionCalled, isTrue);
        expect(completionResult, equals(42));

        await operation.complete();
      });

      test('triggers onCleanup on failure', () async {
        final operation = await client.createOperation();

        var cleanupCalled = false;

        final spawned = operation.spawnCall<int>(
          work: (_, __) async => throw Exception('fail'),
          callback: CallCallback<int>(
            onCleanup: () async {
              cleanupCalled = true;
            },
          ),
          failOnCrash: false,
        );

        await spawned.future;
        await Future.delayed(const Duration(milliseconds: 10));

        expect(cleanupCalled, isTrue);

        await operation.complete();
      });
    });

    group('session call tracking', () {
      test('hasPendingCalls returns correct state', () async {
        final operation = await client.createOperation();

        expect(operation.hasPendingCalls(), isFalse);

        final call = await operation.startCall<void>();
        expect(operation.hasPendingCalls(), isTrue);

        await call.end();
        expect(operation.hasPendingCalls(), isFalse);

        await operation.complete();
      });

      test('getPendingCalls returns active calls', () async {
        final operation = await client.createOperation();

        final call1 = await operation.startCall<void>();
        final call2 = await operation.startCall<void>();

        final pending = operation.getPendingCalls();
        expect(pending.length, equals(2));

        await call1.end();
        expect(operation.getPendingCalls().length, equals(1));

        await call2.end();
        expect(operation.getPendingCalls(), isEmpty);

        await operation.complete();
      });

      test('getPendingSpawnedCalls returns active spawned calls', () async {
        final operation = await client.createOperation();

        final spawned1 = operation.spawnCall<int>(
          work: (_, __) async {
            await Future.delayed(const Duration(milliseconds: 200));
            return 1;
          },
        );

        final spawned2 = operation.spawnCall<int>(
          work: (_, __) async {
            await Future.delayed(const Duration(milliseconds: 200));
            return 2;
          },
        );

        // Wait for calls to be registered
        await Future.delayed(const Duration(milliseconds: 20));

        final pending = operation.getPendingSpawnedCalls();
        expect(pending.length, equals(2));

        await spawned1.future;
        await spawned2.future;

        await operation.complete();
      });
    });

    group('sync', () {
      test('waits for multiple spawned calls', () async {
        final operation = await client.createOperation();

        final call1 = operation.spawnCall<int>(work: (_, __) async => 1);
        final call2 = operation.spawnCall<int>(work: (_, __) async => 2);
        final call3 = operation.spawnCall<int>(work: (_, __) async => 3);

        final result = await operation.sync([call1, call2, call3]);

        expect(result.allSucceeded, isTrue);
        expect(result.successfulCalls.length, equals(3));
        expect(result.failedCalls, isEmpty);
        expect(result.unknownCalls, isEmpty);

        await operation.complete();
      });

      test('reports failed calls', () async {
        final operation = await client.createOperation();

        final call1 = operation.spawnCall<int>(
          work: (_, __) async => 1,
          failOnCrash: false,
        );
        final call2 = operation.spawnCall<int>(
          work: (_, __) async => throw Exception('fail'),
          failOnCrash: false,
        );

        final result = await operation.sync([call1, call2]);

        expect(result.hasFailed, isTrue);
        expect(result.successfulCalls.length, equals(1));
        expect(result.failedCalls.length, equals(1));

        await operation.complete();
      });

      test('calls onCompletion when all succeed', () async {
        final operation = await client.createOperation();

        var completionCalled = false;

        final call1 = operation.spawnCall<int>(work: (_, __) async => 1);
        final call2 = operation.spawnCall<int>(work: (_, __) async => 2);

        await operation.sync(
          [call1, call2],
          onCompletion: () async {
            completionCalled = true;
          },
        );

        expect(completionCalled, isTrue);

        await operation.complete();
      });
    });

    group('awaitCall', () {
      test('waits for single spawned call', () async {
        final operation = await client.createOperation();

        final call = operation.spawnCall<String>(
          work: (_, __) async => 'result',
        );

        final result = await operation.awaitCall(call);

        expect(result.allSucceeded, isTrue);
        expect(call.result, equals('result'));

        await operation.complete();
      });
    });

    group('waitForCompletion', () {
      test('executes work and returns result', () async {
        final operation = await client.createOperation();

        final result = await operation.waitForCompletion<int>(() async => 42);

        expect(result, equals(42));

        await operation.complete();
      });
    });

    group('leave', () {
      test('leaves session', () async {
        final initiator = await client.createOperation();

        // Create another client to join
        final client2 = RemoteLedgerClient(
          serverUrl: serverUrl,
          participantId: 'joiner',
        );
        final joiner = await client2.joinOperation(
          operationId: initiator.operationId,
        );

        // Joiner leaves first
        await joiner.leave();

        // Operation should still exist since initiator is still active
        final opFile = File(
          '${tempDir.path}/${initiator.operationId}.operation.json',
        );
        expect(opFile.existsSync(), isTrue);

        // Initiator completes the operation
        await initiator.complete();
        client2.dispose();
      });

      test(
        'throws with pending calls unless cancelPendingCalls=true',
        () async {
          final operation = await client.createOperation();

          final call = await operation.startCall<void>();

          expect(() => operation.leave(), throwsStateError);

          await call.end();
          await operation.complete();
        },
      );

      test('cancels pending calls when cancelPendingCalls=true', () async {
        final client2 = RemoteLedgerClient(
          serverUrl: serverUrl,
          participantId: 'keeper2',
        );
        final operation = await client2.createOperation();

        // Create a long-running call that checks cancellation
        final spawned = operation.spawnCall<int>(
          work: (call, _) async {
            // Simulate work that checks cancellation periodically
            for (int i = 0; i < 100; i++) {
              if (call.isCancelled) {
                throw StateError('Work cancelled');
              }
              await Future.delayed(const Duration(milliseconds: 100));
            }
            return 42;
          },
        );

        // Wait for call to be registered and work to start
        await Future.delayed(const Duration(milliseconds: 50));

        // Leave with cancel (initiator can leave with cancel)
        await operation.leave(cancelPendingCalls: true);

        // Spawned call should be cancelled
        expect(spawned.isCancelled, isTrue);

        // Wait for call to complete (work should detect cancellation and fail)
        await spawned.future;

        // Call should have failed because it detected cancellation
        expect(spawned.isFailed, isTrue);

        client2.dispose();
      });
    });

    group('log', () {
      test('writes to operation log file', () async {
        final operation = await client.createOperation();
        final operationId = operation.operationId;

        await operation.log('Test message 1');
        await operation.log('Test message 2', level: LogLevel.warning);

        final logFile = File('${tempDir.path}/$operationId.operation.log');
        expect(logFile.existsSync(), isTrue);

        final content = logFile.readAsStringSync();
        expect(content, contains('Test message 1'));
        expect(content, contains('Test message 2'));

        await operation.complete();
      });
    });

    group('complete', () {
      test('moves operation to backup', () async {
        final operation = await client.createOperation();
        final operationId = operation.operationId;

        await operation.complete();

        // Main file should be gone
        final opFile = File('${tempDir.path}/$operationId.operation.json');
        expect(opFile.existsSync(), isFalse);

        // Backup should exist
        final backupDir = Directory('${tempDir.path}/backup/$operationId');
        expect(backupDir.existsSync(), isTrue);
      });

      test('throws if not initiator', () async {
        final client1 = RemoteLedgerClient(
          serverUrl: serverUrl,
          participantId: 'initiator',
        );
        final op1 = await client1.createOperation();

        final client2 = RemoteLedgerClient(
          serverUrl: serverUrl,
          participantId: 'participant',
        );
        final op2 = await client2.joinOperation(operationId: op1.operationId);

        expect(() => op2.complete(), throwsStateError);

        await op1.complete();
        client1.dispose();
        client2.dispose();
      });
    });

    group('abort', () {
      test('setAbortFlag sets abort in file', () async {
        final operation = await client.createOperation();
        final operationId = operation.operationId;

        await operation.setAbortFlag(true);

        final opFile = File('${tempDir.path}/$operationId.operation.json');
        final content =
            jsonDecode(opFile.readAsStringSync()) as Map<String, dynamic>;
        expect(content['aborted'], isTrue);

        await operation.complete();
      });

      test('checkAbort returns correct state', () async {
        final operation = await client.createOperation();

        expect(await operation.checkAbort(), isFalse);

        await operation.setAbortFlag(true);

        expect(await operation.checkAbort(), isTrue);

        await operation.complete();
      });

      test('triggerAbort sets local isAborted', () async {
        final operation = await client.createOperation();

        expect(operation.isAborted, isFalse);

        operation.triggerAbort();

        expect(operation.isAborted, isTrue);

        await operation.complete();
      });

      test('onAbort completes when triggered', () async {
        final operation = await client.createOperation();

        var abortTriggered = false;
        unawaited(
          operation.onAbort.then((_) {
            abortTriggered = true;
          }),
        );

        operation.triggerAbort();
        await Future.delayed(const Duration(milliseconds: 10));

        expect(abortTriggered, isTrue);

        await operation.complete();
      });
    });

    group('heartbeat', () {
      test('startHeartbeat schedules heartbeats', () async {
        final operation = await client.createOperation();
        final operationId = operation.operationId;

        // Get initial heartbeat time
        var opFile = File('${tempDir.path}/$operationId.operation.json');
        var content =
            jsonDecode(opFile.readAsStringSync()) as Map<String, dynamic>;
        final initialHeartbeat = DateTime.parse(
          content['lastHeartbeat'] as String,
        );

        // Start heartbeat with short interval
        operation.startHeartbeat(
          interval: const Duration(milliseconds: 50),
          jitterMs: 10,
        );

        // Wait for heartbeat to occur
        await Future.delayed(const Duration(milliseconds: 200));

        operation.stopHeartbeat();

        // Verify heartbeat was updated
        content = jsonDecode(opFile.readAsStringSync()) as Map<String, dynamic>;
        final updatedHeartbeat = DateTime.parse(
          content['lastHeartbeat'] as String,
        );

        expect(updatedHeartbeat.isAfter(initialHeartbeat), isTrue);

        await operation.complete();
      });

      test('heartbeat() performs single heartbeat', () async {
        final operation = await client.createOperation();

        final result = await operation.heartbeat();

        expect(result, isNotNull);
        expect(result!.ledgerExists, isTrue);
        expect(result.heartbeatUpdated, isTrue);

        await operation.complete();
      });

      test('onSuccess callback is called', () async {
        final operation = await client.createOperation();

        HeartbeatResult? receivedResult;

        operation.startHeartbeat(
          interval: const Duration(milliseconds: 50),
          jitterMs: 10,
          onSuccess: (op, result) {
            receivedResult = result;
          },
        );

        await Future.delayed(const Duration(milliseconds: 150));
        operation.stopHeartbeat();

        expect(receivedResult, isNotNull);
        expect(receivedResult!.ledgerExists, isTrue);

        await operation.complete();
      });

      test('onError callback is called on abort', () async {
        final operation = await client.createOperation();

        HeartbeatError? receivedError;

        await operation.setAbortFlag(true);

        operation.startHeartbeat(
          interval: const Duration(milliseconds: 50),
          jitterMs: 10,
          onError: (op, error) {
            receivedError = error;
          },
        );

        await Future.delayed(const Duration(milliseconds: 150));
        operation.stopHeartbeat();

        expect(receivedError, isNotNull);
        expect(receivedError!.type, equals(HeartbeatErrorType.abortFlagSet));

        await operation.complete();
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // REMOTE LEDGER EXCEPTION TESTS
  // ═══════════════════════════════════════════════════════════════════

  group('RemoteLedgerException', () {
    test('stores message and statusCode', () {
      final exception = RemoteLedgerException('Test error', statusCode: 404);

      expect(exception.message, equals('Test error'));
      expect(exception.statusCode, equals(404));
    });

    test('toString includes message and status', () {
      final exception = RemoteLedgerException('Not found', statusCode: 404);

      expect(exception.toString(), contains('Not found'));
      expect(exception.toString(), contains('404'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // MULTI-CLIENT SCENARIO TESTS
  // ═══════════════════════════════════════════════════════════════════

  group('Multi-client scenarios', () {
    test('multiple clients can work on same operation', () async {
      final client1 = RemoteLedgerClient(
        serverUrl: serverUrl,
        participantId: 'client1',
      );
      final client2 = RemoteLedgerClient(
        serverUrl: serverUrl,
        participantId: 'client2',
      );

      // Client1 creates operation
      final op1 = await client1.createOperation(
        description: 'Multi-client test',
      );

      // Client2 joins
      final op2 = await client2.joinOperation(operationId: op1.operationId);

      // Both clients start calls
      final call1 = await op1.startCall<String>(description: 'Client1 work');
      final call2 = await op2.startCall<String>(description: 'Client2 work');

      // Verify both calls are tracked
      final opFile = File('${tempDir.path}/${op1.operationId}.operation.json');
      final content =
          jsonDecode(opFile.readAsStringSync()) as Map<String, dynamic>;
      final callFrames = content['callFrames'] as List;

      expect(callFrames.length, equals(2));

      // End calls
      await call1.end('done1');
      await call2.end('done2');

      // Leave and complete
      await op2.leave();
      await op1.complete();

      client1.dispose();
      client2.dispose();
    });

    test('spawned calls from multiple clients run concurrently', () async {
      final client1 = RemoteLedgerClient(
        serverUrl: serverUrl,
        participantId: 'spawner1',
      );
      final client2 = RemoteLedgerClient(
        serverUrl: serverUrl,
        participantId: 'spawner2',
      );

      final op1 = await client1.createOperation();
      final op2 = await client2.joinOperation(operationId: op1.operationId);

      // Spawn calls from both clients
      final spawned1 = op1.spawnCall<int>(
        work: (_, __) async {
          await Future.delayed(const Duration(milliseconds: 50));
          return 1;
        },
      );

      final spawned2 = op2.spawnCall<int>(
        work: (_, __) async {
          await Future.delayed(const Duration(milliseconds: 50));
          return 2;
        },
      );

      // Wait for both
      await Future.wait([spawned1.future, spawned2.future]);

      expect(spawned1.result, equals(1));
      expect(spawned2.result, equals(2));

      await op2.leave();
      await op1.complete();

      client1.dispose();
      client2.dispose();
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // API PARITY TESTS (Remote matches Local)
  // ═══════════════════════════════════════════════════════════════════

  group('API parity with local ledger', () {
    test('same startCall signature', () async {
      // This test verifies that RemoteOperation.startCall has the same
      // signature as Operation.startCall
      final client = RemoteLedgerClient(
        serverUrl: serverUrl,
        participantId: 'parity_test',
      );
      final remoteOp = await client.createOperation();

      // All these calls should compile - same as local
      final call1 = await remoteOp.startCall<int>();
      final call2 = await remoteOp.startCall<String>(description: 'test');
      final call3 = await remoteOp.startCall<void>(failOnCrash: false);
      final call4 = await remoteOp.startCall<bool>(
        callback: CallCallback<bool>(
          onCompletion: (result) async {},
          onCleanup: () async {},
        ),
      );

      await call1.end(42);
      await call2.end('done');
      await call3.end();
      await call4.end(true);
      await remoteOp.complete();
      client.dispose();
    });

    test('same spawnCall signature', () async {
      final client = RemoteLedgerClient(
        serverUrl: serverUrl,
        participantId: 'spawn_parity',
      );
      final remoteOp = await client.createOperation();

      // All these calls should compile - same as local
      final spawn1 = remoteOp.spawnCall<int>(work: (_, __) async => 1);
      final spawn2 = remoteOp.spawnCall<String>(
        work: (call, _) async => call.callId,
      );
      final spawn3 = remoteOp.spawnCall<void>(
        work: (_, __) async {},
        description: 'test',
        failOnCrash: false,
        callback: CallCallback<void>(
          onCompletion: (result) async {},
          onCleanup: () async {},
        ),
      );

      await Future.wait([spawn1.future, spawn2.future, spawn3.future]);
      await remoteOp.complete();
      client.dispose();
    });

    test('same sync signature', () async {
      final client = RemoteLedgerClient(
        serverUrl: serverUrl,
        participantId: 'sync_parity',
      );
      final remoteOp = await client.createOperation();

      final spawn1 = remoteOp.spawnCall<int>(work: (_, __) async => 1);
      final spawn2 = remoteOp.spawnCall<int>(work: (_, __) async => 2);

      // Same as local
      final result = await remoteOp.sync(
        [spawn1, spawn2],
        onOperationFailed: (info) async {},
        onCompletion: () async {},
      );

      expect(result.allSucceeded, isTrue);
      await remoteOp.complete();
      client.dispose();
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // NETWORK FAILURE TESTS
  // ═══════════════════════════════════════════════════════════════════

  group('Network Failure Scenarios', () {
    test('handles connection refused when server is down', () async {
      // Connect to a port where no server is running
      final badClient = RemoteLedgerClient(
        serverUrl: 'http://localhost:59999', // Unlikely to be used
        participantId: 'offline_client',
      );

      // Creating an operation should fail gracefully
      expect(
        () => badClient.createOperation(),
        throwsA(isA<SocketException>()),
      );

      badClient.dispose();
    });

    test('handles server stopping mid-operation', () async {
      // Start a dedicated server for this test
      final testDir = Directory.systemTemp.createTempSync('network_fail_test_');
      final testServer = await LedgerServer.start(
        basePath: testDir.path,
        port: 0,
      );
      final testUrl = 'http://localhost:${testServer.port}';

      final client = RemoteLedgerClient(
        serverUrl: testUrl,
        participantId: 'shutdown_client',
      );

      // Create an operation successfully
      final op = await client.createOperation();
      expect(op, isNotNull);

      // Stop the server
      await testServer.stop();

      // Try to complete - should fail with network error
      expect(
        () => op.complete(),
        throwsA(anyOf(isA<SocketException>(), isA<HttpException>())),
      );

      client.dispose();
      if (testDir.existsSync()) {
        testDir.deleteSync(recursive: true);
      }
    });

    test('validates operationId in joinOperation', () async {
      final client = RemoteLedgerClient(
        serverUrl: serverUrl,
        participantId: 'validation_client',
      );

      // Path traversal attempts should be rejected
      expect(
        () => client.joinOperation(operationId: '../../../etc/passwd'),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => client.joinOperation(operationId: 'test/with/slashes'),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => client.joinOperation(operationId: ''),
        throwsA(isA<ArgumentError>()),
      );

      client.dispose();
    });
  });
}
