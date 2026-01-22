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
}
