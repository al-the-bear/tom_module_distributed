import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../exceptions/permission_denied_exception.dart';
import '../exceptions/process_not_found_exception.dart';
import '../models/monitor_status.dart';
import '../models/partner_discovery_config.dart';
import '../models/process_config.dart';
import '../models/process_status.dart';

/// Exception thrown when auto-discovery fails to find a ProcessMonitor instance.
class DiscoveryFailedException implements Exception {
  final String message;
  DiscoveryFailedException(this.message);

  @override
  String toString() => 'DiscoveryFailedException: $message';
}

/// Remote client API for interacting with ProcessMonitor via HTTP.
class RemoteProcessMonitorClient {
  /// Base URL of the ProcessMonitor HTTP API.
  final String baseUrl;

  final http.Client _client;

  /// Creates a remote process monitor client.
  RemoteProcessMonitorClient({String? baseUrl})
    : baseUrl = baseUrl ?? 'http://localhost:5679',
      _client = http.Client();

  /// Auto-discover a ProcessMonitor instance.
  ///
  /// Discovery order:
  /// 1. Try localhost on default port (5679)
  /// 2. Try 127.0.0.1 on default port
  /// 3. Scan local subnet for ProcessMonitor instances
  ///
  /// Throws [DiscoveryFailedException] if no instance is found.
  static Future<RemoteProcessMonitorClient> discover({
    int port = 5679,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final client = http.Client();

    try {
      // List of URLs to try
      final candidateUrls = <String>[
        'http://localhost:$port',
        'http://127.0.0.1:$port',
        'http://0.0.0.0:$port',
      ];

      // Add local network addresses if we can determine them
      try {
        final interfaces = await NetworkInterface.list();
        for (final interface in interfaces) {
          for (final addr in interface.addresses) {
            if (addr.type == InternetAddressType.IPv4) {
              // Get subnet (assume /24 for simplicity)
              final parts = addr.address.split('.');
              if (parts.length == 4) {
                final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
                // Add common gateway addresses
                candidateUrls.add('http://$subnet.1:$port');
                // Add own address
                candidateUrls.add('http://${addr.address}:$port');
              }
            }
          }
        }
      } catch (_) {
        // Ignore network interface errors
      }

      // Try each candidate
      for (final url in candidateUrls) {
        if (await _tryConnect(client, url, timeout)) {
          return RemoteProcessMonitorClient(baseUrl: url);
        }
      }

      throw DiscoveryFailedException(
        'No ProcessMonitor instance found. Tried: ${candidateUrls.join(', ')}',
      );
    } finally {
      // Don't close client here - the returned RemoteProcessMonitorClient
      // will create its own client
    }
  }

  /// Scans a subnet for ProcessMonitor instances.
  ///
  /// [subnet] should be in format "192.168.1" (first 3 octets).
  /// Returns list of URLs where ProcessMonitor is responding.
  static Future<List<String>> scanSubnet(
    String subnet, {
    int port = 5679,
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    final client = http.Client();
    final found = <String>[];

    try {
      // Scan in parallel batches to avoid too many connections
      final batchSize = 20;
      for (var start = 1; start < 255; start += batchSize) {
        final end = (start + batchSize).clamp(1, 255);
        final futures = <Future<bool>>[];
        final urls = <String>[];

        for (var i = start; i < end; i++) {
          final url = 'http://$subnet.$i:$port';
          urls.add(url);
          futures.add(_tryConnect(client, url, timeout));
        }

        final results = await Future.wait(futures);
        for (var i = 0; i < results.length; i++) {
          if (results[i]) {
            found.add(urls[i]);
          }
        }
      }
    } finally {
      client.close();
    }

    return found;
  }

  static Future<bool> _tryConnect(
    http.Client client,
    String url,
    Duration timeout,
  ) async {
    try {
      final response = await client
          .get(Uri.parse('$url/monitor/status'))
          .timeout(timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Disposes the client.
  void dispose() {
    _client.close();
  }

  // --- Registration ---

  /// Register a new remote process.
  Future<void> register(ProcessConfig config) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/processes'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(config.toJson()),
    );

    _checkResponse(response);
  }

  /// Remove a remote process from the registry.
  Future<void> deregister(String processId) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/processes/$processId'),
    );

    _checkResponse(response);
  }

  // --- Enable/Disable ---

  /// Enable a remote process.
  Future<void> enable(String processId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/processes/$processId/enable'),
    );

    _checkResponse(response);
  }

  /// Disable a remote process.
  Future<void> disable(String processId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/processes/$processId/disable'),
    );

    _checkResponse(response);
  }

  // --- Autostart ---

  /// Set autostart for a remote process.
  Future<void> setAutostart(String processId, bool autostart) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/processes/$processId/autostart'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'autostart': autostart}),
    );

    _checkResponse(response);
  }

  // --- Process Control ---

  /// Start a remote process.
  Future<void> start(String processId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/processes/$processId/start'),
    );

    _checkResponse(response);
  }

  /// Stop a remote process.
  Future<void> stop(String processId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/processes/$processId/stop'),
    );

    _checkResponse(response);
  }

  /// Restart a remote process.
  Future<void> restart(String processId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/processes/$processId/restart'),
    );

    _checkResponse(response);
  }

  // --- Status ---

  /// Get status of a specific process.
  Future<ProcessStatus> getStatus(String processId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/processes/$processId'),
    );

    _checkResponse(response);
    return ProcessStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Get status of all processes.
  Future<Map<String, ProcessStatus>> getAllStatus() async {
    final response = await _client.get(Uri.parse('$baseUrl/processes'));

    _checkResponse(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final processes = data['processes'] as List<dynamic>;

    return {
      for (final p in processes)
        (p as Map<String, dynamic>)['id'] as String: ProcessStatus.fromJson(p),
    };
  }

  /// Get ProcessMonitor instance status.
  Future<MonitorStatus> getMonitorStatus() async {
    final response = await _client.get(Uri.parse('$baseUrl/monitor/status'));

    _checkResponse(response);
    return MonitorStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  // --- Remote Access Configuration ---

  /// Set remote access permissions.
  Future<void> setRemoteAccessPermissions({
    bool? allowRegister,
    bool? allowDeregister,
    bool? allowStart,
    bool? allowStop,
    bool? allowDisable,
    bool? allowAutostart,
    bool? allowMonitorRestart,
  }) async {
    final body = <String, dynamic>{};
    if (allowRegister != null) body['allowRemoteRegister'] = allowRegister;
    if (allowDeregister != null)
      body['allowRemoteDeregister'] = allowDeregister;
    if (allowStart != null) body['allowRemoteStart'] = allowStart;
    if (allowStop != null) body['allowRemoteStop'] = allowStop;
    if (allowDisable != null) body['allowRemoteDisable'] = allowDisable;
    if (allowAutostart != null) body['allowRemoteAutostart'] = allowAutostart;
    if (allowMonitorRestart != null) {
      body['allowRemoteMonitorRestart'] = allowMonitorRestart;
    }

    final response = await _client.put(
      Uri.parse('$baseUrl/config/remote-access'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    _checkResponse(response);
  }

  /// Set trusted hosts list.
  Future<void> setTrustedHosts(List<String> hosts) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/config/trusted-hosts'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'trustedHosts': hosts}),
    );

    _checkResponse(response);
  }

  /// Get trusted hosts list.
  Future<List<String>> getTrustedHosts() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/config/trusted-hosts'),
    );

    _checkResponse(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['trustedHosts'] as List<dynamic>)
        .map((e) => e as String)
        .toList();
  }

  // --- Executable Filtering ---

  /// Get the current executable whitelist.
  Future<List<String>> getRemoteExecutableWhitelist() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/config/executable-whitelist'),
    );

    _checkResponse(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['patterns'] as List<dynamic>).map((e) => e as String).toList();
  }

  /// Set the executable whitelist.
  Future<void> setRemoteExecutableWhitelist(List<String> patterns) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/config/executable-whitelist'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'patterns': patterns}),
    );

    _checkResponse(response);
  }

  /// Get the current executable blacklist.
  Future<List<String>> getRemoteExecutableBlacklist() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/config/executable-blacklist'),
    );

    _checkResponse(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['patterns'] as List<dynamic>).map((e) => e as String).toList();
  }

  /// Set the executable blacklist.
  Future<void> setRemoteExecutableBlacklist(List<String> patterns) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/config/executable-blacklist'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'patterns': patterns}),
    );

    _checkResponse(response);
  }

  // --- Standalone / Partner Configuration ---

  /// Enable or disable standalone mode.
  Future<void> setStandaloneMode(bool enabled) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/config/standalone-mode'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'enabled': enabled}),
    );

    _checkResponse(response);
  }

  /// Get current standalone mode setting.
  Future<bool> isStandaloneMode() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/config/standalone-mode'),
    );

    _checkResponse(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['enabled'] as bool;
  }

  /// Get partner discovery configuration.
  Future<PartnerDiscoveryConfig> getPartnerDiscoveryConfig() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/config/partner-discovery'),
    );

    _checkResponse(response);
    return PartnerDiscoveryConfig.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Set partner discovery configuration.
  Future<void> setPartnerDiscoveryConfig(PartnerDiscoveryConfig config) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/config/partner-discovery'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(config.toJson()),
    );

    _checkResponse(response);
  }

  // --- Monitor Control ---

  /// Restart the ProcessMonitor itself.
  Future<void> restartMonitor() async {
    final response = await _client.post(Uri.parse('$baseUrl/monitor/restart'));

    _checkResponse(response);
  }

  void _checkResponse(http.Response response) {
    if (response.statusCode == 403) {
      throw PermissionDeniedException(response.body);
    }
    if (response.statusCode == 404) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw ProcessNotFoundException(body['processId'] as String? ?? 'unknown');
    }
    if (response.statusCode >= 400) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }
}
