import 'package:test/test.dart';
import 'package:tom_process_monitor/tom_process_monitor.dart';

void main() {
  group('ProcessConfig', () {
    test('creates with required fields', () {
      final config = ProcessConfig(
        id: 'test-id',
        name: 'Test Process',
        command: '/usr/bin/test',
      );

      expect(config.id, equals('test-id'));
      expect(config.name, equals('Test Process'));
      expect(config.command, equals('/usr/bin/test'));
      expect(config.args, isEmpty);
      expect(config.autostart, isTrue);
    });

    test('serializes to JSON correctly', () {
      final config = ProcessConfig(
        id: 'test-id',
        name: 'Test Process',
        command: '/usr/bin/test',
        args: ['--arg1', '--arg2'],
        autostart: false,
      );

      final json = config.toJson();

      expect(json['id'], equals('test-id'));
      expect(json['name'], equals('Test Process'));
      expect(json['command'], equals('/usr/bin/test'));
      expect(json['args'], equals(['--arg1', '--arg2']));
      expect(json['autostart'], isFalse);
    });

    test('deserializes from JSON correctly', () {
      final json = {
        'id': 'test-id',
        'name': 'Test Process',
        'command': '/usr/bin/test',
        'args': ['--arg1'],
        'autostart': true,
      };

      final config = ProcessConfig.fromJson(json);

      expect(config.id, equals('test-id'));
      expect(config.name, equals('Test Process'));
      expect(config.command, equals('/usr/bin/test'));
      expect(config.args, equals(['--arg1']));
      expect(config.autostart, isTrue);
    });
  });

  group('RestartPolicy', () {
    test('creates with defaults', () {
      final policy = RestartPolicy();

      expect(policy.maxAttempts, equals(5));
      expect(policy.backoffIntervalsMs, equals([1000, 2000, 5000]));
      expect(policy.resetAfterMs, equals(300000));
      expect(policy.retryIndefinitely, isFalse);
    });

    test('serializes to JSON correctly', () {
      final policy = RestartPolicy(maxAttempts: 3, retryIndefinitely: true);

      final json = policy.toJson();

      expect(json['maxAttempts'], equals(3));
      expect(json['retryIndefinitely'], isTrue);
    });
  });

  group('AlivenessCheck', () {
    test('creates with required fields', () {
      final check = AlivenessCheck(
        enabled: true,
        url: 'http://localhost:8080/health',
      );

      expect(check.enabled, isTrue);
      expect(check.url, equals('http://localhost:8080/health'));
      expect(check.intervalMs, equals(3000));
      expect(check.timeoutMs, equals(2000));
      expect(check.consecutiveFailuresRequired, equals(2));
    });

    test('serializes to JSON correctly', () {
      final check = AlivenessCheck(
        enabled: true,
        url: 'http://localhost:8080/health',
        intervalMs: 5000,
        timeoutMs: 3000,
      );

      final json = check.toJson();

      expect(json['enabled'], isTrue);
      expect(json['url'], equals('http://localhost:8080/health'));
      expect(json['intervalMs'], equals(5000));
      expect(json['timeoutMs'], equals(3000));
    });
  });

  group('ProcessState', () {
    test('values are correct', () {
      expect(ProcessState.values.length, equals(8));
      expect(ProcessState.values.contains(ProcessState.stopped), isTrue);
      expect(ProcessState.values.contains(ProcessState.starting), isTrue);
      expect(ProcessState.values.contains(ProcessState.running), isTrue);
      expect(ProcessState.values.contains(ProcessState.stopping), isTrue);
      expect(ProcessState.values.contains(ProcessState.crashed), isTrue);
      expect(ProcessState.values.contains(ProcessState.retrying), isTrue);
      expect(ProcessState.values.contains(ProcessState.failed), isTrue);
      expect(ProcessState.values.contains(ProcessState.disabled), isTrue);
    });
  });

  group('MonitorStatus', () {
    test('creates with required fields', () {
      final status = MonitorStatus(
        instanceId: 'default',
        pid: 1234,
        startedAt: DateTime.now(),
        uptime: 3600,
        state: 'running',
        standaloneMode: false,
        managedProcessCount: 5,
        runningProcessCount: 3,
      );

      expect(status.instanceId, equals('default'));
      expect(status.pid, equals(1234));
      expect(status.state, equals('running'));
      expect(status.managedProcessCount, equals(5));
      expect(status.runningProcessCount, equals(3));
    });

    test('serializes to JSON correctly', () {
      final now = DateTime.now();
      final status = MonitorStatus(
        instanceId: 'watcher',
        pid: 5678,
        startedAt: now,
        uptime: 7200,
        state: 'running',
        standaloneMode: true,
        managedProcessCount: 10,
        runningProcessCount: 7,
      );

      final json = status.toJson();

      expect(json['instanceId'], equals('watcher'));
      expect(json['pid'], equals(5678));
      expect(json['state'], equals('running'));
      expect(json['standaloneMode'], isTrue);
      expect(json['managedProcessCount'], equals(10));
      expect(json['runningProcessCount'], equals(7));
    });
  });

  group('ProcessStatus', () {
    test('creates with required fields', () {
      final status = ProcessStatus(
        id: 'test-process',
        name: 'Test Process',
        state: ProcessState.running,
        pid: 1234,
        enabled: true,
        autostart: true,
        isRemote: false,
      );

      expect(status.id, equals('test-process'));
      expect(status.name, equals('Test Process'));
      expect(status.state, equals(ProcessState.running));
      expect(status.pid, equals(1234));
      expect(status.enabled, isTrue);
    });

    test('serializes to JSON correctly', () {
      final status = ProcessStatus(
        id: 'test-process',
        name: 'Test Process',
        state: ProcessState.stopped,
        enabled: true,
        autostart: false,
        isRemote: false,
      );

      final json = status.toJson();

      expect(json['id'], equals('test-process'));
      expect(json['name'], equals('Test Process'));
      expect(json['state'], equals('stopped'));
      expect(json['enabled'], isTrue);
      expect(json['autostart'], isFalse);
    });
  });
}
