import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_process_monitor/tom_process_monitor.dart';

void main() {
  late Directory tempDir;
  late ProcessControl processControl;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pm_control_test_');
    processControl = ProcessControl(
      logDirectory: tempDir.path,
      instanceId: 'test',
    );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('ProcessControl', () {
    test('starts a simple process', () async {
      final entry = ProcessEntry(
        id: 'echo-test',
        name: 'Echo Test',
        command: 'echo',
        args: ['Hello, World!'],
        enabled: true,
        autostart: false,
        registeredAt: DateTime.now(),
      );

      final pid = await processControl.startProcess(entry);

      expect(pid, greaterThan(0));
    });

    test('detects process existence', () async {
      // Current process should exist
      final currentPid = pid;
      final exists = await processControl.isProcessAlive(currentPid);

      expect(exists, isTrue);
    });

    test('detects non-existent process', () async {
      // Use an unlikely PID
      final exists = await processControl.isProcessAlive(999999999);

      expect(exists, isFalse);
    });

    test('stops a running process', () async {
      final entry = ProcessEntry(
        id: 'sleep-test',
        name: 'Sleep Test',
        command: 'sleep',
        args: ['60'],
        enabled: true,
        autostart: false,
        registeredAt: DateTime.now(),
      );

      final processPid = await processControl.startProcess(entry);
      expect(processPid, greaterThan(0));

      // Give process time to start
      await Future<void>.delayed(Duration(milliseconds: 100));

      // Verify it's running
      expect(await processControl.isProcessAlive(processPid), isTrue);

      // Stop it
      final stopped = await processControl.stopProcess(processPid);
      expect(stopped, isTrue);

      // Give it time to stop
      await Future<void>.delayed(Duration(milliseconds: 100));

      // Verify it's stopped
      expect(await processControl.isProcessAlive(processPid), isFalse);
    });
  });

  group('ProcessEntry', () {
    test('creates with required fields', () {
      final entry = ProcessEntry(
        id: 'test',
        name: 'Test Process',
        command: '/usr/bin/test',
        enabled: true,
        autostart: true,
        registeredAt: DateTime.now(),
      );

      expect(entry.id, equals('test'));
      expect(entry.name, equals('Test Process'));
      expect(entry.command, equals('/usr/bin/test'));
      expect(entry.enabled, isTrue);
      expect(entry.autostart, isTrue);
      expect(entry.state, equals(ProcessState.stopped));
    });

    test('serializes to JSON correctly', () {
      final entry = ProcessEntry(
        id: 'test',
        name: 'Test Process',
        command: '/usr/bin/test',
        args: ['--arg1', '--arg2'],
        enabled: true,
        autostart: false,
        state: ProcessState.running,
        pid: 12345,
        isRemote: false,
        registeredAt: DateTime.now(),
      );

      final json = entry.toJson();

      expect(json['id'], equals('test'));
      expect(json['name'], equals('Test Process'));
      expect(json['command'], equals('/usr/bin/test'));
      expect(json['args'], equals(['--arg1', '--arg2']));
      expect(json['state'], equals('running'));
      expect(json['pid'], equals(12345));
    });

    test('deserializes from JSON correctly', () {
      final json = {
        'id': 'test',
        'name': 'Test Process',
        'command': '/usr/bin/test',
        'args': ['--arg1'],
        'enabled': true,
        'autostart': true,
        'state': 'crashed',
        'pid': 12345,
        'isRemote': false,
        'registeredAt': DateTime.now().toIso8601String(),
      };

      final entry = ProcessEntry.fromJson(json);

      expect(entry.id, equals('test'));
      expect(entry.name, equals('Test Process'));
      expect(entry.state, equals(ProcessState.crashed));
      expect(entry.pid, equals(12345));
    });
  });
}
