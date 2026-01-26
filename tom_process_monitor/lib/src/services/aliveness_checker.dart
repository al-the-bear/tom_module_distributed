import 'dart:convert';

import 'package:http/http.dart' as http;

/// Service for checking HTTP aliveness endpoints.
class AlivenessChecker {
  final http.Client _client;

  /// Optional logger for debugging failed health checks.
  final void Function(String message)? logger;

  /// Creates an aliveness checker.
  ///
  /// If [logger] is provided, failed aliveness checks will be logged
  /// for debugging purposes.
  AlivenessChecker({this.logger}) : _client = http.Client();

  /// Disposes the checker.
  void dispose() {
    _client.close();
  }

  /// Checks if a URL is alive.
  ///
  /// Supports multiple response formats:
  /// - Plain text: `"OK"`
  /// - JSON with status: `{"status": "ok"}` or `{"status": "OK"}`
  /// - JSON with healthy: `{"healthy": true}`
  ///
  /// Returns true if HTTP 200 and response indicates healthy.
  Future<bool> checkAlive(String url, {Duration? timeout}) async {
    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(timeout ?? const Duration(milliseconds: 2000));

      if (response.statusCode != 200) return false;

      final body = response.body.trim();

      // Plain text "OK"
      if (body == 'OK') return true;

      // Try JSON parsing
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;

        // {"status": "ok"} or {"status": "OK"}
        final status = json['status'] as String?;
        if (status != null && status.toLowerCase() == 'ok') return true;

        // {"healthy": true}
        final healthy = json['healthy'] as bool?;
        if (healthy == true) return true;
      } catch (_) {
        // Not valid JSON, fall through
      }

      return false;
    } catch (e) {
      logger?.call('Aliveness check failed for $url: $e');
      return false;
    }
  }

  /// Fetches status from a URL and returns the PID if available.
  Future<int?> fetchPid(String url, {Duration? timeout}) async {
    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(timeout ?? const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['pid'] as int?;
      }
    } catch (e) {
      logger?.call('Failed to fetch PID from $url: $e');
    }
    return null;
  }

  /// Fetches full status from a URL.
  Future<Map<String, dynamic>?> fetchStatus(
    String url, {
    Duration? timeout,
  }) async {
    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(timeout ?? const Duration(seconds: 2));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      logger?.call('Failed to fetch status from $url: $e');
    }
    return null;
  }
}
