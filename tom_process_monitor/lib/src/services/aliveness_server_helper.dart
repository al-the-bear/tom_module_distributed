import 'dart:convert';
import 'dart:io';

/// Callback interface for aliveness server events.
class AlivenessCallback {
  /// Called when a health check is requested.
  /// Return true if healthy, false otherwise.
  final Future<bool> Function()? onHealthCheck;

  /// Called when status is requested.
  /// Return a map of status information.
  final Future<Map<String, dynamic>> Function()? onStatusRequest;

  /// Creates an aliveness callback.
  const AlivenessCallback({this.onHealthCheck, this.onStatusRequest});
}

/// Helper class for managed processes to expose aliveness endpoints.
///
/// This provides a simple HTTP server that exposes health check and status
/// endpoints, making it easy for ProcessMonitor to monitor process health.
///
/// Example:
/// ```dart
/// final aliveness = AlivenessServerHelper(
///   port: 8080,
///   callback: AlivenessCallback(
///     onHealthCheck: () async => database.isConnected,
///     onStatusRequest: () async => {'version': '1.0.0'},
///   ),
/// );
/// await aliveness.start();
/// ```
class AlivenessServerHelper {
  /// Server port.
  final int port;

  /// Callback for health and status requests.
  final AlivenessCallback callback;

  /// Optional custom routes.
  final Map<String, Future<void> Function(HttpRequest)> _customRoutes = {};

  HttpServer? _server;

  /// Creates an aliveness server helper.
  AlivenessServerHelper({
    required this.port,
    this.callback = const AlivenessCallback(),
  });

  /// Whether the server is running.
  bool get isRunning => _server != null;

  /// Adds a custom route handler.
  ///
  /// Example:
  /// ```dart
  /// aliveness.addRoute('/metrics', (request) async {
  ///   request.response
  ///     ..statusCode = HttpStatus.ok
  ///     ..write('# HELP requests_total Total requests\n');
  ///   await request.response.close();
  /// });
  /// ```
  void addRoute(String path, Future<void> Function(HttpRequest) handler) {
    _customRoutes[path] = handler;
  }

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
      if (request.method == 'GET') {
        final path = request.uri.path;

        // Check custom routes first
        if (_customRoutes.containsKey(path)) {
          await _customRoutes[path]!(request);
          return;
        }

        switch (path) {
          case '/health':
            await _handleHealthCheck(request);
          case '/status':
            await _handleStatusRequest(request);
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
    } catch (e) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write('Internal Server Error: $e');
    } finally {
      await request.response.close();
    }
  }

  Future<void> _handleHealthCheck(HttpRequest request) async {
    bool isHealthy = true;

    if (callback.onHealthCheck != null) {
      try {
        isHealthy = await callback.onHealthCheck!();
      } catch (e) {
        isHealthy = false;
      }
    }

    request.response
      ..statusCode = isHealthy ? HttpStatus.ok : HttpStatus.serviceUnavailable
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'healthy': isHealthy,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        }),
      );
  }

  Future<void> _handleStatusRequest(HttpRequest request) async {
    Map<String, dynamic> status = {};

    if (callback.onStatusRequest != null) {
      try {
        status = await callback.onStatusRequest!();
      } catch (e) {
        status = {'error': e.toString()};
      }
    }

    // Add standard fields
    status['timestamp'] = DateTime.now().toUtc().toIso8601String();
    status['pid'] = pid;

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(status));
  }
}
