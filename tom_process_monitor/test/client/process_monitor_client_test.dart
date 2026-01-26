import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:tom_process_monitor/tom_process_monitor.dart';

void main() {
  group('LocalProcessMonitorClient', () {
    late String tempDir;
    late LocalProcessMonitorClient client;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('pm_client_test_').path;
      client = LocalProcessMonitorClient(directory: tempDir, instanceId: 'test');
    });

    tearDown(() async {
      final dir = Directory(tempDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('register adds process to registry', () async {
      final config = ProcessConfig(
        id: 'test-process',
        name: 'Test Process',
        command: '/bin/echo',
        args: ['hello'],
      );

      await client.register(config);

      final status = await client.getStatus('test-process');
      expect(status.id, equals('test-process'));
      expect(status.name, equals('Test Process'));
      expect(status.state, equals(ProcessState.stopped));
      expect(status.enabled, isTrue);
    });

    test('register throws for duplicate ID', () async {
      final config = ProcessConfig(
        id: 'duplicate-id',
        name: 'Test Process',
        command: '/bin/echo',
      );

      await client.register(config);

      expect(
        () => client.register(config),
        throwsA(isA<ProcessMonitorException>()),
      );
    });

    test('deregister removes process from registry', () async {
      final config = ProcessConfig(
        id: 'to-remove',
        name: 'To Remove',
        command: '/bin/echo',
      );

      await client.register(config);
      await client.deregister('to-remove');

      expect(
        () => client.getStatus('to-remove'),
        throwsA(isA<ProcessNotFoundException>()),
      );
    });

    test('deregister throws for non-existent process', () async {
      expect(
        () => client.deregister('non-existent'),
        throwsA(isA<ProcessNotFoundException>()),
      );
    });

    test('enable sets process enabled to true', () async {
      final config = ProcessConfig(
        id: 'to-enable',
        name: 'To Enable',
        command: '/bin/echo',
      );

      await client.register(config);
      await client.disable('to-enable');
      await client.enable('to-enable');

      final status = await client.getStatus('to-enable');
      expect(status.enabled, isTrue);
      expect(status.state, equals(ProcessState.stopped));
    });

    test('disable sets process enabled to false', () async {
      final config = ProcessConfig(
        id: 'to-disable',
        name: 'To Disable',
        command: '/bin/echo',
      );

      await client.register(config);
      await client.disable('to-disable');

      final status = await client.getStatus('to-disable');
      expect(status.enabled, isFalse);
      expect(status.state, equals(ProcessState.disabled));
    });

    test('setAutostart updates autostart setting', () async {
      final config = ProcessConfig(
        id: 'autostart-test',
        name: 'Autostart Test',
        command: '/bin/echo',
        autostart: true,
      );

      await client.register(config);
      var status = await client.getStatus('autostart-test');
      expect(status.autostart, isTrue);

      await client.setAutostart('autostart-test', false);
      status = await client.getStatus('autostart-test');
      expect(status.autostart, isFalse);
    });

    test('start sets state to starting', () async {
      final config = ProcessConfig(
        id: 'to-start',
        name: 'To Start',
        command: '/bin/echo',
      );

      await client.register(config);
      await client.start('to-start');

      final status = await client.getStatus('to-start');
      expect(status.state, equals(ProcessState.starting));
    });

    test('start throws for disabled process', () async {
      final config = ProcessConfig(
        id: 'disabled-start',
        name: 'Disabled Start',
        command: '/bin/echo',
      );

      await client.register(config);
      await client.disable('disabled-start');

      expect(
        () => client.start('disabled-start'),
        throwsA(isA<ProcessDisabledException>()),
      );
    });

    test('stop sets state to stopped', () async {
      final config = ProcessConfig(
        id: 'to-stop',
        name: 'To Stop',
        command: '/bin/echo',
      );

      await client.register(config);
      await client.start('to-stop');
      await client.stop('to-stop');

      final status = await client.getStatus('to-stop');
      expect(status.state, equals(ProcessState.stopped));
    });

    test('getAllStatus returns all processes', () async {
      await client.register(
        ProcessConfig(id: 'process-1', name: 'Process 1', command: '/bin/echo'),
      );
      await client.register(
        ProcessConfig(id: 'process-2', name: 'Process 2', command: '/bin/echo'),
      );

      final allStatus = await client.getAllStatus();
      expect(allStatus.length, equals(2));
      expect(allStatus.containsKey('process-1'), isTrue);
      expect(allStatus.containsKey('process-2'), isTrue);
    });

    test('setRemoteAccess updates remote access setting', () async {
      // Ensure registry exists
      await client.register(
        ProcessConfig(id: 'dummy', name: 'Dummy', command: '/bin/echo'),
      );

      await client.setRemoteAccess(true);
      var config = await client.getRemoteAccessConfig();
      expect(config.startRemoteAccess, isTrue);

      await client.setRemoteAccess(false);
      config = await client.getRemoteAccessConfig();
      expect(config.startRemoteAccess, isFalse);
    });

    test('setRemoteAccessPermissions updates permissions', () async {
      await client.register(
        ProcessConfig(id: 'dummy', name: 'Dummy', command: '/bin/echo'),
      );

      await client.setRemoteAccessPermissions(
        allowRegister: false,
        allowStart: false,
      );

      final config = await client.getRemoteAccessConfig();
      expect(config.allowRemoteRegister, isFalse);
      expect(config.allowRemoteStart, isFalse);
    });

    test('setTrustedHosts updates trusted hosts', () async {
      await client.register(
        ProcessConfig(id: 'dummy', name: 'Dummy', command: '/bin/echo'),
      );

      await client.setTrustedHosts(['10.0.0.1', '192.168.1.1']);

      final hosts = await client.getTrustedHosts();
      expect(hosts, contains('10.0.0.1'));
      expect(hosts, contains('192.168.1.1'));
    });

    test('setRemoteExecutableWhitelist updates whitelist', () async {
      await client.register(
        ProcessConfig(id: 'dummy', name: 'Dummy', command: '/bin/echo'),
      );

      await client.setRemoteExecutableWhitelist(['/opt/bin/*', '/usr/local/*']);

      final patterns = await client.getRemoteExecutableWhitelist();
      expect(patterns, contains('/opt/bin/*'));
      expect(patterns, contains('/usr/local/*'));
    });

    test('setRemoteExecutableBlacklist updates blacklist', () async {
      await client.register(
        ProcessConfig(id: 'dummy', name: 'Dummy', command: '/bin/echo'),
      );

      await client.setRemoteExecutableBlacklist(['/bin/rm', '**/*.sh']);

      final patterns = await client.getRemoteExecutableBlacklist();
      expect(patterns, contains('/bin/rm'));
      expect(patterns, contains('**/*.sh'));
    });

    test('setStandaloneMode updates standalone mode', () async {
      await client.register(
        ProcessConfig(id: 'dummy', name: 'Dummy', command: '/bin/echo'),
      );

      await client.setStandaloneMode(true);
      expect(await client.isStandaloneMode(), isTrue);

      await client.setStandaloneMode(false);
      expect(await client.isStandaloneMode(), isFalse);
    });

    test('setPartnerDiscoveryConfig updates partner config', () async {
      await client.register(
        ProcessConfig(id: 'dummy', name: 'Dummy', command: '/bin/echo'),
      );

      final newConfig = PartnerDiscoveryConfig(
        partnerInstanceId: 'custom-watcher',
        partnerAlivenessPort: 9999,
        discoveryOnStartup: false,
      );

      await client.setPartnerDiscoveryConfig(newConfig);

      final config = await client.getPartnerDiscoveryConfig();
      expect(config.partnerInstanceId, equals('custom-watcher'));
      expect(config.partnerAlivenessPort, equals(9999));
      expect(config.discoveryOnStartup, isFalse);
    });

    test('restartMonitor creates restart signal file', () async {
      await client.register(
        ProcessConfig(id: 'dummy', name: 'Dummy', command: '/bin/echo'),
      );

      await client.restartMonitor();

      final signalFile = File(path.join(tempDir, 'restart_test.signal'));
      expect(await signalFile.exists(), isTrue);
    });
  });
}
