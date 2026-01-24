import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_process_monitor/tom_process_monitor.dart';

void main() {
  group('AlivenessChecker', () {
    late AlivenessChecker checker;
    late HttpServer server;
    late int port;

    setUp(() async {
      checker = AlivenessChecker();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
    });

    tearDown(() async {
      checker.dispose();
      await server.close(force: true);
    });

    test('checkAlive returns true for OK response', () async {
      server.listen((request) {
        request.response
          ..statusCode = HttpStatus.ok
          ..write('OK');
        request.response.close();
      });

      final result = await checker.checkAlive('http://localhost:$port/alive');
      expect(result, isTrue);
    });

    test('checkAlive returns false for non-OK body', () async {
      server.listen((request) {
        request.response
          ..statusCode = HttpStatus.ok
          ..write('NOT OK');
        request.response.close();
      });

      final result = await checker.checkAlive('http://localhost:$port/alive');
      expect(result, isFalse);
    });

    test('checkAlive returns false for non-200 status', () async {
      server.listen((request) {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write('OK');
        request.response.close();
      });

      final result = await checker.checkAlive('http://localhost:$port/alive');
      expect(result, isFalse);
    });

    test('checkAlive returns false on connection error', () async {
      await server.close(force: true);

      final result = await checker.checkAlive('http://localhost:$port/alive');
      expect(result, isFalse);
    });

    test('checkAlive respects timeout', () async {
      server.listen((request) async {
        await Future<void>.delayed(const Duration(seconds: 5));
        request.response
          ..statusCode = HttpStatus.ok
          ..write('OK');
        request.response.close();
      });

      final result = await checker.checkAlive(
        'http://localhost:$port/alive',
        timeout: const Duration(milliseconds: 100),
      );
      expect(result, isFalse);
    });

    test('fetchPid returns PID from JSON response', () async {
      server.listen((request) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'pid': 12345, 'state': 'running'}));
        request.response.close();
      });

      final pid = await checker.fetchPid('http://localhost:$port/status');
      expect(pid, equals(12345));
    });

    test('fetchPid returns null for invalid JSON', () async {
      server.listen((request) {
        request.response
          ..statusCode = HttpStatus.ok
          ..write('not json');
        request.response.close();
      });

      final pid = await checker.fetchPid('http://localhost:$port/status');
      expect(pid, isNull);
    });

    test('fetchPid returns null on error', () async {
      await server.close(force: true);

      final pid = await checker.fetchPid('http://localhost:$port/status');
      expect(pid, isNull);
    });

    test('fetchStatus returns full status map', () async {
      final statusData = {
        'instanceId': 'default',
        'pid': 54321,
        'state': 'running',
        'uptime': 3600,
      };

      server.listen((request) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(statusData));
        request.response.close();
      });

      final status = await checker.fetchStatus('http://localhost:$port/status');
      expect(status, isNotNull);
      expect(status!['instanceId'], equals('default'));
      expect(status['pid'], equals(54321));
      expect(status['state'], equals('running'));
    });

    test('fetchStatus returns null on error', () async {
      await server.close(force: true);

      final status = await checker.fetchStatus('http://localhost:$port/status');
      expect(status, isNull);
    });
  });
}
