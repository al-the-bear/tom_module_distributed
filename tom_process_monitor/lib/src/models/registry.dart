import 'partner_discovery_config.dart';
import 'process_entry.dart';
import 'remote_access_config.dart';

/// Aliveness server configuration.
class AlivenessServerConfig {
  /// Whether aliveness server is enabled.
  final bool enabled;

  /// Aliveness server port.
  final int port;

  /// Creates an aliveness server configuration.
  const AlivenessServerConfig({this.enabled = true, this.port = 19883});

  /// Creates an AlivenessServerConfig from JSON.
  factory AlivenessServerConfig.fromJson(Map<String, dynamic> json) {
    return AlivenessServerConfig(
      enabled: json['enabled'] as bool? ?? true,
      port: json['port'] as int? ?? 19883,
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {'enabled': enabled, 'port': port};
  }
}

/// Information about the watcher process.
class WatcherInfo {
  /// PID of the watcher process.
  final int watcherPid;

  /// Instance ID of the watcher.
  final String watcherInstanceId;

  /// Aliveness port of the watcher.
  final int watcherAlivenessPort;

  /// Creates watcher info.
  const WatcherInfo({
    required this.watcherPid,
    required this.watcherInstanceId,
    required this.watcherAlivenessPort,
  });

  /// Creates a WatcherInfo from JSON.
  factory WatcherInfo.fromJson(Map<String, dynamic> json) {
    return WatcherInfo(
      watcherPid: json['watcherPid'] as int,
      watcherInstanceId: json['watcherInstanceId'] as String,
      watcherAlivenessPort: json['watcherAlivenessPort'] as int,
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      'watcherPid': watcherPid,
      'watcherInstanceId': watcherInstanceId,
      'watcherAlivenessPort': watcherAlivenessPort,
    };
  }
}

/// Complete process registry.
class ProcessRegistry {
  /// Schema version.
  int version;

  /// Last modification timestamp.
  DateTime lastModified;

  /// ProcessMonitor instance ID.
  String instanceId;

  /// Monitoring loop interval in milliseconds.
  int monitorIntervalMs;

  /// Disable partner (watcher) discovery and monitoring.
  bool standaloneMode;

  /// Partner instance discovery configuration.
  PartnerDiscoveryConfig partnerDiscovery;

  /// Remote HTTP API configuration.
  RemoteAccessConfig remoteAccess;

  /// Aliveness HTTP server configuration.
  AlivenessServerConfig alivenessServer;

  /// Information about the watcher process.
  WatcherInfo? watcherInfo;

  /// Registered processes.
  Map<String, ProcessEntry> processes;

  /// Creates a process registry.
  ProcessRegistry({
    this.version = 1,
    DateTime? lastModified,
    required this.instanceId,
    this.monitorIntervalMs = 5000,
    this.standaloneMode = false,
    PartnerDiscoveryConfig? partnerDiscovery,
    RemoteAccessConfig? remoteAccess,
    AlivenessServerConfig? alivenessServer,
    this.watcherInfo,
    Map<String, ProcessEntry>? processes,
  }) : lastModified = lastModified ?? DateTime.now(),
       partnerDiscovery =
           partnerDiscovery ??
           PartnerDiscoveryConfig.defaultForInstance(instanceId),
       remoteAccess = remoteAccess ?? RemoteAccessConfig.defaultConfig,
       alivenessServer =
           alivenessServer ??
           AlivenessServerConfig(port: instanceId == 'watcher' ? 19884 : 19883),
       processes = processes ?? {};

  /// Creates a ProcessRegistry from JSON.
  factory ProcessRegistry.fromJson(Map<String, dynamic> json) {
    final instanceId = json['instanceId'] as String? ?? 'default';
    return ProcessRegistry(
      version: json['version'] as int? ?? 1,
      lastModified: json['lastModified'] != null
          ? DateTime.parse(json['lastModified'] as String)
          : DateTime.now(),
      instanceId: instanceId,
      monitorIntervalMs: json['monitorIntervalMs'] as int? ?? 5000,
      standaloneMode: json['standaloneMode'] as bool? ?? false,
      partnerDiscovery: json['partnerDiscovery'] != null
          ? PartnerDiscoveryConfig.fromJson(
              json['partnerDiscovery'] as Map<String, dynamic>,
            )
          : PartnerDiscoveryConfig.defaultForInstance(instanceId),
      remoteAccess: json['remoteAccess'] != null
          ? RemoteAccessConfig.fromJson(
              json['remoteAccess'] as Map<String, dynamic>,
            )
          : RemoteAccessConfig.defaultConfig,
      alivenessServer: json['alivenessServer'] != null
          ? AlivenessServerConfig.fromJson(
              json['alivenessServer'] as Map<String, dynamic>,
            )
          : AlivenessServerConfig(port: instanceId == 'watcher' ? 19884 : 19883),
      watcherInfo: json['watcherInfo'] != null
          ? WatcherInfo.fromJson(json['watcherInfo'] as Map<String, dynamic>)
          : null,
      processes:
          (json['processes'] as Map<String, dynamic>?)?.map(
            (k, v) =>
                MapEntry(k, ProcessEntry.fromJson(v as Map<String, dynamic>)),
          ) ??
          {},
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'lastModified': lastModified.toIso8601String(),
      'instanceId': instanceId,
      'monitorIntervalMs': monitorIntervalMs,
      'standaloneMode': standaloneMode,
      'partnerDiscovery': partnerDiscovery.toJson(),
      'remoteAccess': remoteAccess.toJson(),
      'alivenessServer': alivenessServer.toJson(),
      if (watcherInfo != null) 'watcherInfo': watcherInfo!.toJson(),
      'processes': processes.map((k, v) => MapEntry(k, v.toJson())),
    };
  }
}
