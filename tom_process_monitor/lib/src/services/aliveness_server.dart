import 'dart:convert';
import 'dart:io';

import '../models/monitor_status.dart';

/// HTTP server for aliveness checks.
class AlivenessServer {
  /// Server port.
  final int port;

  /// Function to get current monitor status.
  final Future<MonitorStatus> Function() getStatus;

  HttpServer? _server;

  /// Creates an aliveness server.
  AlivenessServer({required this.port, required this.getStatus});

  /// Whether the server is running.
  bool get isRunning => _server != null;

  /// Starts the server.
  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_handleRequest);
  }

  /// Stops the server.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      // Add CORS headers
      request.response.headers.add('Access-Control-Allow-Origin', '*');
      request.response.headers.add(
        'Access-Control-Allow-Methods',
        'GET, POST, OPTIONS',
      );
      request.response.headers.add(
        'Access-Control-Allow-Headers',
        'Origin, Content-Type, X-Auth-Token',
      );

      // Handle preflight requests
      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        return;
      }

      if (request.method == 'GET') {
        switch (request.uri.path) {
          case '/alive':
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.text
              ..write('OK');
          case '/status':
            final status = await getStatus();
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode(status.toJson()));
          default:
            request.response
              ..statusCode = HttpStatus.notFound
              ..write('Not Found');
        }
      } else {
        request.response
          ..statusCode = HttpStatus.methodNotAllowed
          ..write('Method Not Allowed');
      }
    } finally {
      await request.response.close();
    }
  }
}
