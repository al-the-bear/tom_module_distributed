import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_process_monitor/tom_process_monitor.dart';

void main() {
  group('ProcessMonitorClient.connect()', () {
    late String tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('pm_connect_test_').path;
    });

    tearDown(() async {
      final dir = Directory(tempDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    group('with directory parameter', () {
      test('returns LocalProcessMonitorClient', () async {
        final client = await ProcessMonitorClient.connect(
          directory: tempDir,
        );

        expect(client, isA<LocalProcessMonitorClient>());
      });

      test('uses default instanceId when not specified', () async {
        final client = await ProcessMonitorClient.connect(
          directory: tempDir,
        );

        expect(client, isA<LocalProcessMonitorClient>());
        // instanceId is now part of ProcessMonitorClient interface
        expect(client.instanceId, equals('default'));
      });

      test('passes custom instanceId to LocalProcessMonitorClient', () async {
        final client = await ProcessMonitorClient.connect(
          directory: tempDir,
          instanceId: 'my-custom-instance',
        );

        expect(client, isA<LocalProcessMonitorClient>());
        expect(client.instanceId, equals('my-custom-instance'));
      });
    });

    group('with baseUrl parameter', () {
      test('returns RemoteProcessMonitorClient', () async {
        final client = await ProcessMonitorClient.connect(
          baseUrl: 'http://localhost:8080',
        );

        expect(client, isA<RemoteProcessMonitorClient>());
      });

      test('uses default instanceId when not specified', () async {
        final client = await ProcessMonitorClient.connect(
          baseUrl: 'http://localhost:8080',
        );

        expect(client, isA<RemoteProcessMonitorClient>());
        // instanceId is now part of ProcessMonitorClient interface
        expect(client.instanceId, equals('default'));
      });

      test('passes custom instanceId to RemoteProcessMonitorClient', () async {
        final client = await ProcessMonitorClient.connect(
          baseUrl: 'http://localhost:8080',
          instanceId: 'my-custom-instance',
        );

        expect(client, isA<RemoteProcessMonitorClient>());
        expect(client.instanceId, equals('my-custom-instance'));
      });

      test('sets baseUrl correctly on RemoteProcessMonitorClient', () async {
        final client = await ProcessMonitorClient.connect(
          baseUrl: 'http://192.168.1.100:9999',
        );

        final remoteClient = client as RemoteProcessMonitorClient;
        expect(remoteClient.baseUrl, equals('http://192.168.1.100:9999'));
      });
    });

    group('with both directory and baseUrl', () {
      test('throws ArgumentError', () async {
        expect(
          () => ProcessMonitorClient.connect(
            directory: tempDir,
            baseUrl: 'http://localhost:8080',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('error message explains the conflict', () async {
        try {
          await ProcessMonitorClient.connect(
            directory: tempDir,
            baseUrl: 'http://localhost:8080',
          );
          fail('Expected ArgumentError to be thrown');
        } on ArgumentError catch (e) {
          expect(
            e.message.toString(),
            contains('Cannot specify both directory and baseUrl'),
          );
        }
      });
    });

    group('with no parameters (auto-discovery)', () {
      // Note: These tests will fail if no ProcessMonitor server is running.
      // They are skipped by default and should be run manually during
      // integration testing with a running server.

      test(
        'attempts discovery and throws DiscoveryFailedException when no server',
        () async {
          // When no server is running, discovery should fail
          expect(
            () => ProcessMonitorClient.connect(),
            throwsA(isA<DiscoveryFailedException>()),
          );
        },
        skip: 'Requires no ProcessMonitor server running on localhost:19881',
      );
    });
  });

  group('RemoteProcessMonitorClient', () {
    group('constructor', () {
      test('uses default baseUrl when not specified', () {
        final client = RemoteProcessMonitorClient();

        expect(client.baseUrl, equals('http://localhost:19881'));
      });

      test('uses custom baseUrl when specified', () {
        final client = RemoteProcessMonitorClient(
          baseUrl: 'http://192.168.1.50:8080',
        );

        expect(client.baseUrl, equals('http://192.168.1.50:8080'));
      });

      test('uses default instanceId when not specified', () {
        final client = RemoteProcessMonitorClient();

        expect(client.instanceId, equals('default'));
      });

      test('uses custom instanceId when specified', () {
        final client = RemoteProcessMonitorClient(
          instanceId: 'production-monitor',
        );

        expect(client.instanceId, equals('production-monitor'));
      });

      test('accepts both baseUrl and instanceId', () {
        final client = RemoteProcessMonitorClient(
          baseUrl: 'http://10.0.0.1:19881',
          instanceId: 'staging-instance',
        );

        expect(client.baseUrl, equals('http://10.0.0.1:19881'));
        expect(client.instanceId, equals('staging-instance'));
      });
    });

    group('instanceId field', () {
      test('is accessible and immutable', () {
        final client = RemoteProcessMonitorClient(
          instanceId: 'immutable-test',
        );

        // The field should be final (no setter)
        expect(client.instanceId, equals('immutable-test'));
      });

      test('can be used to distinguish different instances', () {
        final client1 = RemoteProcessMonitorClient(instanceId: 'instance-1');
        final client2 = RemoteProcessMonitorClient(instanceId: 'instance-2');
        final client3 = RemoteProcessMonitorClient(instanceId: 'instance-1');

        expect(client1.instanceId, equals('instance-1'));
        expect(client2.instanceId, equals('instance-2'));
        expect(client3.instanceId, equals(client1.instanceId));
        expect(client1.instanceId, isNot(equals(client2.instanceId)));
      });
    });
  });

  group('LocalProcessMonitorClient', () {
    late String tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('pm_local_test_').path;
    });

    tearDown(() async {
      final dir = Directory(tempDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    group('instanceId', () {
      test('uses default instanceId when not specified', () {
        final client = LocalProcessMonitorClient(directory: tempDir);

        expect(client.instanceId, equals('default'));
      });

      test('uses custom instanceId when specified', () {
        final client = LocalProcessMonitorClient(
          directory: tempDir,
          instanceId: 'local-monitor',
        );

        expect(client.instanceId, equals('local-monitor'));
      });

      test('instanceId is accessible on the client', () {
        final client = LocalProcessMonitorClient(
          directory: tempDir,
          instanceId: 'accessible-id',
        );

        // Verify it's accessible (not private)
        expect(client.instanceId, isNotNull);
        expect(client.instanceId, equals('accessible-id'));
      });
    });
  });
}
