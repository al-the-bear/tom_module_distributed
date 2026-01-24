/// Configuration for partner instance discovery.
class PartnerDiscoveryConfig {
  /// Partner instance ID (e.g., "watcher" for default instance).
  final String? partnerInstanceId;

  /// Partner aliveness port.
  final int? partnerAlivenessPort;

  /// URL to fetch partner status.
  final String? partnerStatusUrl;

  /// Attempt to discover partner on startup.
  final bool discoveryOnStartup;

  /// Start partner if not found on startup.
  final bool startPartnerIfMissing;

  /// Creates a partner discovery configuration.
  const PartnerDiscoveryConfig({
    this.partnerInstanceId,
    this.partnerAlivenessPort,
    this.partnerStatusUrl,
    this.discoveryOnStartup = true,
    this.startPartnerIfMissing = false,
  });

  /// Default partner discovery config for default instance.
  static PartnerDiscoveryConfig defaultForInstance(String instanceId) {
    if (instanceId == 'default') {
      return const PartnerDiscoveryConfig(
        partnerInstanceId: 'watcher',
        partnerAlivenessPort: 5682,
        partnerStatusUrl: 'http://localhost:5682/status',
      );
    } else {
      return const PartnerDiscoveryConfig(
        partnerInstanceId: 'default',
        partnerAlivenessPort: 5681,
        partnerStatusUrl: 'http://localhost:5681/status',
      );
    }
  }

  /// Creates a PartnerDiscoveryConfig from JSON.
  factory PartnerDiscoveryConfig.fromJson(Map<String, dynamic> json) {
    return PartnerDiscoveryConfig(
      partnerInstanceId: json['partnerInstanceId'] as String?,
      partnerAlivenessPort: json['partnerAlivenessPort'] as int?,
      partnerStatusUrl: json['partnerStatusUrl'] as String?,
      discoveryOnStartup: json['discoveryOnStartup'] as bool? ?? true,
      startPartnerIfMissing: json['startPartnerIfMissing'] as bool? ?? false,
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      if (partnerInstanceId != null) 'partnerInstanceId': partnerInstanceId,
      if (partnerAlivenessPort != null)
        'partnerAlivenessPort': partnerAlivenessPort,
      if (partnerStatusUrl != null) 'partnerStatusUrl': partnerStatusUrl,
      'discoveryOnStartup': discoveryOnStartup,
      'startPartnerIfMissing': startPartnerIfMissing,
    };
  }

  /// Creates a copy with modified values.
  PartnerDiscoveryConfig copyWith({
    String? partnerInstanceId,
    int? partnerAlivenessPort,
    String? partnerStatusUrl,
    bool? discoveryOnStartup,
    bool? startPartnerIfMissing,
  }) {
    return PartnerDiscoveryConfig(
      partnerInstanceId: partnerInstanceId ?? this.partnerInstanceId,
      partnerAlivenessPort: partnerAlivenessPort ?? this.partnerAlivenessPort,
      partnerStatusUrl: partnerStatusUrl ?? this.partnerStatusUrl,
      discoveryOnStartup: discoveryOnStartup ?? this.discoveryOnStartup,
      startPartnerIfMissing:
          startPartnerIfMissing ?? this.startPartnerIfMissing,
    );
  }
}
