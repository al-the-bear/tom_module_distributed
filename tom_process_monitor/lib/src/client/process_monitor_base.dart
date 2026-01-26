// Copyright 2025 Tom2 Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import '../models/monitor_status.dart';
import '../models/partner_discovery_config.dart';
import '../models/process_config.dart';
import '../models/process_status.dart';
import '../models/remote_access_config.dart';
import 'local_process_monitor_client.dart';
import 'remote_process_monitor_client.dart';

/// Abstract base class for process monitor clients.
///
/// Provides a unified interface for managing processes through both local
/// file-based and remote HTTP-based clients. Use the [connect] static method
/// to create an appropriate implementation based on your configuration.
///
/// ## Usage
///
/// ```dart
/// // Auto-discover a remote ProcessMonitor (default behavior)
/// final monitor = await ProcessMonitorClient.connect();
///
/// // Local connection
/// final monitor = await ProcessMonitorClient.connect(
///   directory: '/var/process_monitor',
///   instanceId: 'my-instance',
/// );
///
/// // Remote connection with explicit URL
/// final monitor = await ProcessMonitorClient.connect(
///   baseUrl: 'http://192.168.1.100:8080',
/// );
///
/// // Register and start a process
/// await monitor.register(ProcessConfig(
///   processId: 'my-app',
///   executable: '/usr/bin/my-app',
/// ));
/// await monitor.start('my-app');
/// ```
abstract class ProcessMonitorClient {
  /// The ProcessMonitor instance ID this client is targeting.
  String get instanceId;

  /// Creates a ProcessMonitorClient instance based on the provided parameters.
  ///
  /// Connection modes (in priority order):
  /// 1. If [directory] is provided, creates a local [LocalProcessMonitorClient]
  ///    that communicates via file-based registry.
  /// 2. If [baseUrl] is provided, creates a [RemoteProcessMonitorClient]
  ///    that communicates via HTTP to the specified endpoint.
  /// 3. If neither is provided, uses [RemoteProcessMonitorClient.discover()]
  ///    to auto-discover a ProcessMonitor instance on the network.
  ///
  /// Parameters:
  /// - [instanceId]: The ProcessMonitor instance to target (defaults to 'default')
  /// - [directory]: Path to the local ProcessMonitor directory (for local mode)
  /// - [baseUrl]: HTTP endpoint for remote ProcessMonitor server (for remote mode)
  /// - [port]: Port for auto-discovery when neither directory nor baseUrl specified
  /// - [timeout]: Timeout for auto-discovery
  ///
  /// Throws [ArgumentError] if both [directory] and [baseUrl] are specified.
  /// Throws [DiscoveryFailedException] if auto-discovery fails.
  static Future<ProcessMonitorClient> connect({
    String instanceId = 'default',
    String? directory,
    String? baseUrl,
    int port = 19881,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final hasDirectory = directory != null;
    final hasBaseUrl = baseUrl != null;

    if (hasDirectory && hasBaseUrl) {
      throw ArgumentError(
        'Cannot specify both directory and baseUrl. '
        'Use directory for local mode or baseUrl for remote mode.',
      );
    }

    if (hasDirectory) {
      return LocalProcessMonitorClient(
        directory: directory,
        instanceId: instanceId,
      );
    }

    if (hasBaseUrl) {
      return RemoteProcessMonitorClient(
        baseUrl: baseUrl,
        instanceId: instanceId,
      );
    }

    // Default: auto-discover
    return RemoteProcessMonitorClient.discover(
      port: port,
      timeout: timeout,
      instanceId: instanceId,
    );
  }

  // ---------------------------------------------------------------------------
  // Process Registration
  // ---------------------------------------------------------------------------

  /// Register a new process with the monitor.
  ///
  /// The process will be tracked but not started until [start] is called
  /// (unless autostart is enabled in the config).
  Future<void> register(ProcessConfig config);

  /// Deregister a process from the monitor.
  ///
  /// If the process is running, it will be stopped first.
  Future<void> deregister(String processId);

  // ---------------------------------------------------------------------------
  // Process Control
  // ---------------------------------------------------------------------------

  /// Enable a previously disabled process.
  ///
  /// Enabled processes can be started and will be managed by the monitor.
  Future<void> enable(String processId);

  /// Disable a process.
  ///
  /// Disabled processes will be stopped and cannot be started until
  /// re-enabled.
  Future<void> disable(String processId);

  /// Set whether a process should auto-start when the monitor starts.
  Future<void> setAutostart(String processId, bool autostart);

  /// Start a registered process.
  ///
  /// Throws if the process is not registered or is disabled.
  Future<void> start(String processId);

  /// Stop a running process.
  ///
  /// Sends SIGTERM and waits for graceful shutdown before force killing.
  Future<void> stop(String processId);

  /// Restart a running process.
  ///
  /// Equivalent to calling [stop] followed by [start].
  Future<void> restart(String processId);

  // ---------------------------------------------------------------------------
  // Process Status
  // ---------------------------------------------------------------------------

  /// Get the status of a specific process.
  ///
  /// Returns detailed status including running state, PID, uptime, etc.
  Future<ProcessStatus> getStatus(String processId);

  /// Get the status of all registered processes.
  ///
  /// Returns a map from process ID to status.
  Future<Map<String, ProcessStatus>> getAllStatus();

  /// Get the status of the ProcessMonitor itself.
  ///
  /// Returns information about the monitor including version, uptime,
  /// registered process count, etc.
  Future<MonitorStatus> getMonitorStatus();

  // ---------------------------------------------------------------------------
  // Remote Access Configuration
  // ---------------------------------------------------------------------------

  /// Enable or disable remote HTTP access.
  Future<void> setRemoteAccess(bool enabled);

  /// Get the current remote access configuration.
  Future<RemoteAccessConfig> getRemoteAccessConfig();

  /// Set remote access permissions.
  ///
  /// Controls which operations remote clients can perform.
  Future<void> setRemoteAccessPermissions({
    bool? allowRegister,
    bool? allowDeregister,
    bool? allowStart,
    bool? allowStop,
    bool? allowDisable,
    bool? allowAutostart,
    bool? allowMonitorRestart,
  });

  /// Set the list of trusted hosts for remote access.
  ///
  /// Only connections from these hosts will be allowed.
  /// Pass an empty list to allow connections from any host.
  Future<void> setTrustedHosts(List<String> hosts);

  /// Get the current list of trusted hosts.
  Future<List<String>> getTrustedHosts();

  // ---------------------------------------------------------------------------
  // Executable Filtering
  // ---------------------------------------------------------------------------

  /// Get the current executable whitelist.
  ///
  /// Only executables matching these patterns can be registered.
  /// Empty list means all executables are allowed (subject to blacklist).
  Future<List<String>> getRemoteExecutableWhitelist();

  /// Set the executable whitelist.
  Future<void> setRemoteExecutableWhitelist(List<String> patterns);

  /// Get the current executable blacklist.
  ///
  /// Executables matching these patterns cannot be registered.
  Future<List<String>> getRemoteExecutableBlacklist();

  /// Set the executable blacklist.
  Future<void> setRemoteExecutableBlacklist(List<String> patterns);

  // ---------------------------------------------------------------------------
  // Standalone / Partner Configuration
  // ---------------------------------------------------------------------------

  /// Enable or disable standalone mode.
  ///
  /// In standalone mode, the monitor does not participate in partner discovery.
  Future<void> setStandaloneMode(bool enabled);

  /// Get current standalone mode setting.
  Future<bool> isStandaloneMode();

  /// Get partner discovery configuration.
  Future<PartnerDiscoveryConfig> getPartnerDiscoveryConfig();

  /// Set partner discovery configuration.
  Future<void> setPartnerDiscoveryConfig(PartnerDiscoveryConfig config);

  // ---------------------------------------------------------------------------
  // Monitor Control
  // ---------------------------------------------------------------------------

  /// Restart the ProcessMonitor itself.
  ///
  /// All managed processes will continue running through the restart.
  Future<void> restartMonitor();

  /// Dispose of any resources held by this client.
  ///
  /// For remote clients, this closes the HTTP client.
  /// For local clients, this is a no-op.
  void dispose();
}
