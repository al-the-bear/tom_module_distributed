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
      late String tempDir;
      late RegistryService registryService;
      late ProcessControl processControl;
      late RemoteApiServer server;
      late int port;

      Future<MonitorStatus> mockGetStatus() async {
        return MonitorStatus(
          instanceId: 'discovery-test',
          pid: 12345,
          startedAt: DateTime.now(),
          uptime: 100,
          state: 'running',
          standaloneMode: false,
          managedProcessCount: 0,
          runningProcessCount: 0,
        );
      }

      setUp(() async {
        tempDir = Directory.systemTemp.createTempSync('pm_discover_test_').path;
        registryService = RegistryService(directory: tempDir, instanceId: 'test');
        await registryService.initialize();
        processControl = ProcessControl(logDirectory: tempDir);

        // Find an available port
        final tempServer = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        port = tempServer.port;
        await tempServer.close();

        server = RemoteApiServer(
          port: port,
          registryService: registryService,
          processControl: processControl,
          getStatus: mockGetStatus,
        );
        await server.start();
      });

      tearDown(() async {
        await server.stop();
        final dir = Directory(tempDir);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      test('discovers server on localhost', () async {
        final client = await RemoteProcessMonitorClient.discover(
          port: port,
          timeout: const Duration(seconds: 2),
        );

        expect(client, isA<RemoteProcessMonitorClient>());
        expect(client.instanceId, equals('default'));
        // Verify we can actually communicate with the server
        final status = await client.getMonitorStatus();
        expect(status.instanceId, equals('discovery-test'));
      });

      test('passes instanceId to discovered client', () async {
        final client = await RemoteProcessMonitorClient.discover(
          port: port,
          instanceId: 'my-instance',
          timeout: const Duration(seconds: 2),
        );

        expect(client.instanceId, equals('my-instance'));
      });

      test('ProcessMonitorClient.connect() with custom port discovers server', () async {
        final client = await ProcessMonitorClient.connect(
          port: port,
          instanceId: 'connected-instance',
          timeout: const Duration(seconds: 2),
        );

        expect(client, isA<RemoteProcessMonitorClient>());
        expect(client.instanceId, equals('connected-instance'));
      });

      test('throws DiscoveryFailedException when no server on port', () async {
        // Use a port where no server is running
        final unusedPort = port + 1000;

        expect(
          () => RemoteProcessMonitorClient.discover(
            port: unusedPort,
            timeout: const Duration(milliseconds: 500),
          ),
          throwsA(isA<DiscoveryFailedException>()),
        );
      });
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

  group('RemoteApiServer bindAddress', () {
    late String tempDir;
    late RegistryService registryService;
    late ProcessControl processControl;
    late int port;

    Future<MonitorStatus> mockGetStatus() async {
      return MonitorStatus(
        instanceId: 'bind-test',
        pid: 12345,
        startedAt: DateTime.now(),
        uptime: 100,
        state: 'running',
        standaloneMode: false,
        managedProcessCount: 0,
        runningProcessCount: 0,
      );
    }

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('pm_bind_test_').path;
      registryService = RegistryService(directory: tempDir, instanceId: 'test');
      await registryService.initialize();
      processControl = ProcessControl(logDirectory: tempDir);

      // Find an available port
      final tempServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      port = tempServer.port;
      await tempServer.close();
    });

    tearDown(() async {
      final dir = Directory(tempDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('binds to all interfaces when bindAddress is null', () async {
      final server = RemoteApiServer(
        port: port,
        bindAddress: null,
        registryService: registryService,
        processControl: processControl,
        getStatus: mockGetStatus,
      );

      await server.start();
      expect(server.isRunning, isTrue);
      expect(server.boundAddress, equals('0.0.0.0'));
      await server.stop();
    });

    test('binds to specific IP when full address provided', () async {
      final server = RemoteApiServer(
        port: port,
        bindAddress: '127.0.0.1',
        registryService: registryService,
        processControl: processControl,
        getStatus: mockGetStatus,
      );

      await server.start();
      expect(server.isRunning, isTrue);
      expect(server.boundAddress, equals('127.0.0.1'));
      await server.stop();
    });

    test('resolves partial pattern to matching local IP', () async {
      // Get a local non-loopback IP for testing
      String? localIp;
      try {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
        );
        for (final interface in interfaces) {
          for (final addr in interface.addresses) {
            if (!addr.isLoopback) {
              localIp = addr.address;
              break;
            }
          }
          if (localIp != null) break;
        }
      } catch (_) {
        // Skip if can't get network interfaces
      }

      if (localIp == null) {
        // Skip test if no non-loopback IP available
        return;
      }

      // Use first octet as pattern
      final pattern = '${localIp.split('.')[0]}.';

      final server = RemoteApiServer(
        port: port,
        bindAddress: pattern,
        registryService: registryService,
        processControl: processControl,
        getStatus: mockGetStatus,
      );

      await server.start();
      expect(server.isRunning, isTrue);
      expect(server.boundAddress, startsWith(pattern));
      await server.stop();
    });

    test('throws when pattern matches no interface', () async {
      final server = RemoteApiServer(
        port: port,
        bindAddress: '240.',  // Reserved range, unlikely to exist
        registryService: registryService,
        processControl: processControl,
        getStatus: mockGetStatus,
      );

      expect(
        () => server.start(),
        throwsA(isA<StateError>()),
      );
    });
  });
}
