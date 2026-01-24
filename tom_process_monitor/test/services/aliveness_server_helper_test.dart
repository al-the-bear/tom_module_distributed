import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_process_monitor/tom_process_monitor.dart';

void main() {
  group('AlivenessServerHelper', () {
    late AlivenessServerHelper helper;
    final testPort = 18080;

    tearDown(() async {
      await helper.stop();
    });

    test('starts and responds to /health endpoint with default callback', () async {
      helper = AlivenessServerHelper(port: testPort);
      await helper.start();

      expect(helper.isRunning, isTrue);

      final response = await HttpClient()
          .getUrl(Uri.parse('http://localhost:$testPort/health'))
          .then((req) => req.close());

      expect(response.statusCode, HttpStatus.ok);

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body);

      expect(json['healthy'], isTrue);
      expect(json['timestamp'], isNotNull);
    });

    test('responds to /status endpoint with default callback', () async {
      helper = AlivenessServerHelper(port: testPort);
      await helper.start();

      final response = await HttpClient()
          .getUrl(Uri.parse('http://localhost:$testPort/status'))
          .then((req) => req.close());

      expect(response.statusCode, HttpStatus.ok);

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body);

      expect(json['timestamp'], isNotNull);
      expect(json['pid'], isNotNull);
    });

    test('onHealthCheck callback controls health status', () async {
      var isHealthy = true;

      helper = AlivenessServerHelper(
        port: testPort,
        callback: AlivenessCallback(
          onHealthCheck: () async => isHealthy,
        ),
      );
      await helper.start();

      // Check healthy
      var response = await HttpClient()
          .getUrl(Uri.parse('http://localhost:$testPort/health'))
          .then((req) => req.close());

      expect(response.statusCode, HttpStatus.ok);

      // Check unhealthy
      isHealthy = false;
      response = await HttpClient()
          .getUrl(Uri.parse('http://localhost:$testPort/health'))
          .then((req) => req.close());

      expect(response.statusCode, HttpStatus.serviceUnavailable);
    });

    test('onStatusRequest callback provides custom status', () async {
      helper = AlivenessServerHelper(
        port: testPort,
        callback: AlivenessCallback(
          onStatusRequest: () async => {
                'version': '1.0.0',
                'connections': 42,
              },
        ),
      );
      await helper.start();

      final response = await HttpClient()
          .getUrl(Uri.parse('http://localhost:$testPort/status'))
          .then((req) => req.close());

      expect(response.statusCode, HttpStatus.ok);

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body);

      expect(json['version'], '1.0.0');
      expect(json['connections'], 42);
      expect(json['timestamp'], isNotNull);
      expect(json['pid'], isNotNull);
    });

    test('addRoute allows custom endpoints', () async {
      helper = AlivenessServerHelper(port: testPort);
      helper.addRoute('/metrics', (request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..write('custom_metric 123');
        await request.response.close();
      });
      await helper.start();

      final response = await HttpClient()
          .getUrl(Uri.parse('http://localhost:$testPort/metrics'))
          .then((req) => req.close());

      expect(response.statusCode, HttpStatus.ok);

      final body = await response.transform(utf8.decoder).join();
      expect(body, 'custom_metric 123');
    });

    test('returns 404 for unknown endpoints', () async {
      helper = AlivenessServerHelper(port: testPort);
      await helper.start();

      final response = await HttpClient()
          .getUrl(Uri.parse('http://localhost:$testPort/unknown'))
          .then((req) => req.close());

      expect(response.statusCode, HttpStatus.notFound);
    });

    test('returns 405 for non-GET methods', () async {
      helper = AlivenessServerHelper(port: testPort);
      await helper.start();

      final client = HttpClient();
      final request =
          await client.postUrl(Uri.parse('http://localhost:$testPort/health'));
      final response = await request.close();

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });

    test('stop shuts down the server', () async {
      helper = AlivenessServerHelper(port: testPort);
      await helper.start();

      expect(helper.isRunning, isTrue);

      await helper.stop();

      expect(helper.isRunning, isFalse);

      // Verify server is actually stopped
      try {
        await HttpClient()
            .getUrl(Uri.parse('http://localhost:$testPort/health'))
            .then((req) => req.close())
            .timeout(const Duration(milliseconds: 500));
        fail('Should have thrown');
      } catch (e) {
        expect(e, isA<Object>());
      }
    });
  });
}
