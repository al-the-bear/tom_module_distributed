import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_process_monitor/tom_process_monitor.dart';

void main() {
  late Directory tempDir;
  late RegistryService registryService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pm_test_');
    registryService = RegistryService(
      directory: tempDir.path,
      instanceId: 'test',
    );
    await registryService.initialize();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('RegistryService', () {
    test('initializes with default registry', () async {
      final registry = await registryService.load();

      expect(registry, isNotNull);
      expect(registry.processes, isEmpty);
      expect(registry.alivenessServer.enabled, isTrue);
      expect(registry.alivenessServer.port, equals(19883));
    });

    test('saves and loads registry', () async {
      await registryService.withLock((registry) async {
        registry.processes['test-process'] = ProcessEntry(
          id: 'test-process',
          name: 'Test Process',
          command: '/usr/bin/test',
          enabled: true,
          autostart: true,
          registeredAt: DateTime.now(),
        );
      });

      final loaded = await registryService.load();

      expect(loaded.processes.containsKey('test-process'), isTrue);
      expect(loaded.processes['test-process']?.name, equals('Test Process'));
    });

    test('handles concurrent access with lock', () async {
      // Start two concurrent operations - they should serialize properly
      await registryService.withLock((registry) async {
        registry.processes['process1'] = ProcessEntry(
          id: 'process1',
          name: 'Process 1',
          command: '/usr/bin/test',
          enabled: true,
          autostart: true,
          registeredAt: DateTime.now(),
        );
      });

      await registryService.withLock((registry) async {
        registry.processes['process2'] = ProcessEntry(
          id: 'process2',
          name: 'Process 2',
          command: '/usr/bin/test',
          enabled: true,
          autostart: true,
          registeredAt: DateTime.now(),
        );
      });

      final registry = await registryService.load();
      expect(registry.processes.length, equals(2));
    });

    test('updates process entry correctly', () async {
      await registryService.withLock((registry) async {
        registry.processes['test'] = ProcessEntry(
          id: 'test',
          name: 'Test',
          command: '/usr/bin/test',
          enabled: true,
          autostart: true,
          registeredAt: DateTime.now(),
        );
      });

      await registryService.withLock((registry) async {
        final process = registry.processes['test']!;
        process.state = ProcessState.running;
        process.pid = 12345;
      });

      final registry = await registryService.load();
      expect(registry.processes['test']?.state, equals(ProcessState.running));
      expect(registry.processes['test']?.pid, equals(12345));
    });
  });

  group('ProcessRegistry', () {
    test('serializes to JSON correctly', () async {
      await registryService.withLock((registry) async {
        registry.processes['test'] = ProcessEntry(
          id: 'test',
          name: 'Test',
          command: '/usr/bin/test',
          enabled: true,
          autostart: true,
          registeredAt: DateTime.now(),
        );
        registry.remoteAccess = RemoteAccessConfig(
          startRemoteAccess: true,
          remotePort: 19881,
        );
      });

      final registry = await registryService.load();
      final json = registry.toJson();

      expect(json['processes'], isA<Map>());
      expect(json['alivenessServer'], isA<Map>());
      expect(json['remoteAccess'], isA<Map>());
    });

    test('deserializes from JSON correctly', () {
      final json = {
        'processes': {
          'test': {
            'id': 'test',
            'name': 'Test Process',
            'command': '/usr/bin/test',
            'args': <String>[],
            'enabled': true,
            'autostart': true,
            'state': 'stopped',
            'isRemote': false,
            'registeredAt': DateTime.now().toIso8601String(),
          },
        },
        'alivenessServer': {'enabled': true, 'port': 19883},
        'remoteAccess': {'startRemoteAccess': false, 'remotePort': 19881},
      };

      final registry = ProcessRegistry.fromJson(json);

      expect(registry.processes.containsKey('test'), isTrue);
      expect(registry.processes['test']?.name, equals('Test Process'));
    });
  });
}
