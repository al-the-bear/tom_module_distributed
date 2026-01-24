import 'dart:convert';

import 'package:http/http.dart' as http;

import '../exceptions/permission_denied_exception.dart';
import '../exceptions/process_not_found_exception.dart';
import '../models/monitor_status.dart';
import '../models/partner_discovery_config.dart';
import '../models/process_config.dart';
import '../models/process_status.dart';

/// Remote client API for interacting with ProcessMonitor via HTTP.
class RemoteProcessMonitorClient {
  /// Base URL of the ProcessMonitor HTTP API.
  final String baseUrl;

  final http.Client _client;

  /// Creates a remote process monitor client.
  RemoteProcessMonitorClient({String? baseUrl})
      : baseUrl = baseUrl ?? 'http://localhost:5679',
        _client = http.Client();

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
    final response = await _client.get(
      Uri.parse('$baseUrl/processes'),
    );

    _checkResponse(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final processes = data['processes'] as List<dynamic>;

    return {
      for (final p in processes)
        (p as Map<String, dynamic>)['id'] as String:
            ProcessStatus.fromJson(p),
    };
  }

  /// Get ProcessMonitor instance status.
  Future<MonitorStatus> getMonitorStatus() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/monitor/status'),
    );

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
    if (allowDeregister != null) body['allowRemoteDeregister'] = allowDeregister;
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
    return (data['patterns'] as List<dynamic>)
        .map((e) => e as String)
        .toList();
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
    return (data['patterns'] as List<dynamic>)
        .map((e) => e as String)
        .toList();
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
    final response = await _client.post(
      Uri.parse('$baseUrl/monitor/restart'),
    );

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
