/// Auto-discovery for LedgerServer instances.
///
/// This library provides utilities to automatically discover a running
/// LedgerServer on the local network by scanning known addresses.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Result of a successful server discovery.
class DiscoveredServer {
  /// The URL of the discovered server.
  final String serverUrl;

  /// The server status response.
  final Map<String, dynamic> status;

  /// Creates a discovered server result.
  const DiscoveredServer({
    required this.serverUrl,
    required this.status,
  });

  /// The service name from the status response.
  String? get service => status['service'] as String?;

  /// The version from the status response.
  String? get version => status['version'] as String?;

  /// The port the server is running on.
  int? get port => status['port'] as int?;

  @override
  String toString() => 'DiscoveredServer($serverUrl)';
}

/// Options for server discovery.
class DiscoveryOptions {
  /// Port to scan for servers.
  final int port;

  /// Timeout for each connection attempt.
  final Duration timeout;

  /// Whether to scan the local subnet.
  final bool scanSubnet;

  /// Maximum concurrent connection attempts.
  final int maxConcurrent;

  /// Logger function for discovery progress.
  final void Function(String message)? logger;

  /// Creates discovery options.
  const DiscoveryOptions({
    this.port = 19880,
    this.timeout = const Duration(milliseconds: 500),
    this.scanSubnet = true,
    this.maxConcurrent = 20,
    this.logger,
  });
}

/// Discovers LedgerServer instances on the network.
///
/// The discovery process scans addresses in this order:
/// 1. localhost (127.0.0.1)
/// 2. 0.0.0.0
/// 3. Local machine's IP addresses
/// 4. Other addresses in the local subnet (xxx.xxx.xxx.1-255)
///
/// ## Usage
///
/// ```dart
/// final discovered = await ServerDiscovery.discover();
/// if (discovered != null) {
///   print('Found server at ${discovered.serverUrl}');
///   final client = RemoteLedgerClient(
///     serverUrl: discovered.serverUrl,
///     participantId: 'my_client',
///   );
/// }
/// ```
class ServerDiscovery {
  /// Discover a LedgerServer on the network.
  ///
  /// Returns the first discovered server, or null if none found.
  static Future<DiscoveredServer?> discover([
    DiscoveryOptions options = const DiscoveryOptions(),
  ]) async {
    final candidates = await _buildCandidateList(options);

    for (final url in candidates) {
      final result = await _tryConnect(url, options);
      if (result != null) {
        return result;
      }
    }

    return null;
  }

  /// Discover all LedgerServers on the network.
  ///
  /// Returns a list of all discovered servers.
  static Future<List<DiscoveredServer>> discoverAll([
    DiscoveryOptions options = const DiscoveryOptions(),
  ]) async {
    final candidates = await _buildCandidateList(options);
    final results = <DiscoveredServer>[];

    // Scan in batches for better performance
    for (var i = 0; i < candidates.length; i += options.maxConcurrent) {
      final batch = candidates.skip(i).take(options.maxConcurrent).toList();
      final futures =
          batch.map((url) => _tryConnect(url, options));
      final batchResults = await Future.wait(futures);

      for (final result in batchResults) {
        if (result != null) {
          results.add(result);
        }
      }
    }

    return results;
  }

  /// Build the list of candidate URLs to scan.
  static Future<List<String>> _buildCandidateList(
    DiscoveryOptions options,
  ) async {
    final candidates = <String>[];
    final port = options.port;

    // 1. Primary localhost addresses
    candidates.add('http://127.0.0.1:$port');
    candidates.add('http://localhost:$port');

    // 2. Get local machine's IP addresses
    final localIps = await _getLocalIpAddresses();
    for (final ip in localIps) {
      candidates.add('http://$ip:$port');
    }

    // 3. Scan subnet if enabled
    if (options.scanSubnet && localIps.isNotEmpty) {
      final subnetAddresses = _getSubnetAddresses(localIps.first);
      for (final ip in subnetAddresses) {
        final url = 'http://$ip:$port';
        if (!candidates.contains(url)) {
          candidates.add(url);
        }
      }
    }

    return candidates;
  }

  /// Get local IP addresses of the machine.
  static Future<List<String>> _getLocalIpAddresses() async {
    final addresses = <String>[];

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          // Skip loopback
          if (!addr.isLoopback) {
            addresses.add(addr.address);
          }
        }
      }
    } catch (_) {
      // Ignore errors getting network interfaces
    }

    return addresses;
  }

  /// Get all addresses in the /24 subnet of the given IP.
  static List<String> _getSubnetAddresses(String ip) {
    final addresses = <String>[];
    final parts = ip.split('.');

    if (parts.length != 4) return addresses;

    final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';

    // Scan 1-254 (skip 0 and 255)
    for (var i = 1; i < 255; i++) {
      final addr = '$prefix.$i';
      if (addr != ip) {
        // Skip our own IP (already added)
        addresses.add(addr);
      }
    }

    return addresses;
  }

  /// Try to connect to a server at the given URL.
  static Future<DiscoveredServer?> _tryConnect(
    String url,
    DiscoveryOptions options,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = options.timeout;

    try {
      final statusUrl = '$url/status';
      options.logger?.call('Trying $statusUrl...');

      final request = await client.getUrl(Uri.parse(statusUrl));
      final response = await request.close().timeout(options.timeout);

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = _parseJson(body);

        if (json != null && json['service'] == 'tom_dist_ledger') {
          options.logger?.call('Found server at $url');
          return DiscoveredServer(serverUrl: url, status: json);
        }
      }
    } on TimeoutException {
      // Expected for unreachable hosts
    } on SocketException {
      // Expected for unreachable hosts
    } on HttpException {
      // Connection issues
    } catch (_) {
      // Other errors
    } finally {
      client.close(force: true);
    }

    return null;
  }

  /// Parse JSON safely.
  static Map<String, dynamic>? _parseJson(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // Invalid JSON
    }
    return null;
  }
}
