import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_process_monitor/tom_process_monitor.dart';
import 'package:http/http.dart' as http;

void main() {
  group('RemoteApiServer', () {
    late String tempDir;
    late RegistryService registryService;
    late ProcessControl processControl;
    late RemoteApiServer server;
    late int port;
    late http.Client client;

    Future<MonitorStatus> mockGetStatus() async {
      return MonitorStatus(
        instanceId: 'test',
        pid: 12345,
        startedAt: DateTime.now(),
        uptime: 100,
        state: 'running',
        standaloneMode: false,
        managedProcessCount: 1,
        runningProcessCount: 0,
      );
    }

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('api_server_test_').path;
      registryService = RegistryService(
        directory: tempDir,
        instanceId: 'test',
      );
      await registryService.initialize();
      processControl = ProcessControl(logDirectory: tempDir);
      client = http.Client();

      // Find an available port
      final tempServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
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
      client.close();
      await server.stop();
      final dir = Directory(tempDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('GET /processes returns empty list initially', () async {
      final response = await client.get(
        Uri.parse('http://localhost:$port/processes'),
      );

      expect(response.statusCode, equals(HttpStatus.ok));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final processes = data['processes'] as List;
      expect(processes, isEmpty);
    });

    test('POST /processes registers a new process', () async {
      final config = {
        'id': 'test-process',
        'name': 'Test Process',
        'command': '/bin/echo',
        'args': ['hello'],
        'autostart': false,
      };

      final response = await client.post(
        Uri.parse('http://localhost:$port/processes'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(config),
      );

      expect(response.statusCode, equals(HttpStatus.ok));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      expect(data['success'], isTrue);
      expect(data['processId'], equals('test-process'));
    });

    test('GET /processes/{id} returns process status', () async {
      // First register a process
      await client.post(
        Uri.parse('http://localhost:$port/processes'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': 'my-process',
          'name': 'My Process',
          'command': '/bin/echo',
        }),
      );

      final response = await client.get(
        Uri.parse('http://localhost:$port/processes/my-process'),
      );

      expect(response.statusCode, equals(HttpStatus.ok));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      expect(data['id'], equals('my-process'));
      expect(data['name'], equals('My Process'));
      expect(data['state'], equals('stopped'));
    });

    test('GET /processes/{id} returns 404 for unknown process', () async {
      final response = await client.get(
        Uri.parse('http://localhost:$port/processes/unknown'),
      );

      expect(response.statusCode, equals(HttpStatus.notFound));
    });

    test('DELETE /processes/{id} deregisters process', () async {
      await client.post(
        Uri.parse('http://localhost:$port/processes'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': 'to-delete',
          'name': 'To Delete',
          'command': '/bin/echo',
        }),
      );

      final response = await client.delete(
        Uri.parse('http://localhost:$port/processes/to-delete'),
      );

      expect(response.statusCode, equals(HttpStatus.ok));

      // Verify it's gone
      final getResponse = await client.get(
        Uri.parse('http://localhost:$port/processes/to-delete'),
      );
      expect(getResponse.statusCode, equals(HttpStatus.notFound));
    });

    test('POST /processes/{id}/start sets state to starting', () async {
      await client.post(
        Uri.parse('http://localhost:$port/processes'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': 'to-start',
          'name': 'To Start',
          'command': '/bin/echo',
        }),
      );

      final response = await client.post(
        Uri.parse('http://localhost:$port/processes/to-start/start'),
      );

      expect(response.statusCode, equals(HttpStatus.ok));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      expect(data['success'], isTrue);
      expect(data['state'], equals('starting'));
    });

    test('POST /processes/{id}/stop sets state to stopped', () async {
      await client.post(
        Uri.parse('http://localhost:$port/processes'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': 'to-stop',
          'name': 'To Stop',
          'command': '/bin/echo',
        }),
      );

      await client.post(
        Uri.parse('http://localhost:$port/processes/to-stop/start'),
      );

      final response = await client.post(
        Uri.parse('http://localhost:$port/processes/to-stop/stop'),
      );

      expect(response.statusCode, equals(HttpStatus.ok));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      expect(data['success'], isTrue);
      expect(data['state'], equals('stopped'));
    });

    test('POST /processes/{id}/enable enables the process', () async {
      await client.post(
        Uri.parse('http://localhost:$port/processes'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': 'to-enable',
          'name': 'To Enable',
          'command': '/bin/echo',
        }),
      );

      await client.post(
        Uri.parse('http://localhost:$port/processes/to-enable/disable'),
      );

      final response = await client.post(
        Uri.parse('http://localhost:$port/processes/to-enable/enable'),
      );

      expect(response.statusCode, equals(HttpStatus.ok));

      final statusResponse = await client.get(
        Uri.parse('http://localhost:$port/processes/to-enable'),
      );
      final status = jsonDecode(statusResponse.body) as Map<String, dynamic>;
      expect(status['enabled'], isTrue);
    });

    test('POST /processes/{id}/disable disables the process', () async {
      await client.post(
        Uri.parse('http://localhost:$port/processes'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': 'to-disable',
          'name': 'To Disable',
          'command': '/bin/echo',
        }),
      );

      final response = await client.post(
        Uri.parse('http://localhost:$port/processes/to-disable/disable'),
      );

      expect(response.statusCode, equals(HttpStatus.ok));

      final statusResponse = await client.get(
        Uri.parse('http://localhost:$port/processes/to-disable'),
      );
      final status = jsonDecode(statusResponse.body) as Map<String, dynamic>;
      expect(status['enabled'], isFalse);
      expect(status['state'], equals('disabled'));
    });

    test('PUT /processes/{id}/autostart updates autostart', () async {
      await client.post(
        Uri.parse('http://localhost:$port/processes'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': 'autostart-test',
          'name': 'Autostart Test',
          'command': '/bin/echo',
          'autostart': true,
        }),
      );

      final response = await client.put(
        Uri.parse('http://localhost:$port/processes/autostart-test/autostart'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'autostart': false}),
      );

      expect(response.statusCode, equals(HttpStatus.ok));

      final statusResponse = await client.get(
        Uri.parse('http://localhost:$port/processes/autostart-test'),
      );
      final status = jsonDecode(statusResponse.body) as Map<String, dynamic>;
      expect(status['autostart'], isFalse);
    });

    test('GET /monitor/status returns monitor status', () async {
      final response = await client.get(
        Uri.parse('http://localhost:$port/monitor/status'),
      );

      expect(response.statusCode, equals(HttpStatus.ok));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      expect(data['instanceId'], equals('test'));
      expect(data['pid'], equals(12345));
      expect(data['state'], equals('running'));
    });

    test('GET /config/standalone-mode returns standalone mode', () async {
      final response = await client.get(
        Uri.parse('http://localhost:$port/config/standalone-mode'),
      );

      expect(response.statusCode, equals(HttpStatus.ok));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      expect(data['enabled'], isFalse);
    });

    test('GET /config/trusted-hosts returns trusted hosts', () async {
      final response = await client.get(
        Uri.parse('http://localhost:$port/config/trusted-hosts'),
      );

      expect(response.statusCode, equals(HttpStatus.ok));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      expect(data['trustedHosts'], contains('localhost'));
    });

    test('isRunning property reflects server state', () async {
      expect(server.isRunning, isTrue);
      await server.stop();
      expect(server.isRunning, isFalse);
    });

    group('executable whitelist requirement', () {
      test('registration fails with empty whitelist for non-trusted host',
          () async {
        // Configure registry with empty whitelist
        final registry = await registryService.load();
        registry.remoteAccess = RemoteAccessConfig(
          startRemoteAccess: true,
          executableWhitelist: [], // Empty whitelist
          trustedHosts: [], // No trusted hosts
        );
        await registryService.save(registry);

        final config = {
          'id': 'blocked-process',
          'name': 'Blocked Process',
          'command': '/usr/bin/echo',
          'args': [],
          'autostart': false,
        };

        // Registration should fail due to empty whitelist
        final response = await client.post(
          Uri.parse('http://localhost:$port/processes'),
          headers: {
            'Content-Type': 'application/json',
            'X-Real-IP': '10.0.0.100', // Non-trusted host
          },
          body: jsonEncode(config),
        );

        // Should be forbidden or similar
        expect(response.statusCode, equals(HttpStatus.forbidden));
      });

      test('registration succeeds when command matches whitelist', () async {
        // Configure registry with whitelist
        final registry = await registryService.load();
        registry.remoteAccess = RemoteAccessConfig(
          startRemoteAccess: true,
          executableWhitelist: ['/usr/bin/*'],
          trustedHosts: ['localhost', '127.0.0.1'],
        );
        await registryService.save(registry);

        final config = {
          'id': 'allowed-process',
          'name': 'Allowed Process',
          'command': '/usr/bin/echo',
          'args': [],
          'autostart': false,
        };

        final response = await client.post(
          Uri.parse('http://localhost:$port/processes'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(config),
        );

        expect(response.statusCode, equals(HttpStatus.ok));
      });
    });
  });
}
