import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:tom_basics_network/tom_basics_network.dart';

import '../exceptions/permission_denied_exception.dart';
import '../exceptions/process_not_found_exception.dart';
import '../models/monitor_status.dart';
import '../models/partner_discovery_config.dart';
import '../models/process_config.dart';
import '../models/process_status.dart';
import '../models/remote_access_config.dart';
import 'process_monitor_base.dart';

/// Remote client API for interacting with ProcessMonitor via HTTP.
class RemoteProcessMonitorClient implements ProcessMonitorClient {
  /// Base URL of the ProcessMonitor HTTP API.
  final String baseUrl;

  @override
  final String instanceId;

  final http.Client _client;

  /// Creates a remote process monitor client.
  ///
  /// - [baseUrl]: The HTTP endpoint (defaults to 'http://localhost:19881')
  /// - [instanceId]: The target ProcessMonitor instance (defaults to 'default')
  RemoteProcessMonitorClient({
    String? baseUrl,
    this.instanceId = 'default',
  }) : baseUrl = baseUrl ?? 'http://localhost:19881',
       _client = http.Client();

  /// Auto-discover a ProcessMonitor instance.
  ///
  /// Uses the common [ServerDiscovery] to find a ProcessMonitor server.
  /// Discovery order:
  /// 1. Try localhost on default port (19881)
  /// 2. Try 127.0.0.1 on default port
  /// 3. Try all local machine IP addresses
  /// 4. Scan all /24 subnets for each local IP
  ///
  /// When the machine has multiple network interfaces (e.g., Ethernet and WiFi,
  /// or VPN connections), all subnets are scanned to find servers on any
  /// connected network.
  ///
  /// - [port]: The port to scan (defaults to 19881)
  /// - [timeout]: Connection timeout for discovery (defaults to 5 seconds)
  /// - [instanceId]: The target ProcessMonitor instance (defaults to 'default')
  ///
  /// Throws [DiscoveryFailedException] if no instance is found.
  static Future<RemoteProcessMonitorClient> discover({
    int port = 19881,
    Duration timeout = const Duration(seconds: 5),
    String instanceId = 'default',
  }) async {
    final discovered = await ServerDiscovery.discover(
      DiscoveryOptions(
        port: port,
        timeout: timeout,
        statusPath: '/monitor/status',
      ),
    );

    if (discovered == null) {
      throw DiscoveryFailedException(
        'No ProcessMonitor instance found on port $port',
      );
    }

    return RemoteProcessMonitorClient(
      baseUrl: discovered.serverUrl,
      instanceId: instanceId,
    );
  }

  /// Scans a subnet for ProcessMonitor instances.
  ///
  /// [subnet] should be in format "192.168.1" (first 3 octets).
  /// Returns list of URLs where ProcessMonitor is responding.
  static Future<List<String>> scanSubnet(
    String subnet, {
    int port = 19881,
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    // Build candidate list for this subnet only
    final candidates = <String>[];
    for (var i = 1; i < 255; i++) {
      candidates.add('http://$subnet.$i:$port');
    }

    final results = await ServerDiscovery.discoverAll(
      DiscoveryOptions(
        port: port,
        timeout: timeout,
        scanSubnet: false, // We're providing specific candidates
        statusPath: '/monitor/status',
      ),
    );

    return results.map((s) => s.serverUrl).toList();
  }

  /// Disposes the client.
  @override
  void dispose() {
    _client.close();
  }

  // --- Registration ---

  /// Register a new remote process.
  @override
  Future<void> register(ProcessConfig config) async {
    final response = await _postWithRetry(
      Uri.parse('$baseUrl/processes'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(config.toJson()),
    );

    _checkResponse(response);
  }

  /// Remove a remote process from the registry.
  @override
  Future<void> deregister(String processId) async {
    final response = await _deleteWithRetry(
      Uri.parse('$baseUrl/processes/$processId'),
    );

    _checkResponse(response);
  }

  // --- Enable/Disable ---

  /// Enable a remote process.
  @override
  Future<void> enable(String processId) async {
    final response = await _postWithRetry(
      Uri.parse('$baseUrl/processes/$processId/enable'),
    );

    _checkResponse(response);
  }

  /// Disable a remote process.
  @override
  Future<void> disable(String processId) async {
    final response = await _postWithRetry(
      Uri.parse('$baseUrl/processes/$processId/disable'),
    );

    _checkResponse(response);
  }

  // --- Autostart ---

  /// Set autostart for a remote process.
  @override
  Future<void> setAutostart(String processId, bool autostart) async {
    final response = await _putWithRetry(
      Uri.parse('$baseUrl/processes/$processId/autostart'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'autostart': autostart}),
    );

    _checkResponse(response);
  }

  // --- Process Control ---

  /// Start a remote process.
  @override
  Future<void> start(String processId) async {
    final response = await _postWithRetry(
      Uri.parse('$baseUrl/processes/$processId/start'),
    );

    _checkResponse(response);
  }

  /// Stop a remote process.
  @override
  Future<void> stop(String processId) async {
    final response = await _postWithRetry(
      Uri.parse('$baseUrl/processes/$processId/stop'),
    );

    _checkResponse(response);
  }

  /// Restart a remote process.
  @override
  Future<void> restart(String processId) async {
    final response = await _postWithRetry(
      Uri.parse('$baseUrl/processes/$processId/restart'),
    );

    _checkResponse(response);
  }

  // --- Status ---

  /// Get status of a specific process.
  @override
  Future<ProcessStatus> getStatus(String processId) async {
    final response = await _getWithRetry(
      Uri.parse('$baseUrl/processes/$processId'),
    );

    _checkResponse(response);
    return ProcessStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Get status of all processes.
  @override
  Future<Map<String, ProcessStatus>> getAllStatus() async {
    final response = await _getWithRetry(Uri.parse('$baseUrl/processes'));

    _checkResponse(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final processes = data['processes'] as List<dynamic>;

    return {
      for (final p in processes)
        (p as Map<String, dynamic>)['id'] as String: ProcessStatus.fromJson(p),
    };
  }

  /// Get ProcessMonitor instance status.
  @override
  Future<MonitorStatus> getMonitorStatus() async {
    final response = await _getWithRetry(Uri.parse('$baseUrl/monitor/status'));

    _checkResponse(response);
    return MonitorStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  // --- Remote Access Configuration ---

  /// Enable or disable remote HTTP API access.
  @override
  Future<void> setRemoteAccess(bool enabled) async {
    final response = await _putWithRetry(
      Uri.parse('$baseUrl/config/remote-access'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'startRemoteAccess': enabled}),
    );

    _checkResponse(response);
  }

  /// Get current remote access configuration.
  @override
  Future<RemoteAccessConfig> getRemoteAccessConfig() async {
    final response = await _getWithRetry(
      Uri.parse('$baseUrl/config/remote-access'),
    );

    _checkResponse(response);
    return RemoteAccessConfig.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Set remote access permissions.
  @override
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

    final response = await _putWithRetry(
      Uri.parse('$baseUrl/config/remote-access'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    _checkResponse(response);
  }

  /// Set trusted hosts list.
  @override
  Future<void> setTrustedHosts(List<String> hosts) async {
    final response = await _putWithRetry(
      Uri.parse('$baseUrl/config/trusted-hosts'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'trustedHosts': hosts}),
    );

    _checkResponse(response);
  }

  /// Get trusted hosts list.
  @override
  Future<List<String>> getTrustedHosts() async {
    final response = await _getWithRetry(
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
  @override
  Future<List<String>> getRemoteExecutableWhitelist() async {
    final response = await _getWithRetry(
      Uri.parse('$baseUrl/config/executable-whitelist'),
    );

    _checkResponse(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['patterns'] as List<dynamic>).map((e) => e as String).toList();
  }

  /// Set the executable whitelist.
  @override
  Future<void> setRemoteExecutableWhitelist(List<String> patterns) async {
    final response = await _putWithRetry(
      Uri.parse('$baseUrl/config/executable-whitelist'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'patterns': patterns}),
    );

    _checkResponse(response);
  }

  /// Get the current executable blacklist.
  @override
  Future<List<String>> getRemoteExecutableBlacklist() async {
    final response = await _getWithRetry(
      Uri.parse('$baseUrl/config/executable-blacklist'),
    );

    _checkResponse(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['patterns'] as List<dynamic>).map((e) => e as String).toList();
  }

  /// Set the executable blacklist.
  @override
  Future<void> setRemoteExecutableBlacklist(List<String> patterns) async {
    final response = await _putWithRetry(
      Uri.parse('$baseUrl/config/executable-blacklist'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'patterns': patterns}),
    );

    _checkResponse(response);
  }

  // --- Standalone / Partner Configuration ---

  /// Enable or disable standalone mode.
  @override
  Future<void> setStandaloneMode(bool enabled) async {
    final response = await _putWithRetry(
      Uri.parse('$baseUrl/config/standalone-mode'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'enabled': enabled}),
    );

    _checkResponse(response);
  }

  /// Get current standalone mode setting.
  @override
  Future<bool> isStandaloneMode() async {
    final response = await _getWithRetry(
      Uri.parse('$baseUrl/config/standalone-mode'),
    );

    _checkResponse(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['enabled'] as bool;
  }

  /// Get partner discovery configuration.
  @override
  Future<PartnerDiscoveryConfig> getPartnerDiscoveryConfig() async {
    final response = await _getWithRetry(
      Uri.parse('$baseUrl/config/partner-discovery'),
    );

    _checkResponse(response);
    return PartnerDiscoveryConfig.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Set partner discovery configuration.
  @override
  Future<void> setPartnerDiscoveryConfig(PartnerDiscoveryConfig config) async {
    final response = await _putWithRetry(
      Uri.parse('$baseUrl/config/partner-discovery'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(config.toJson()),
    );

    _checkResponse(response);
  }

  // --- Monitor Control ---

  /// Restart the ProcessMonitor itself.
  @override
  Future<void> restartMonitor() async {
    final response = await _postWithRetry(Uri.parse('$baseUrl/monitor/restart'));

    _checkResponse(response);
  }

  // --- Private HTTP helpers with retry ---

  Future<http.Response> _getWithRetry(Uri uri) async {
    return withRetry(() => _client.get(uri));
  }

  Future<http.Response> _postWithRetry(
    Uri uri, {
    Map<String, String>? headers,
    String? body,
  }) async {
    return withRetry(() => _client.post(uri, headers: headers, body: body));
  }

  Future<http.Response> _putWithRetry(
    Uri uri, {
    Map<String, String>? headers,
    String? body,
  }) async {
    return withRetry(() => _client.put(uri, headers: headers, body: body));
  }

  Future<http.Response> _deleteWithRetry(Uri uri) async {
    return withRetry(() => _client.delete(uri));
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
