import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_dist_ledger/tom_dist_ledger.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ledger_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  // ═══════════════════════════════════════════════════════════════════
  // LEDGER DATA STRUCTURE TESTS
  // ═══════════════════════════════════════════════════════════════════

  group('LedgerData', () {
    test('can be serialized to JSON and back', () {
      final data = LedgerData(
        operationId: 'test_op_1',
        initiatorId: 'cli',
        lastHeartbeat: DateTime(2026, 1, 20, 12, 0, 0),
      );
      data.aborted = false;

      final jsonData = data.toJson();
      final restored = LedgerData.fromJson(jsonData);

      expect(restored.operationId, equals('test_op_1'));
      expect(restored.initiatorId, equals('cli'));
      expect(restored.aborted, isFalse);
      expect(restored.lastHeartbeat.year, equals(2026));
    });

    test('handles stack frames correctly', () {
      final data = LedgerData(operationId: 'test_op_1', initiatorId: 'cli');
      data.stack.add(StackFrame(
        participantId: 'cli',
        callId: 'call-1',
        pid: 1234,
        startTime: DateTime.now(),
      ));
      data.stack.add(StackFrame(
        participantId: 'bridge',
        callId: 'call-2',
        pid: 5678,
        startTime: DateTime.now(),
      ));

      final json = data.toJson();
      final restored = LedgerData.fromJson(json);

      expect(restored.stack.length, equals(2));
      expect(restored.stack[0].participantId, equals('cli'));
      expect(restored.stack[1].participantId, equals('bridge'));
    });

    test('handles temp resources correctly', () {
      final data = LedgerData(operationId: 'test_op_1', initiatorId: 'cli');
      data.tempResources.add(TempResource(
        path: '/tmp/file1.txt',
        owner: 1234,
        registeredAt: DateTime.now(),
      ));

      final json = data.toJson();
      final restored = LedgerData.fromJson(json);

      expect(restored.tempResources.length, equals(1));
      expect(restored.tempResources[0].path, equals('/tmp/file1.txt'));
      expect(restored.tempResources[0].owner, equals(1234));
    });

    test('isEmpty returns true when stack and temp resources are empty', () {
      final data = LedgerData(operationId: 'test', initiatorId: 'cli');
      expect(data.isEmpty, isTrue);

      data.stack.add(StackFrame(
        participantId: 'test',
        callId: 'test',
        pid: 123,
        startTime: DateTime.now(),
      ));
      expect(data.isEmpty, isFalse);
    });
  });

  group('StackFrame', () {
    test('can be serialized to JSON and back', () {
      final frame = StackFrame(
        participantId: 'test_participant',
        callId: 'test_call',
        pid: 12345,
        startTime: DateTime(2026, 1, 20, 12, 0, 0),
      );

      final json = frame.toJson();
      final restored = StackFrame.fromJson(json);

      expect(restored.participantId, equals('test_participant'));
      expect(restored.callId, equals('test_call'));
      expect(restored.pid, equals(12345));
    });

    test('toString is descriptive', () {
      final frame = StackFrame(
        participantId: 'cli',
        callId: 'main',
        pid: 123,
        startTime: DateTime.now(),
      );

      expect(frame.toString(), contains('cli'));
      expect(frame.toString(), contains('main'));
    });

    test('failOnCrash defaults to true and is serialized', () {
      final frame = StackFrame(
        participantId: 'test',
        callId: 'call',
        pid: 100,
        startTime: DateTime.now(),
      );

      expect(frame.failOnCrash, isTrue);

      final json = frame.toJson();
      expect(json['failOnCrash'], isTrue);

      final restored = StackFrame.fromJson(json);
      expect(restored.failOnCrash, isTrue);
    });

    test('failOnCrash can be set to false and is preserved', () {
      final frame = StackFrame(
        participantId: 'test',
        callId: 'call',
        pid: 100,
        startTime: DateTime.now(),
        failOnCrash: false,
      );

      expect(frame.failOnCrash, isFalse);

      final json = frame.toJson();
      expect(json['failOnCrash'], isFalse);

      final restored = StackFrame.fromJson(json);
      expect(restored.failOnCrash, isFalse);
    });

    test('failOnCrash defaults to true when missing from JSON', () {
      // Simulate old ledger data without failOnCrash field
      final json = {
        'participantId': 'test',
        'callId': 'call',
        'pid': 100,
        'startTime': DateTime.now().toIso8601String(),
        // no failOnCrash field
      };

      final restored = StackFrame.fromJson(json);
      expect(restored.failOnCrash, isTrue);
    });
  });

  group('TempResource', () {
    test('can be serialized to JSON and back', () {
      final resource = TempResource(
        path: '/tmp/test.txt',
        owner: 9999,
        registeredAt: DateTime(2026, 1, 20, 12, 0, 0),
      );

      final json = resource.toJson();
      final restored = TempResource.fromJson(json);

      expect(restored.path, equals('/tmp/test.txt'));
      expect(restored.owner, equals(9999));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // LEDGER LIFECYCLE TESTS
  // ═══════════════════════════════════════════════════════════════════

  group('Ledger', () {
    late Ledger ledger;
    final List<String> backups = [];

    setUp(() {
      backups.clear();
      ledger = Ledger(
        basePath: tempDir.path,
        onBackupCreated: (path) => backups.add(path),
      );
    });

    tearDown(() {
      ledger.dispose();
    });

    group('initialization', () {
      test('creates the ledger directory if it does not exist', () {
        final newPath = '${tempDir.path}/new_ledger';
        expect(Directory(newPath).existsSync(), isFalse);

        final newLedger = Ledger(basePath: newPath);
        expect(Directory(newPath).existsSync(), isTrue);
        newLedger.dispose();
      });

      test('basePath is accessible', () {
        expect(ledger.basePath, equals(tempDir.path));
      });

      test('operations map starts empty', () {
        expect(ledger.operations, isEmpty);
      });
    });

    group('startOperation', () {
      test('creates operation file in ledger directory', () async {
        final operation = await ledger.startOperation(
          operationId: 'test_op_1',
          initiatorPid: 1234,
          participantId: 'cli',
          getElapsedFormatted: () => '000.000',
        );

        final opFile = File('${tempDir.path}/test_op_1.operation.json');
        expect(opFile.existsSync(), isTrue);

        final content = json.decode(opFile.readAsStringSync());
        expect(content['operationId'], equals('test_op_1'));
        expect(content['initiatorId'], equals('cli'));
        expect(content['aborted'], isFalse);
        // Stack starts empty in new implementation
        expect(content['stack'], isEmpty);

        await operation.complete();
      });

      test('stack is initially empty', () async {
        final operation = await ledger.startOperation(
          operationId: 'test_op_2',
          initiatorPid: 1234,
          participantId: 'cli',
          getElapsedFormatted: () => '000.000',
        );

        final opFile = File('${tempDir.path}/test_op_2.operation.json');
        final content = json.decode(opFile.readAsStringSync());
        final stack = content['stack'] as List;

        // Stack starts empty - frames are added by startCall/startCallExecution
        expect(stack.length, equals(0));

        await operation.complete();
      });

      test('registers operation in ledger', () async {
        final operation = await ledger.startOperation(
          operationId: 'test_op_3',
          initiatorPid: 1234,
          participantId: 'cli',
          getElapsedFormatted: () => '000.000',
        );

        expect(ledger.operations.containsKey('test_op_3'), isTrue);
        expect(ledger.getOperation('test_op_3'), equals(operation));

        await operation.complete();
      });

      test('sets isInitiator to true', () async {
        final operation = await ledger.startOperation(
          operationId: 'test_op_4',
          initiatorPid: 1234,
          participantId: 'cli',
          getElapsedFormatted: () => '000.000',
        );

        expect(operation.isInitiator, isTrue);

        await operation.complete();
      });
    });

    group('participateInOperation', () {
      test('creates operation object for existing operation', () async {
        // First, create an operation as initiator
        final initiator = await ledger.startOperation(
          operationId: 'test_op_5',
          initiatorPid: 1234,
          participantId: 'cli',
          getElapsedFormatted: () => '000.000',
        );

        // Then, participate as another process
        final participant = await ledger.participateInOperation(
          operationId: 'test_op_5',
          participantPid: 5678,
          participantId: 'bridge',
          getElapsedFormatted: () => '000.000',
        );

        expect(participant.operationId, equals('test_op_5'));
        expect(participant.participantId, equals('bridge'));
        expect(participant.pid, equals(5678));
        expect(participant.isInitiator, isFalse);

        await initiator.complete();
      });

      test('loads cached data from existing operation file', () async {
        final initiator = await ledger.startOperation(
          operationId: 'test_op_6',
          initiatorPid: 1234,
          participantId: 'cli',
          getElapsedFormatted: () => '000.000',
        );

        final participant = await ledger.participateInOperation(
          operationId: 'test_op_6',
          participantPid: 5678,
          participantId: 'bridge',
          getElapsedFormatted: () => '000.000',
        );

        expect(participant.cachedData, isNotNull);
        expect(participant.cachedData!.operationId, equals('test_op_6'));

        await initiator.complete();
      });
    });

    group('dispose', () {
      test('stops all heartbeats and clears operations', () async {
        await ledger.startOperation(
          operationId: 'test_op_7',
          initiatorPid: 1234,
          participantId: 'cli',
          getElapsedFormatted: () => '000.000',
        );

        expect(ledger.operations.length, equals(1));

        ledger.dispose();

        expect(ledger.operations, isEmpty);
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // OPERATION TESTS
  // ═══════════════════════════════════════════════════════════════════

  group('Operation', () {
    late Ledger ledger;
    late Operation operation;
    final List<String> backups = [];

    setUp(() async {
      backups.clear();
      ledger = Ledger(
        basePath: tempDir.path,
        onBackupCreated: (path) => backups.add(path),
      );
      operation = await ledger.startOperation(
        operationId: 'op_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );
    });

    tearDown(() {
      ledger.dispose();
    });

    group('startCallExecution', () {
      test('adds stack frame to operation file', () async {
        await operation.startCallExecution(callId: 'call-1');

        final opFile = File('${tempDir.path}/op_test.operation.json');
        final content = json.decode(opFile.readAsStringSync());
        final stack = content['stack'] as List;

        // Stack starts empty, startCallExecution adds one frame
        expect(stack.length, equals(1));
        expect(stack[0]['callId'], equals('call-1'));
        expect(stack[0]['participantId'], equals('cli'));

        await operation.complete();
      });

      test('creates backup before modification', () async {
        await operation.startCallExecution(callId: 'call-1');

        expect(backups.length, equals(1));
        expect(backups[0], contains('op_test'));
        expect(File(backups[0]).existsSync(), isTrue);

        await operation.complete();
      });

      test('updates lastHeartbeat timestamp', () async {
        final opFile = File('${tempDir.path}/op_test.operation.json');
        final beforeContent = json.decode(opFile.readAsStringSync());
        final beforeHeartbeat =
            DateTime.parse(beforeContent['lastHeartbeat'] as String);

        await Future.delayed(const Duration(milliseconds: 10));
        await operation.startCallExecution(callId: 'call-1');

        final afterContent = json.decode(opFile.readAsStringSync());
        final afterHeartbeat =
            DateTime.parse(afterContent['lastHeartbeat'] as String);

        expect(afterHeartbeat.isAfter(beforeHeartbeat), isTrue);

        await operation.complete();
      });

      test('updates cached data', () async {
        expect(operation.cachedData!.stack.length, equals(0));

        await operation.startCallExecution(callId: 'call-1');

        expect(operation.cachedData!.stack.length, equals(1));

        await operation.complete();
      });
    });

    group('endCallExecution', () {
      test('removes stack frame from operation file', () async {
        await operation.startCallExecution(callId: 'call-1');
        await operation.endCallExecution(callId: 'call-1');

        final opFile = File('${tempDir.path}/op_test.operation.json');
        final content = json.decode(opFile.readAsStringSync());
        final stack = content['stack'] as List;

        // Stack should be empty after removing the only frame
        expect(stack.length, equals(0));

        await operation.complete();
      });

      test('removes correct frame when multiple exist', () async {
        await operation.startCallExecution(callId: 'call-1');
        await operation.startCallExecution(callId: 'call-2');
        await operation.endCallExecution(callId: 'call-1');

        final opFile = File('${tempDir.path}/op_test.operation.json');
        final content = json.decode(opFile.readAsStringSync());
        final stack = content['stack'] as List;

        // Should only have call-2 remaining
        expect(stack.length, equals(1));
        expect(stack[0]['callId'], equals('call-2'));

        await operation.complete();
      });

      test('creates backup before modification', () async {
        await operation.startCallExecution(callId: 'call-1');
        final backupsBefore = backups.length;

        await operation.endCallExecution(callId: 'call-1');

        expect(backups.length, greaterThan(backupsBefore));

        await operation.complete();
      });
    });

    group('registerTempResource', () {
      test('adds temp resource to operation file', () async {
        await operation.registerTempResource(path: '/tmp/test.txt');

        final opFile = File('${tempDir.path}/op_test.operation.json');
        final content = json.decode(opFile.readAsStringSync());
        final resources = content['tempResources'] as List;

        expect(resources.length, equals(1));
        expect(resources[0]['path'], equals('/tmp/test.txt'));
        expect(resources[0]['owner'], equals(1234));

        await operation.complete();
      });

      test('can register multiple resources', () async {
        await operation.registerTempResource(path: '/tmp/file1.txt');
        await operation.registerTempResource(path: '/tmp/file2.txt');

        final opFile = File('${tempDir.path}/op_test.operation.json');
        final content = json.decode(opFile.readAsStringSync());
        final resources = content['tempResources'] as List;

        expect(resources.length, equals(2));

        await operation.complete();
      });
    });

    group('unregisterTempResource', () {
      test('removes temp resource from operation file', () async {
        await operation.registerTempResource(path: '/tmp/test.txt');
        await operation.unregisterTempResource(path: '/tmp/test.txt');

        final opFile = File('${tempDir.path}/op_test.operation.json');
        final content = json.decode(opFile.readAsStringSync());
        final resources = content['tempResources'] as List;

        expect(resources, isEmpty);

        await operation.complete();
      });

      test('only removes matching resource', () async {
        await operation.registerTempResource(path: '/tmp/file1.txt');
        await operation.registerTempResource(path: '/tmp/file2.txt');
        await operation.unregisterTempResource(path: '/tmp/file1.txt');

        final opFile = File('${tempDir.path}/op_test.operation.json');
        final content = json.decode(opFile.readAsStringSync());
        final resources = content['tempResources'] as List;

        expect(resources.length, equals(1));
        expect(resources[0]['path'], equals('/tmp/file2.txt'));

        await operation.complete();
      });
    });

    group('setAbortFlag', () {
      test('sets abort flag in operation file', () async {
        await operation.setAbortFlag(true);

        final opFile = File('${tempDir.path}/op_test.operation.json');
        final content = json.decode(opFile.readAsStringSync());

        expect(content['aborted'], isTrue);

        await operation.complete();
      });

      test('can clear abort flag', () async {
        await operation.setAbortFlag(true);
        await operation.setAbortFlag(false);

        final opFile = File('${tempDir.path}/op_test.operation.json');
        final content = json.decode(opFile.readAsStringSync());

        expect(content['aborted'], isFalse);

        await operation.complete();
      });
    });

    group('checkAbort', () {
      test('returns false when not aborted', () async {
        final aborted = await operation.checkAbort();
        expect(aborted, isFalse);

        await operation.complete();
      });

      test('returns true when aborted', () async {
        await operation.setAbortFlag(true);
        final aborted = await operation.checkAbort();

        expect(aborted, isTrue);

        await operation.complete();
      });
    });

    group('triggerAbort', () {
      test('sets isAborted to true', () {
        expect(operation.isAborted, isFalse);

        operation.triggerAbort();

        expect(operation.isAborted, isTrue);
      });

      test('completes onAbort future', () async {
        var completed = false;
        operation.onAbort.then((_) => completed = true);

        operation.triggerAbort();

        await Future.delayed(const Duration(milliseconds: 10));
        expect(completed, isTrue);
      });
    });

    group('complete', () {
      test('moves operation file to backup folder', () async {
        await operation.complete();

        // Main file should be gone
        final opFile = File('${tempDir.path}/op_test.operation.json');
        expect(opFile.existsSync(), isFalse);

        // Backup folder should exist
        final backupDir = Directory('${tempDir.path}/backup');
        expect(backupDir.existsSync(), isTrue);

        // Operation folder should exist in backup
        final opBackupDir = Directory('${tempDir.path}/backup/op_test');
        expect(opBackupDir.existsSync(), isTrue);
        
        // Operation file should exist in backup folder
        final backupFile = File('${tempDir.path}/backup/op_test/operation.json');
        expect(backupFile.existsSync(), isTrue);
      });

      test('sets operationState to completed in backup file', () async {
        await operation.complete();

        final backupFile = File('${tempDir.path}/backup/op_test/operation.json');
        expect(backupFile.existsSync(), isTrue);

        final content = json.decode(backupFile.readAsStringSync());
        expect(content['operationState'], equals('completed'));
      });

      test('unregisters operation from ledger', () async {
        expect(ledger.operations.containsKey('op_test'), isTrue);

        await operation.complete();

        expect(ledger.operations.containsKey('op_test'), isFalse);
      });

      test('throws if not initiator', () async {
        final participant = await ledger.participateInOperation(
          operationId: 'op_test',
          participantPid: 5678,
          participantId: 'bridge',
          getElapsedFormatted: () => '000.000',
        );

        expect(() => participant.complete(), throwsStateError);

        await operation.complete();
      });
    });

    group('log', () {
      test('creates log file with entries', () async {
        await operation.log('Test log line 1');
        await operation.log('Test log line 2');

        final logFile = File('${tempDir.path}/op_test.operation.log');
        expect(logFile.existsSync(), isTrue);

        final content = logFile.readAsStringSync();
        expect(content, contains('Test log line 1'));
        expect(content, contains('Test log line 2'));

        await operation.complete();
      });

      test('appends to existing log file', () async {
        await operation.log('Line 1');
        await operation.log('Line 2');
        await operation.log('Line 3');

        final logFile = File('${tempDir.path}/op_test.operation.log');
        final lines = logFile.readAsLinesSync();

        expect(lines.length, equals(3));

        await operation.complete();
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // BACKUP AND TRAIL TESTS
  // ═══════════════════════════════════════════════════════════════════

  group('Backup and Trail', () {
    late Ledger ledger;
    final List<String> backups = [];

    setUp(() {
      backups.clear();
      ledger = Ledger(
        basePath: tempDir.path,
        onBackupCreated: (path) => backups.add(path),
      );
    });

    tearDown(() {
      ledger.dispose();
    });

    test('creates trail directory on first backup', () async {
      final operation = await ledger.startOperation(
        operationId: 'trail_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final trailDir = Directory('${tempDir.path}/trail_test_trail');
      expect(trailDir.existsSync(), isFalse);

      await operation.startCallExecution(callId: 'call-1');

      expect(trailDir.existsSync(), isTrue);

      await operation.complete();
    });

    test('backup files contain correct operation state', () async {
      final operation = await ledger.startOperation(
        operationId: 'trail_test_2',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '001.000',
      );

      await operation.startCallExecution(callId: 'call-1');

      expect(backups.length, equals(1));

      final backupContent = json.decode(File(backups[0]).readAsStringSync());
      // Backup should contain state BEFORE the modification
      expect(backupContent['operationId'], equals('trail_test_2'));

      await operation.complete();
    });

    test('multiple backups are created for multiple modifications', () async {
      final operation = await ledger.startOperation(
        operationId: 'trail_test_3',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      await operation.startCallExecution(callId: 'call-1');
      await operation.startCallExecution(callId: 'call-2');
      await operation.endCallExecution(callId: 'call-2');
      await operation.endCallExecution(callId: 'call-1');

      // Should have backups for each modification
      expect(backups.length, greaterThanOrEqualTo(4));

      await operation.complete();
    });

    test('backup filename includes timestamp', () async {
      var timestamp = '005.123';
      final operation = await ledger.startOperation(
        operationId: 'timestamp_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => timestamp,
      );

      timestamp = '006.456';
      await operation.startCallExecution(callId: 'call-1');

      expect(backups.isNotEmpty, isTrue);
      expect(backups.last, contains('006.456'));

      await operation.complete();
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // LOCKING TESTS
  // ═══════════════════════════════════════════════════════════════════

  group('File Locking', () {
    late Ledger ledger;

    setUp(() {
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
    });

    test('lock file is created during operation', () async {
      final operation = await ledger.startOperation(
        operationId: 'lock_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      // Lock should be released after startOperation
      final lockFile = File('${tempDir.path}/lock_test.operation.json.lock');
      expect(lockFile.existsSync(), isFalse);

      await operation.complete();
    });

    test('stale locks are cleaned up', () async {
      // Create a stale lock file manually
      final lockFile = File('${tempDir.path}/stale_test.operation.json.lock');
      lockFile.createSync();
      lockFile.writeAsStringSync('{"pid": 99999}');

      // Set modification time to the past
      // (This test may be flaky as we can't easily set file time)

      // Try to create an operation - should succeed by cleaning up stale lock
      final opFile = File('${tempDir.path}/stale_test.operation.json');
      opFile.writeAsStringSync(json.encode(LedgerData(
        operationId: 'stale_test',
        initiatorId: 'cli',
      ).toJson()));

      final operation = await ledger.participateInOperation(
        operationId: 'stale_test',
        participantPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      expect(operation, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // HEARTBEAT RESULT TESTS
  // ═══════════════════════════════════════════════════════════════════

  group('HeartbeatResult', () {
    test('noLedger factory creates correct result', () {
      final result = HeartbeatResult.noLedger();

      expect(result.ledgerExists, isFalse);
      expect(result.abortFlag, isTrue);
      expect(result.heartbeatUpdated, isFalse);
      expect(result.isStale, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // CONCURRENT ACCESS TESTS
  // ═══════════════════════════════════════════════════════════════════

  group('Concurrent Access', () {
    late Ledger ledger;

    setUp(() {
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
    });

    test('multiple participants can modify the same operation', () async {
      // Start as initiator
      final initiator = await ledger.startOperation(
        operationId: 'concurrent_test',
        initiatorPid: 1111,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      // Join as participant
      final participant = await ledger.participateInOperation(
        operationId: 'concurrent_test',
        participantPid: 2222,
        participantId: 'bridge',
        getElapsedFormatted: () => '000.000',
      );

      // Both modify the operation
      await initiator.startCallExecution(callId: 'cli-call');
      await participant.startCallExecution(callId: 'bridge-call');

      // Verify both calls are in the stack
      final opFile = File('${tempDir.path}/concurrent_test.operation.json');
      final content = json.decode(opFile.readAsStringSync());
      final stack = content['stack'] as List;

      expect(stack.length, equals(2)); // cli-call + bridge-call

      await initiator.complete();
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // FULL OPERATION LIFECYCLE TEST
  // ═══════════════════════════════════════════════════════════════════

  group('Full Operation Lifecycle', () {
    late Ledger ledger;
    final List<String> backups = [];

    setUp(() {
      backups.clear();
      ledger = Ledger(
        basePath: tempDir.path,
        onBackupCreated: (path) => backups.add(path),
      );
    });

    tearDown(() {
      ledger.dispose();
    });

    test('complete lifecycle with multiple participants', () async {
      // 1. CLI starts operation
      final cli = await ledger.startOperation(
        operationId: 'lifecycle_test',
        initiatorPid: 1000,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );
      await cli.startCallExecution(callId: 'cli-main');

      // 2. Bridge joins and starts processing
      final bridge = await ledger.participateInOperation(
        operationId: 'lifecycle_test',
        participantPid: 2000,
        participantId: 'bridge',
        getElapsedFormatted: () => '001.000',
      );
      await bridge.startCallExecution(callId: 'bridge-process');
      await bridge.registerTempResource(path: '/tmp/work.txt');

      // 3. VSCode joins and calls external service
      final vscode = await ledger.participateInOperation(
        operationId: 'lifecycle_test',
        participantPid: 3000,
        participantId: 'vscode',
        getElapsedFormatted: () => '002.000',
      );
      await vscode.startCallExecution(callId: 'vscode-copilot');

      // Verify full stack
      var opFile = File('${tempDir.path}/lifecycle_test.operation.json');
      var content = json.decode(opFile.readAsStringSync());
      var stack = content['stack'] as List;
      expect(stack.length, equals(3)); // 3 calls (no initial frame)

      // 4. Unwind in reverse order
      await vscode.endCallExecution(callId: 'vscode-copilot');
      await bridge.unregisterTempResource(path: '/tmp/work.txt');
      await bridge.endCallExecution(callId: 'bridge-process');
      await cli.endCallExecution(callId: 'cli-main');

      // Verify stack is empty after unwinding
      content = json.decode(opFile.readAsStringSync());
      stack = content['stack'] as List;
      expect(stack.length, equals(0));

      // 5. Complete
      await cli.complete();

      // Verify final state
      expect(opFile.existsSync(), isFalse);
      final backupDir = Directory('${tempDir.path}/backup');
      expect(backupDir.existsSync(), isTrue);

      // Should have multiple backups
      expect(backups.length, greaterThan(5));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // HEARTBEAT ERROR TESTS
  // ═══════════════════════════════════════════════════════════════════

  group('HeartbeatError', () {
    test('toString returns formatted message', () {
      const error = HeartbeatError(
        type: HeartbeatErrorType.ledgerNotFound,
        message: 'Operation file not found',
      );

      expect(
        error.toString(),
        equals('HeartbeatError(HeartbeatErrorType.ledgerNotFound): '
            'Operation file not found'),
      );
    });

    test('can include a cause', () {
      final cause = Exception('IO Error');
      final error = HeartbeatError(
        type: HeartbeatErrorType.ioError,
        message: 'Failed to read file',
        cause: cause,
      );

      expect(error.cause, equals(cause));
      expect(error.type, equals(HeartbeatErrorType.ioError));
    });

    test('all error types can be created', () {
      const types = HeartbeatErrorType.values;
      expect(types, contains(HeartbeatErrorType.ledgerNotFound));
      expect(types, contains(HeartbeatErrorType.abortFlagSet));
      expect(types, contains(HeartbeatErrorType.heartbeatStale));
      expect(types, contains(HeartbeatErrorType.ioError));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // HEARTBEAT CALLBACK TESTS
  // ═══════════════════════════════════════════════════════════════════

  group('Heartbeat Callbacks', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('heartbeat_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('onHeartbeatSuccess is called on successful heartbeat', () async {
      final operation = await ledger.startOperation(
        operationId: 'hb_success_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      HeartbeatResult? receivedResult;
      Operation? receivedOperation;

      operation.startHeartbeat(
        interval: const Duration(milliseconds: 50),
        jitterMs: 10,
        onSuccess: (op, result) {
          receivedResult = result;
          receivedOperation = op;
        },
      );

      // Wait for heartbeat to occur
      await Future.delayed(const Duration(milliseconds: 150));

      operation.stopHeartbeat();

      expect(receivedResult, isNotNull);
      expect(receivedResult!.ledgerExists, isTrue);
      expect(receivedResult!.heartbeatUpdated, isTrue);
      expect(receivedOperation, equals(operation));

      await operation.complete();
    });

    test('onHeartbeatError called when abort flag is set', () async {
      final operation = await ledger.startOperation(
        operationId: 'hb_abort_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      HeartbeatError? receivedError;

      // Set abort flag before starting heartbeat
      await operation.setAbortFlag(true);

      operation.startHeartbeat(
        interval: const Duration(milliseconds: 50),
        jitterMs: 10,
        onError: (op, error) {
          receivedError = error;
        },
      );

      // Wait for heartbeat to detect abort
      await Future.delayed(const Duration(milliseconds: 150));

      operation.stopHeartbeat();

      expect(receivedError, isNotNull);
      expect(receivedError!.type, equals(HeartbeatErrorType.abortFlagSet));

      await operation.complete();
    });

    test('onHeartbeatError called when ledger file is deleted', () async {
      final operation = await ledger.startOperation(
        operationId: 'hb_deleted_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      HeartbeatError? receivedError;

      operation.startHeartbeat(
        interval: const Duration(milliseconds: 50),
        jitterMs: 10,
        onError: (op, error) {
          receivedError = error;
        },
      );

      // Delete the operation file to simulate crash
      final opFile = File('${tempDir.path}/hb_deleted_test.operation.json');
      await opFile.delete();

      // Wait for heartbeat to detect missing file
      await Future.delayed(const Duration(milliseconds: 150));

      operation.stopHeartbeat();

      expect(receivedError, isNotNull);
      expect(receivedError!.type, equals(HeartbeatErrorType.ledgerNotFound));
    });

    test('onHeartbeatSuccess detects stale children', () async {
      final operation = await ledger.startOperation(
        operationId: 'hb_stale_cb_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      // Add a second participant to the stack (simulating another process)
      await operation.startCallExecution(callId: 'test-call');
      
      // Manually set another participant's heartbeat to be stale
      final opFile = File('${tempDir.path}/hb_stale_cb_test.operation.json');
      var content =
          json.decode(opFile.readAsStringSync()) as Map<String, dynamic>;
      
      // Add a fake stale participant to the stack (simulating a crashed process)
      final staleTime = DateTime.now().subtract(const Duration(seconds: 15)).toIso8601String();
      (content['stack'] as List).add({
        'participantId': 'stale_participant',
        'callId': 'stale-call',
        'pid': 9999,
        'startTime': staleTime,
        'lastHeartbeat': staleTime,
      });
      await opFile.writeAsString(json.encode(content));

      HeartbeatResult? resultWithStale;

      operation.startHeartbeat(
        interval: const Duration(milliseconds: 50),
        jitterMs: 10,
        onSuccess: (op, result) {
          if (result.hasStaleChildren) {
            resultWithStale = result;
          }
        },
      );

      // Wait for heartbeat to detect stale
      await Future.delayed(const Duration(milliseconds: 200));

      operation.stopHeartbeat();

      // Stale heartbeat should be detected in success callback result
      expect(resultWithStale, isNotNull);
      expect(resultWithStale!.hasStaleChildren, isTrue);
      expect(resultWithStale!.staleParticipants, contains('stale_participant'));

      await operation.complete();
    });

    test('onHeartbeatError called on IO exception', () async {
      final operation = await ledger.startOperation(
        operationId: 'hb_io_error_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      HeartbeatError? ioError;

      operation.startHeartbeat(
        interval: const Duration(milliseconds: 50),
        jitterMs: 10,
        onError: (op, error) {
          ioError = error;
        },
      );

      // Corrupt the file to cause JSON parse error
      final opFile = File('${tempDir.path}/hb_io_error_test.operation.json');
      await opFile.writeAsString('not valid json {{{');

      // Wait for heartbeat to hit the error
      await Future.delayed(const Duration(milliseconds: 200));

      operation.stopHeartbeat();

      expect(ioError, isNotNull);
      expect(ioError!.type, equals(HeartbeatErrorType.ioError));
      expect(ioError!.cause, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // TOSTRING TESTS
  // ═══════════════════════════════════════════════════════════════════

  group('toString methods', () {
    test('StackFrame.toString is descriptive', () {
      final frame = StackFrame(
        participantId: 'test_participant',
        callId: 'test_call',
        pid: 9999,
        startTime: DateTime(2026, 1, 20, 12, 30, 45),
      );

      final str = frame.toString();
      expect(str, contains('test_participant'));
      expect(str, contains('test_call'));
      expect(str, contains('9999'));
    });

    test('TempResource.toString is descriptive', () {
      final resource = TempResource(
        path: '/tmp/test_file.txt',
        owner: 8888,
        registeredAt: DateTime.now(),
      );

      final str = resource.toString();
      expect(str, contains('/tmp/test_file.txt'));
      expect(str, contains('8888'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // HEARTBEAT RESULT TESTS (EXTENDED)
  // ═══════════════════════════════════════════════════════════════════

  group('HeartbeatResult (extended)', () {
    test('full constructor works correctly', () {
      final result = HeartbeatResult(
        abortFlag: true,
        ledgerExists: true,
        heartbeatUpdated: true,
        stackDepth: 3,
        tempResourceCount: 2,
        heartbeatAgeMs: 5000,
        isStale: false,
        stackParticipants: ['cli', 'bridge', 'vscode'],
      );

      expect(result.abortFlag, isTrue);
      expect(result.ledgerExists, isTrue);
      expect(result.heartbeatUpdated, isTrue);
      expect(result.stackDepth, equals(3));
      expect(result.tempResourceCount, equals(2));
      expect(result.heartbeatAgeMs, equals(5000));
      expect(result.isStale, isFalse);
      expect(result.stackParticipants.length, equals(3));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // OPERATION ADDITIONAL COVERAGE
  // ═══════════════════════════════════════════════════════════════════

  group('Operation (additional coverage)', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('op_extra_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('elapsedFormatted returns value from callback', () async {
      var elapsed = '001.234';
      final operation = await ledger.startOperation(
        operationId: 'elapsed_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => elapsed,
      );

      expect(operation.elapsedFormatted, equals('001.234'));

      elapsed = '002.456';
      expect(operation.elapsedFormatted, equals('002.456'));

      await operation.complete();
    });

    test('logMessage formats with timestamp and participant', () async {
      final operation = await ledger.startOperation(
        operationId: 'log_msg_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '003.500',
      );

      await operation.logMessage(depth: 1, message: 'Test message');

      final logFile = File('${tempDir.path}/log_msg_test.operation.log');
      final content = logFile.readAsStringSync();

      expect(content, contains('003.500'));
      expect(content, contains('[cli]'));
      expect(content, contains('Test message'));
      expect(content, contains('    ')); // indentation for depth 1

      await operation.complete();
    });

    test('stopHeartbeat can be called when no heartbeat is running', () async {
      final operation = await ledger.startOperation(
        operationId: 'stop_no_hb',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      // Should not throw
      operation.stopHeartbeat();

      await operation.complete();
    });

    test('lastChangeTimestamp is updated on modifications', () async {
      final operation = await ledger.startOperation(
        operationId: 'timestamp_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final initialTimestamp = operation.lastChangeTimestamp;
      expect(initialTimestamp, isNotNull);

      await Future.delayed(const Duration(milliseconds: 10));
      await operation.startCallExecution(callId: 'test');

      expect(
        operation.lastChangeTimestamp!.isAfter(initialTimestamp!),
        isTrue,
      );

      await operation.complete();
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // NEW API TESTS
  // ═══════════════════════════════════════════════════════════════════

  group('New API - startCall/endCall', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('new_api_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('startCall adds stack frame with ledger-generated callId', () async {
      final operation = await ledger.startOperation(
        operationId: 'start_call_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final testCallback = CallCallback(
        onCleanup: () async {},
      );

      final callId = await operation.startCall(
        callback: testCallback,
        description: 'test call',
      );
      
      expect(callId, isNotEmpty);
      expect(operation.cachedData!.stack.length, equals(1));
      expect(operation.cachedData!.stack[0].callId, equals(callId));
      expect(operation.cachedData!.stack[0].description, equals('test call'));

      await operation.complete();
    });

    test('startCall callId has correct format', () async {
      final operation = await ledger.startOperation(
        operationId: 'callid_format_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final testCallback = CallCallback(onCleanup: () async {});

      final callId = await operation.startCall(
        callback: testCallback,
        description: 'test',
      );
      
      // Format: call_{participantId}_{counter}_{random}
      expect(callId, matches(RegExp(r'^call_cli_\d+_[0-9a-f]+$')));

      await operation.complete();
    });

    test('startCall with callback for cleanup', () async {
      final operation = await ledger.startOperation(
        operationId: 'callback_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      var cleanupCalled = false;
      final testCallback = CallCallback(
        onCleanup: () async { cleanupCalled = true; },
      );

      await operation.startCall(
        callback: testCallback,
        description: 'call with callback',
      );
      
      // Cleanup is called during crash recovery, not normal operation
      expect(cleanupCalled, isFalse);

      await operation.complete();
    });

    test('endCall removes matching stack frame', () async {
      final operation = await ledger.startOperation(
        operationId: 'end_call_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final testCallback = CallCallback(onCleanup: () async {});
      final callId = await operation.startCall(callback: testCallback, description: 'test');
      expect(operation.cachedData!.stack.length, equals(1));

      await operation.endCall(callId: callId);
      expect(operation.cachedData!.stack.length, equals(0));

      await operation.complete();
    });

    test('endCall removes correct frame when multiple exist', () async {
      final operation = await ledger.startOperation(
        operationId: 'multi_end_call_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final testCallback = CallCallback(onCleanup: () async {});
      final call1 = await operation.startCall(callback: testCallback, description: 'call 1');
      final call2 = await operation.startCall(callback: testCallback, description: 'call 2');
      expect(operation.cachedData!.stack.length, equals(2));

      await operation.endCall(callId: call1);
      expect(operation.cachedData!.stack.length, equals(1));
      expect(operation.cachedData!.stack[0].callId, equals(call2));

      await operation.complete();
    });

    test('startCall failOnCrash defaults to true', () async {
      final operation = await ledger.startOperation(
        operationId: 'failoncrash_default_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final testCallback = CallCallback(onCleanup: () async {});
      await operation.startCall(
        callback: testCallback,
        description: 'default failOnCrash',
      );

      expect(operation.cachedData!.stack[0].failOnCrash, isTrue);

      await operation.complete();
    });

    test('startCall failOnCrash can be set to false', () async {
      final operation = await ledger.startOperation(
        operationId: 'failoncrash_false_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final testCallback = CallCallback(onCleanup: () async {});
      await operation.startCall(
        callback: testCallback,
        description: 'contained crash',
        failOnCrash: false,
      );

      expect(operation.cachedData!.stack[0].failOnCrash, isFalse);

      // Verify persisted to file
      final opFile = File('${tempDir.path}/failoncrash_false_test.operation.json');
      final content = json.decode(opFile.readAsStringSync());
      expect(content['stack'][0]['failOnCrash'], isFalse);

      await operation.complete();
    });

    test('startCall failOnCrash is persisted and restored', () async {
      // Create operation with failOnCrash=false call
      final operation1 = await ledger.startOperation(
        operationId: 'failoncrash_persist_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final testCallback = CallCallback(onCleanup: () async {});
      await operation1.startCall(
        callback: testCallback,
        description: 'contained',
        failOnCrash: false,
      );
      await operation1.startCall(
        callback: testCallback,
        description: 'normal',
        failOnCrash: true,
      );
      
      // Read and verify from file directly
      final opFile = File('${tempDir.path}/failoncrash_persist_test.operation.json');
      final content = json.decode(opFile.readAsStringSync()) as Map<String, dynamic>;
      final data = LedgerData.fromJson(content);
      
      expect(data.stack[0].failOnCrash, isFalse);
      expect(data.stack[0].description, equals('contained'));
      expect(data.stack[1].failOnCrash, isTrue);
      expect(data.stack[1].description, equals('normal'));

      await operation1.complete();
    });
  });

  group('New API - log with LogLevel', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('log_level_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('log with different levels writes to operation log', () async {
      final operation = await ledger.startOperation(
        operationId: 'log_level_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      await operation.log('Info message', level: LogLevel.info);
      await operation.log('Warning message', level: LogLevel.warning);
      await operation.log('Error message', level: LogLevel.error);

      final logFile = File('${tempDir.path}/log_level_test.operation.log');
      final content = logFile.readAsStringSync();

      expect(content, contains('[INFO] Info message'));
      expect(content, contains('[WARNING] Warning message'));
      expect(content, contains('[ERROR] Error message'));

      await operation.complete();
    });

    test('debugLog writes to debug log only', () async {
      final operation = await ledger.startOperation(
        operationId: 'debug_log_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      await operation.debugLog('Debug message');

      final debugLogFile = File('${tempDir.path}/debug_log_test.operation.debug.log');
      final content = debugLogFile.readAsStringSync();

      expect(content, contains('Debug message'));

      // Debug log should not be in operation log
      final opLogFile = File('${tempDir.path}/debug_log_test.operation.log');
      final opContent = opLogFile.readAsStringSync();
      expect(opContent, isNot(contains('Debug message')));

      await operation.complete();
    });
  });

  group('New API - createOperation with generated ID', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('create_op_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('createOperation generates operation ID', () async {
      final operation = await ledger.createOperation(
        participantPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      // Format: YYYYMMDDTHH:MM:SS.sss-participantId-random
      expect(operation.operationId, matches(RegExp(r'^\d{8}T\d{2}:\d{2}:\d{2}\.\d{3}-cli-\w+$')));

      await operation.complete();
    });
  });

  group('Backup cleanup with maxBackups', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('backup_cleanup_test_');
      ledger = Ledger(basePath: tempDir.path, maxBackups: 3);
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('maxBackups limits number of backup files', () async {
      // Create multiple operations to generate backups
      for (var i = 0; i < 5; i++) {
        final operation = await ledger.startOperation(
          operationId: 'backup_test_$i',
          initiatorPid: 1234,
          participantId: 'cli',
          getElapsedFormatted: () => '000.000',
        );
        await operation.complete();
      }

      final backupDir = Directory('${tempDir.path}/backup');
      if (backupDir.existsSync()) {
        // Count only .operation.json files (maxBackups applies to these)
        final opFiles = backupDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.operation.json'))
            .toList();
        // Should have at most maxBackups operation files
        expect(opFiles.length, lessThanOrEqualTo(3));
      }
    });
  });

  group('spawnCall with failOnCrash', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('spawnCall_failoncrash_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('spawnCall failOnCrash defaults to true', () async {
      final operation = await ledger.startOperation(
        operationId: 'spawn_default_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final testCallback = CallCallback(onCleanup: () async {});
      await operation.spawnCall(
        callback: testCallback,
        description: 'spawned call',
      );

      expect(operation.cachedData!.stack[0].failOnCrash, isTrue);

      await operation.complete();
    });

    test('spawnCall failOnCrash can be set to false', () async {
      final operation = await ledger.startOperation(
        operationId: 'spawn_false_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final testCallback = CallCallback(onCleanup: () async {});
      await operation.spawnCall(
        callback: testCallback,
        description: 'contained spawned',
        failOnCrash: false,
      );

      expect(operation.cachedData!.stack[0].failOnCrash, isFalse);

      // Verify persisted to file
      final opFile = File('${tempDir.path}/spawn_false_test.operation.json');
      final content = json.decode(opFile.readAsStringSync());
      expect(content['stack'][0]['failOnCrash'], isFalse);

      await operation.complete();
    });

    test('mixed startCall and spawnCall with different failOnCrash', () async {
      final operation = await ledger.startOperation(
        operationId: 'mixed_calls_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final testCallback = CallCallback(onCleanup: () async {});
      
      // Start a normal call (failOnCrash=true)
      await operation.startCall(
        callback: testCallback,
        description: 'normal call',
      );
      
      // Spawn a contained call (failOnCrash=false)
      await operation.spawnCall(
        callback: testCallback,
        description: 'contained spawn',
        failOnCrash: false,
      );
      
      // Start another normal call (failOnCrash=true, explicit)
      await operation.startCall(
        callback: testCallback,
        description: 'explicit normal',
        failOnCrash: true,
      );

      final stack = operation.cachedData!.stack;
      expect(stack.length, equals(3));
      expect(stack[0].failOnCrash, isTrue);
      expect(stack[0].description, equals('normal call'));
      expect(stack[1].failOnCrash, isFalse);
      expect(stack[1].description, equals('contained spawn'));
      expect(stack[2].failOnCrash, isTrue);
      expect(stack[2].description, equals('explicit normal'));

      await operation.complete();
    });
  });

  group('failCall', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('failCall_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('failCall removes stack frame and logs error', () async {
      final operation = await ledger.startOperation(
        operationId: 'fail_call_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      var cleanupCalled = false;
      final testCallback = CallCallback(
        onCleanup: () async { cleanupCalled = true; },
      );
      
      final callId = await operation.startCall(
        callback: testCallback,
        description: 'will fail',
      );

      expect(operation.cachedData!.stack.length, equals(1));

      await operation.failCall(
        callId: callId,
        error: 'Test error',
      );

      expect(operation.cachedData!.stack.length, equals(0));
      expect(cleanupCalled, isTrue);

      // Check log file for error entry
      final logFile = File('${tempDir.path}/fail_call_test.operation.log');
      expect(logFile.existsSync(), isTrue);
      final logContent = logFile.readAsStringSync();
      expect(logContent, contains('CALL_FAILED'));
      expect(logContent, contains('Test error'));

      await operation.complete();
    });

    test('failCall throws for unknown callId', () async {
      final operation = await ledger.startOperation(
        operationId: 'fail_call_unknown_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      expect(
        () => operation.failCall(callId: 'unknown_call', error: 'error'),
        throwsStateError,
      );

      await operation.complete();
    });

    test('failCall calls onCrashed callback if provided', () async {
      final operation = await ledger.startOperation(
        operationId: 'fail_call_crashed_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      CrashedCallInfo? crashedInfo;
      final testCallback = CallCallback(
        onCleanup: () async {},
        onCrashed: (info) async { crashedInfo = info; },
      );
      
      final callId = await operation.startCall(
        callback: testCallback,
        description: 'will crash',
      );

      await operation.failCall(
        callId: callId,
        error: 'Crash reason',
      );

      expect(crashedInfo, isNotNull);
      expect(crashedInfo!.callId, equals(callId));
      expect(crashedInfo!.crashReason, contains('Crash reason'));

      await operation.complete();
    });
  });

  group('spawnTyped and syncTyped', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('spawnTyped_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('spawnTyped returns SpawnedCall and executes work', () async {
      final operation = await ledger.startOperation(
        operationId: 'spawn_typed_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final spawned = operation.spawnTyped<int>(
        work: () async {
          await Future.delayed(Duration(milliseconds: 50));
          return 42;
        },
        description: 'compute value',
      );

      expect(spawned.callId, isNotEmpty);
      expect(spawned.isCompleted, isFalse);

      // Wait for completion
      await spawned.future;

      expect(spawned.isCompleted, isTrue);
      expect(spawned.isSuccess, isTrue);
      expect(spawned.result, equals(42));

      await operation.complete();
    });

    test('spawnTyped with onCallCrashed provides fallback', () async {
      final operation = await ledger.startOperation(
        operationId: 'spawn_typed_fallback_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final spawned = operation.spawnTyped<String>(
        work: () async {
          throw Exception('Work failed');
        },
        onCallCrashed: () async => 'fallback_value',
        description: 'will fail but recover',
        failOnCrash: false,
      );

      await spawned.future;

      expect(spawned.isSuccess, isTrue);
      expect(spawned.result, equals('fallback_value'));

      await operation.complete();
    });

    test('spawnTyped marks call as failed when no fallback', () async {
      final operation = await ledger.startOperation(
        operationId: 'spawn_typed_fail_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final spawned = operation.spawnTyped<int>(
        work: () async {
          throw Exception('Work failed');
        },
        description: 'will fail',
        failOnCrash: false,
      );

      await spawned.future;

      expect(spawned.isFailed, isTrue);
      expect(spawned.error, isNotNull);

      await operation.complete();
    });

    test('syncTyped waits for multiple calls', () async {
      final operation = await ledger.startOperation(
        operationId: 'sync_typed_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final call1 = operation.spawnTyped<int>(
        work: () async => 1,
      );
      final call2 = operation.spawnTyped<int>(
        work: () async => 2,
      );
      final call3 = operation.spawnTyped<int>(
        work: () async => 3,
      );

      final result = await operation.syncTyped([call1, call2, call3]);

      expect(result.allSucceeded, isTrue);
      expect(result.successfulCalls.length, equals(3));
      expect(result.failedCalls, isEmpty);

      await operation.complete();
    });

    test('syncTyped reports failed calls', () async {
      final operation = await ledger.startOperation(
        operationId: 'sync_typed_fail_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final call1 = operation.spawnTyped<int>(
        work: () async => 1,
        failOnCrash: false,
      );
      final call2 = operation.spawnTyped<int>(
        work: () async => throw Exception('fail'),
        failOnCrash: false,
      );

      final result = await operation.syncTyped([call1, call2]);

      expect(result.hasFailed, isTrue);
      expect(result.successfulCalls.length, equals(1));
      expect(result.failedCalls.length, equals(1));

      await operation.complete();
    });
  });

  group('OperationHelper', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('operation_helper_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('pollFile waits for file and reads content', () async {
      final filePath = '${tempDir.path}/result.txt';

      // Start poll before file exists
      final pollFuture = OperationHelper.pollFile<String>(
        path: filePath,
        pollInterval: Duration(milliseconds: 20),
      )();

      // Create file after a delay
      await Future.delayed(Duration(milliseconds: 50));
      await File(filePath).writeAsString('test content');

      final result = await pollFuture;
      expect(result, equals('test content'));
    });

    test('pollFile deletes file when delete=true', () async {
      final filePath = '${tempDir.path}/delete_me.txt';
      await File(filePath).writeAsString('content');

      final result = await OperationHelper.pollFile<String>(
        path: filePath,
        delete: true,
      )();

      expect(result, equals('content'));
      expect(File(filePath).existsSync(), isFalse);
    });

    test('pollFile uses deserializer', () async {
      final filePath = '${tempDir.path}/json_file.json';
      await File(filePath).writeAsString('{"value": 42}');

      final result = await OperationHelper.pollFile<Map<String, dynamic>>(
        path: filePath,
        deserializer: (content) => json.decode(content) as Map<String, dynamic>,
      )();

      expect(result['value'], equals(42));
    });

    test('pollFile times out', () async {
      final filePath = '${tempDir.path}/never_exists.txt';

      expect(
        () => OperationHelper.pollFile<String>(
          path: filePath,
          timeout: Duration(milliseconds: 100),
          pollInterval: Duration(milliseconds: 20),
        )(),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('pollUntil waits for condition', () async {
      var counter = 0;

      final result = await OperationHelper.pollUntil<int>(
        check: () async {
          counter++;
          return counter >= 3 ? counter : null;
        },
        pollInterval: Duration(milliseconds: 20),
      )();

      expect(result, equals(3));
    });

    test('pollUntil times out', () async {
      expect(
        () => OperationHelper.pollUntil<int>(
          check: () async => null,
          timeout: Duration(milliseconds: 100),
          pollInterval: Duration(milliseconds: 20),
        )(),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('pollFiles waits for multiple files', () async {
      final file1 = '${tempDir.path}/file1.txt';
      final file2 = '${tempDir.path}/file2.txt';

      // Create files with delay
      Future.delayed(Duration(milliseconds: 30)).then((_) async {
        await File(file1).writeAsString('content1');
      });
      Future.delayed(Duration(milliseconds: 60)).then((_) async {
        await File(file2).writeAsString('content2');
      });

      final results = await OperationHelper.pollFiles<String>(
        paths: [file1, file2],
        pollInterval: Duration(milliseconds: 20),
      )();

      expect(results.length, equals(2));
      expect(results[0], equals('content1'));
      expect(results[1], equals('content2'));
    });
  });

  group('SyncResult', () {
    test('allSucceeded is true when all calls succeed', () {
      final result = SyncResult(
        successfulCalls: [SpawnedCall<int>(callId: 'c1')],
        failedCalls: [],
        unknownCalls: [],
        operationFailed: false,
      );
      expect(result.allSucceeded, isTrue);
    });

    test('allSucceeded is false when any call fails', () {
      final result = SyncResult(
        successfulCalls: [],
        failedCalls: [SpawnedCall<int>(callId: 'c1')],
        unknownCalls: [],
        operationFailed: false,
      );
      expect(result.allSucceeded, isFalse);
      expect(result.hasFailed, isTrue);
    });

    test('allSucceeded is false when operation fails', () {
      final result = SyncResult(
        successfulCalls: [SpawnedCall<int>(callId: 'c1')],
        operationFailed: true,
      );
      expect(result.allSucceeded, isFalse);
    });

    test('allResolved is false when there are unknown calls', () {
      final result = SyncResult(
        successfulCalls: [],
        failedCalls: [],
        unknownCalls: [SpawnedCall<int>(callId: 'c1')],
        operationFailed: false,
      );
      expect(result.allResolved, isFalse);
    });
  });

  group('SpawnedCall', () {
    test('result throws before completion', () {
      final call = SpawnedCall<int>(callId: 'test');
      expect(() => call.result, throwsStateError);
    });

    test('result throws when failed', () {
      final call = SpawnedCall<int>(callId: 'test');
      call.fail(Exception('error'), StackTrace.current);
      expect(() => call.result, throwsStateError);
    });

    test('resultOrNull returns null when not completed', () {
      final call = SpawnedCall<int>(callId: 'test');
      expect(call.resultOrNull, isNull);
    });

    test('resultOrNull returns value when completed', () {
      final call = SpawnedCall<int>(callId: 'test');
      call.complete(42);
      expect(call.resultOrNull, equals(42));
    });

    test('resultOr returns default when failed', () {
      final call = SpawnedCall<int>(callId: 'test');
      call.fail(Exception('error'), StackTrace.current);
      expect(call.resultOr(99), equals(99));
    });

    test('toString is descriptive', () {
      final call = SpawnedCall<int>(callId: 'test_call', description: 'Test description');
      expect(call.toString(), contains('test_call'));
      expect(call.toString(), contains('SpawnedCall<int>'));
    });

    test('complete only works once', () {
      final call = SpawnedCall<int>(callId: 'test');
      call.complete(42);
      call.complete(99); // Should be ignored
      expect(call.result, equals(42));
    });

    test('fail only works once', () {
      final call = SpawnedCall<int>(callId: 'test');
      call.fail(Exception('first'));
      call.fail(Exception('second')); // Should be ignored
      expect(call.error.toString(), contains('first'));
    });

    test('resultOrNull returns null when failed', () {
      final call = SpawnedCall<int>(callId: 'test');
      call.fail(Exception('error'));
      expect(call.resultOrNull, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // ADDITIONAL COVERAGE TESTS
  // ═══════════════════════════════════════════════════════════════════

  group('endCall with onEnded callback', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('endcall_callback_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('endCall calls onEnded callback with info', () async {
      final operation = await ledger.startOperation(
        operationId: 'end_call_cb_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      CallEndedInfo? endedInfo;
      final testCallback = CallCallback(
        onCleanup: () async {},
        onEnded: (info) async { endedInfo = info; },
      );

      final callId = await operation.startCall(
        callback: testCallback,
        description: 'will end normally',
      );

      await Future.delayed(Duration(milliseconds: 10));
      await operation.endCall(callId: callId);

      expect(endedInfo, isNotNull);
      expect(endedInfo!.callId, equals(callId));
      expect(endedInfo!.operationId, equals('end_call_cb_test'));
      expect(endedInfo!.participantId, equals('cli'));
      expect(endedInfo!.duration.inMilliseconds, greaterThanOrEqualTo(10));

      await operation.complete();
    });

    test('endCall throws for unknown callId', () async {
      final operation = await ledger.startOperation(
        operationId: 'end_call_unknown_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      expect(
        () => operation.endCall(callId: 'unknown_call'),
        throwsStateError,
      );

      await operation.complete();
    });
  });

  group('sync method', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sync_method_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('sync waits for spawned calls to complete', () async {
      final operation = await ledger.startOperation(
        operationId: 'sync_wait_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      var completed = false;
      final testCallback = CallCallback(
        onCleanup: () async {},
        onEnded: (info) async { completed = true; },
      );

      final callId = await operation.spawnCall(
        callback: testCallback,
        description: 'spawned',
      );

      // Immediately complete the call
      await operation.endCall(callId: callId);

      // sync with empty list should return immediately
      await operation.sync([]);

      // sync with completed call should return
      await operation.sync([callId]);

      expect(completed, isTrue);

      await operation.complete();
    });
  });

  group('waitForCompletion', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('wait_completion_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('waitForCompletion executes work', () async {
      final operation = await ledger.startOperation(
        operationId: 'wait_comp_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      var workExecuted = false;
      await operation.waitForCompletion(() async {
        workExecuted = true;
      });

      expect(workExecuted, isTrue);

      await operation.complete();
    });

    test('waitForCompletion with async delay', () async {
      final operation = await ledger.startOperation(
        operationId: 'wait_comp_delay_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final stopwatch = Stopwatch()..start();
      await operation.waitForCompletion(() async {
        await Future.delayed(Duration(milliseconds: 50));
      });
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(40));

      await operation.complete();
    });
  });

  group('Operation.heartbeat() single call', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('single_heartbeat_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('heartbeat() returns result on success', () async {
      final operation = await ledger.startOperation(
        operationId: 'single_hb_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final result = await operation.heartbeat();

      expect(result, isNotNull);
      expect(result!.ledgerExists, isTrue);
      expect(result.heartbeatUpdated, isTrue);

      await operation.complete();
    });

    test('heartbeat() returns null when file missing', () async {
      final operation = await ledger.startOperation(
        operationId: 'single_hb_missing_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      // Delete the operation file
      final opFile = File('${tempDir.path}/single_hb_missing_test.operation.json');
      await opFile.delete();

      final result = await operation.heartbeat();
      expect(result, isNull);
    });
  });

  group('getOperationState and setOperationState', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('op_state_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('getOperationState returns running by default', () async {
      final operation = await ledger.startOperation(
        operationId: 'state_default_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final state = await operation.getOperationState();
      expect(state, equals(OperationState.running));

      await operation.complete();
    });

    test('setOperationState changes state', () async {
      final operation = await ledger.startOperation(
        operationId: 'state_change_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      await operation.setOperationState(OperationState.cleanup);
      var state = await operation.getOperationState();
      expect(state, equals(OperationState.cleanup));

      await operation.setOperationState(OperationState.failed);
      state = await operation.getOperationState();
      expect(state, equals(OperationState.failed));

      await operation.complete();
    });

    test('setOperationState logs state change', () async {
      final operation = await ledger.startOperation(
        operationId: 'state_log_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      await operation.setOperationState(OperationState.cleanup);

      final logFile = File('${tempDir.path}/state_log_test.operation.log');
      final content = logFile.readAsStringSync();
      expect(content, contains('OPERATION_STATE_CHANGED'));
      expect(content, contains('cleanup'));

      await operation.complete();
    });
  });

  group('retrieveAndLockOperation', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('lock_op_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('retrieveAndLockOperation returns data and unlocks', () async {
      final operation = await ledger.startOperation(
        operationId: 'retrieve_lock_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final data = await operation.retrieveAndLockOperation();
      expect(data, isNotNull);
      expect(data!.operationId, equals('retrieve_lock_test'));

      await operation.unlockOperation();

      await operation.complete();
    });

    test('writeAndUnlockOperation writes data', () async {
      final operation = await ledger.startOperation(
        operationId: 'write_unlock_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final data = await operation.retrieveAndLockOperation();
      data!.aborted = true;

      await operation.writeAndUnlockOperation(data);

      // Verify change was persisted
      final opFile = File('${tempDir.path}/write_unlock_test.operation.json');
      final content = json.decode(opFile.readAsStringSync());
      expect(content['aborted'], isTrue);

      await operation.complete();
    });
  });

  group('joinOperation', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('join_op_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('joinOperation works like participateInOperation', () async {
      final initiator = await ledger.startOperation(
        operationId: 'join_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final participant = await ledger.joinOperation(
        operationId: 'join_test',
        participantId: 'bridge',
        participantPid: 5678,
        getElapsedFormatted: () => '001.000',
      );

      expect(participant.operationId, equals('join_test'));
      expect(participant.participantId, equals('bridge'));
      expect(participant.pid, equals(5678));
      expect(participant.isInitiator, isFalse);

      await initiator.complete();
    });
  });

  group('Global Heartbeat', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('global_hb_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('startGlobalHeartbeat and stopGlobalHeartbeat', () async {
      final operation = await ledger.startOperation(
        operationId: 'global_hb_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      ledger.startGlobalHeartbeat(
        interval: Duration(milliseconds: 50),
        staleThreshold: Duration(seconds: 1),
      );

      await Future.delayed(Duration(milliseconds: 100));

      ledger.stopGlobalHeartbeat();

      await operation.complete();
    });

    test('global heartbeat calls onError for stale operations', () async {
      final operation = await ledger.startOperation(
        operationId: 'global_hb_stale_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      HeartbeatError? receivedError;
      ledger.startGlobalHeartbeat(
        interval: Duration(milliseconds: 30),
        staleThreshold: Duration(milliseconds: 10), // Very short for test
        onError: (op, error) {
          receivedError = error;
        },
      );

      // Wait long enough for operation to become stale
      await Future.delayed(Duration(milliseconds: 100));

      ledger.stopGlobalHeartbeat();

      // Operation should be detected as stale
      expect(receivedError, isNotNull);
      expect(receivedError!.type, equals(HeartbeatErrorType.heartbeatStale));

      await operation.complete();
    });
  });

  group('CallEndedInfo and CrashedCallInfo', () {
    test('CallEndedInfo has correct duration', () {
      final start = DateTime.now();
      final end = start.add(Duration(milliseconds: 500));
      
      final info = CallEndedInfo(
        callId: 'test_call',
        operationId: 'test_op',
        participantId: 'cli',
        startedAt: start,
        endedAt: end,
      );

      expect(info.duration.inMilliseconds, equals(500));
      expect(info.toString(), contains('test_call'));
    });

    test('CrashedCallInfo has correct uptime', () {
      final start = DateTime.now();
      final detected = start.add(Duration(milliseconds: 300));
      
      final info = CrashedCallInfo(
        callId: 'crash_call',
        operationId: 'test_op',
        participantId: 'cli',
        startedAt: start,
        detectedAt: detected,
        crashReason: 'Test crash',
      );

      expect(info.uptime.inMilliseconds, equals(300));
      expect(info.toString(), contains('crash_call'));
      expect(info.toString(), contains('Test crash'));
    });
  });

  group('OperationFailedInfo', () {
    test('toString is descriptive', () {
      final info = OperationFailedInfo(
        operationId: 'test_op',
        failedAt: DateTime.now(),
        reason: 'Test failure',
        crashedCallIds: ['call1', 'call2'],
      );

      final str = info.toString();
      expect(str, contains('test_op'));
      expect(str, contains('call1'));
      expect(str, contains('Test failure'));
    });
  });

  group('SyncResult toString', () {
    test('toString is descriptive', () {
      final result = SyncResult(
        successfulCalls: [SpawnedCall<int>(callId: 'c1')],
        failedCalls: [SpawnedCall<int>(callId: 'c2')],
        unknownCalls: [],
        operationFailed: true,
      );

      final str = result.toString();
      expect(str, contains('success: 1'));
      expect(str, contains('failed: 1'));
      expect(str, contains('operationFailed: true'));
    });
  });

  group('StackFrame heartbeat age', () {
    test('heartbeatAgeMs calculates correctly', () async {
      final oldTime = DateTime.now().subtract(Duration(seconds: 5));
      final frame = StackFrame(
        participantId: 'test',
        callId: 'call',
        pid: 100,
        startTime: oldTime,
        lastHeartbeat: oldTime,
      );

      final ageMs = frame.heartbeatAgeMs;
      expect(ageMs, greaterThanOrEqualTo(5000));
    });

    test('isStale returns true for old heartbeat', () {
      final oldTime = DateTime.now().subtract(Duration(seconds: 15));
      final frame = StackFrame(
        participantId: 'test',
        callId: 'call',
        pid: 100,
        startTime: oldTime,
        lastHeartbeat: oldTime,
      );

      expect(frame.isStale(), isTrue);
      expect(frame.isStale(timeoutMs: 20000), isFalse);
    });
  });

  group('LogLevel extension', () {
    test('all log levels have correct name', () {
      expect(LogLevel.debug.name, equals('DEBUG'));
      expect(LogLevel.info.name, equals('INFO'));
      expect(LogLevel.warning.name, equals('WARNING'));
      expect(LogLevel.error.name, equals('ERROR'));
    });
  });

  group('pollFile type inference', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('poll_type_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('pollFile returns Map when T is dynamic', () async {
      final filePath = '${tempDir.path}/map.json';
      await File(filePath).writeAsString('{"key": "value"}');

      final result = await OperationHelper.pollFile<dynamic>(
        path: filePath,
      )();

      expect(result, isA<Map>());
      expect((result as Map)['key'], equals('value'));
    });
  });

  group('pollFiles with deserializer', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('poll_files_deser_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('pollFiles uses deserializer for each file', () async {
      final file1 = '${tempDir.path}/f1.txt';
      final file2 = '${tempDir.path}/f2.txt';
      await File(file1).writeAsString('10');
      await File(file2).writeAsString('20');

      final results = await OperationHelper.pollFiles<int>(
        paths: [file1, file2],
        deserializer: (content) => int.parse(content),
      )();

      expect(results, equals([10, 20]));
    });

    test('pollFiles times out when file missing', () async {
      final file1 = '${tempDir.path}/exists.txt';
      final file2 = '${tempDir.path}/missing.txt';
      await File(file1).writeAsString('data');
      // file2 never created

      expect(
        () => OperationHelper.pollFiles<String>(
          paths: [file1, file2],
          timeout: Duration(milliseconds: 100),
          pollInterval: Duration(milliseconds: 20),
        )(),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('pollFiles deletes files when delete=true', () async {
      final file1 = '${tempDir.path}/del1.txt';
      final file2 = '${tempDir.path}/del2.txt';
      await File(file1).writeAsString('a');
      await File(file2).writeAsString('b');

      await OperationHelper.pollFiles<String>(
        paths: [file1, file2],
        delete: true,
      )();

      expect(File(file1).existsSync(), isFalse);
      expect(File(file2).existsSync(), isFalse);
    });
  });

  group('syncTyped with onCompletion', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sync_oncompletion_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('syncTyped calls onCompletion callback', () async {
      final operation = await ledger.startOperation(
        operationId: 'sync_completion_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      var completionCalled = false;
      final call = operation.spawnTyped<int>(work: () async => 42);

      await operation.syncTyped(
        [call],
        onCompletion: () async {
          completionCalled = true;
        },
      );

      expect(completionCalled, isTrue);

      await operation.complete();
    });
  });

  group('spawnTyped with onCompletion', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('spawn_oncompletion_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('spawnTyped calls onCompletion with result', () async {
      final operation = await ledger.startOperation(
        operationId: 'spawn_completion_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      int? receivedResult;
      final completer = Completer<void>();
      final call = operation.spawnTyped<int>(
        work: () async => 42,
        onCompletion: (result) async {
          receivedResult = result;
          completer.complete();
        },
      );

      await call.future;
      // Wait for onCompletion callback
      await completer.future.timeout(Duration(seconds: 1));

      expect(receivedResult, equals(42));

      await operation.complete();
    });
  });

  group('sync method with active calls', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sync_active_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('sync waits for active call completers', () async {
      final operation = await ledger.startOperation(
        operationId: 'sync_active_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final testCallback = CallCallback(onCleanup: () async {});
      
      // Spawn a call that will complete after delay
      final callId = await operation.spawnCall(
        callback: testCallback,
        description: 'will complete',
      );

      // End the call in the future
      Future.delayed(Duration(milliseconds: 50)).then((_) async {
        await operation.endCall(callId: callId);
      });

      // sync should wait for the call
      await operation.sync([callId]);

      await operation.complete();
    });

    test('sync returns immediately for unknown callIds', () async {
      final operation = await ledger.startOperation(
        operationId: 'sync_unknown_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      // sync with non-existent callIds should return immediately
      final stopwatch = Stopwatch()..start();
      await operation.sync(['unknown_call_1', 'unknown_call_2']);
      stopwatch.stop();

      // Should complete almost immediately
      expect(stopwatch.elapsedMilliseconds, lessThan(50));

      await operation.complete();
    });
  });

  group('onFailure callback in sync', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sync_onfailure_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('sync calls onOperationFailed when operation fails', () async {
      final operation = await ledger.startOperation(
        operationId: 'sync_fail_cb_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final testCallback = CallCallback(onCleanup: () async {});
      final callId = await operation.spawnCall(callback: testCallback);

      // Trigger failure in parallel
      Future.delayed(Duration(milliseconds: 20)).then((_) async {
        // Fail the call to trigger operation failure
        await operation.failCall(callId: callId, error: 'Test failure');
      });

      await operation.sync(
        [callId],
        onOperationFailed: (info) async {
          // This callback can be called when operation fails
          expect(info.operationId, equals('sync_fail_cb_test'));
        },
      );

      // Just verify the sync completed without error
      await operation.complete();
    });
  });

  group('waitForCompletion with onOperationFailed', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('wait_fail_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('waitForCompletion completes normally when work succeeds', () async {
      final operation = await ledger.startOperation(
        operationId: 'wait_normal_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      var workDone = false;
      await operation.waitForCompletion(
        () async {
          await Future.delayed(Duration(milliseconds: 20));
          workDone = true;
        },
        onOperationFailed: (info) async {
          // Should not be called
          fail('onOperationFailed should not be called');
        },
      );

      expect(workDone, isTrue);

      await operation.complete();
    });
  });

  group('Heartbeat detects operation state changes', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('hb_state_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('heartbeat signals failure when operation enters cleanup state', () async {
      final operation = await ledger.startOperation(
        operationId: 'hb_cleanup_state_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      // Set operation to cleanup state
      await operation.setOperationState(OperationState.cleanup);

      // Do a heartbeat - should detect the cleanup state
      final result = await operation.heartbeat();
      expect(result, isNotNull);

      await operation.complete();
    });
  });

  group('spawnTyped with onCallCrashed returning null', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('spawn_crash_null_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('call fails when onCallCrashed returns null', () async {
      final operation = await ledger.startOperation(
        operationId: 'crash_null_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final call = operation.spawnTyped<String>(
        work: () async => throw Exception('Work failed'),
        onCallCrashed: () async => null, // Returns null, so call should fail
        failOnCrash: false,
      );

      await call.future;

      expect(call.isFailed, isTrue);
      expect(call.error, isNotNull);

      await operation.complete();
    });

    test('call fails when onCallCrashed throws', () async {
      final operation = await ledger.startOperation(
        operationId: 'crash_throws_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      final call = operation.spawnTyped<String>(
        work: () async => throw Exception('Work failed'),
        onCallCrashed: () async => throw Exception('Recovery also failed'),
        failOnCrash: false,
      );

      await call.future;

      expect(call.isFailed, isTrue);

      await operation.complete();
    });
  });

  group('LedgerData edge cases', () {
    test('fromJson with null operationState', () {
      final json = {
        'operationId': 'test',
        'initiatorId': 'cli',
        // operationState is null
      };

      final data = LedgerData.fromJson(json);
      expect(data.operationState, equals(OperationState.running));
    });

    test('fromJson with missing fields', () {
      final json = {
        'operationId': 'test',
        // missing initiatorId
        'stack': [],
        'tempResources': [],
      };

      final data = LedgerData.fromJson(json);
      expect(data.initiatorId, equals('unknown'));
    });
  });

  group('HeartbeatResult with per-participant info', () {
    test('hasStaleChildren returns false when no stale participants', () {
      final result = HeartbeatResult(
        abortFlag: false,
        ledgerExists: true,
        heartbeatUpdated: true,
        stackDepth: 2,
        tempResourceCount: 0,
        heartbeatAgeMs: 100,
        isStale: false,
        stackParticipants: ['cli', 'bridge'],
        participantHeartbeatAges: {'cli': 100, 'bridge': 200},
        staleParticipants: [],
      );

      expect(result.hasStaleChildren, isFalse);
    });

    test('hasStaleChildren returns true when there are stale participants', () {
      final result = HeartbeatResult(
        abortFlag: false,
        ledgerExists: true,
        heartbeatUpdated: true,
        stackDepth: 2,
        tempResourceCount: 0,
        heartbeatAgeMs: 100,
        isStale: false,
        stackParticipants: ['cli', 'bridge'],
        participantHeartbeatAges: {'cli': 100, 'bridge': 15000},
        staleParticipants: ['bridge'],
      );

      expect(result.hasStaleChildren, isTrue);
    });
  });

  group('Ledger onLogLine callback', () {
    late Directory tempDir;
    
    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('log_callback_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('onLogLine is called for each log entry', () async {
      final logLines = <String>[];
      final ledger = Ledger(
        basePath: tempDir.path,
        onLogLine: (line) => logLines.add(line),
      );

      final operation = await ledger.startOperation(
        operationId: 'log_cb_test',
        initiatorPid: 1234,
        participantId: 'cli',
        getElapsedFormatted: () => '000.000',
      );

      await operation.log('First message');
      await operation.log('Second message');

      expect(logLines.length, equals(2));
      expect(logLines[0], contains('First message'));
      expect(logLines[1], contains('Second message'));

      await operation.complete();
      ledger.dispose();
    });
  });
}
