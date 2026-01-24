import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_process_monitor/tom_process_monitor.dart';

void main() {
  late AlivenessServer server;
  late int testPort;

  setUp(() async {
    // Find an available port
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    testPort = socket.port;
    await socket.close();

    server = AlivenessServer(
      port: testPort,
      getStatus: () async => MonitorStatus(
        instanceId: 'test',
        pid: pid,
        startedAt: DateTime.now(),
        uptime: 100,
        state: 'running',
        standaloneMode: false,
        managedProcessCount: 5,
        runningProcessCount: 3,
      ),
    );
  });

  tearDown(() async {
    await server.stop();
  });

  group('AlivenessServer', () {
    test('starts and stops correctly', () async {
      expect(server.isRunning, isFalse);

      await server.start();
      expect(server.isRunning, isTrue);

      await server.stop();
      expect(server.isRunning, isFalse);
    });

    test('responds to /alive endpoint', () async {
      await server.start();

      final client = HttpClient();
      final request = await client.get('localhost', testPort, '/alive');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      expect(response.statusCode, equals(HttpStatus.ok));
      expect(body, equals('OK'));

      client.close();
    });

    test('responds to /status endpoint with JSON', () async {
      await server.start();

      final client = HttpClient();
      final request = await client.get('localhost', testPort, '/status');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      expect(response.statusCode, equals(HttpStatus.ok));

      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['instanceId'], equals('test'));
      expect(json['state'], equals('running'));
      expect(json['managedProcessCount'], equals(5));
      expect(json['runningProcessCount'], equals(3));

      client.close();
    });

    test('returns 404 for unknown endpoints', () async {
      await server.start();

      final client = HttpClient();
      final request = await client.get('localhost', testPort, '/unknown');
      final response = await request.close();

      expect(response.statusCode, equals(HttpStatus.notFound));

      client.close();
    });

    test('returns 405 for non-GET requests', () async {
      await server.start();

      final client = HttpClient();
      final request = await client.post('localhost', testPort, '/alive');
      final response = await request.close();

      expect(response.statusCode, equals(HttpStatus.methodNotAllowed));

      client.close();
    });
  });
}
