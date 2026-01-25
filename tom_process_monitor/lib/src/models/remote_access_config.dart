/// Remote HTTP API configuration.
class RemoteAccessConfig {
  /// Enable HTTP remote API.
  final bool startRemoteAccess;

  /// HTTP server port for remote API.
  final int remotePort;

  /// Hosts that bypass all permission checks.
  final List<String> trustedHosts;

  /// Allow remote process registration.
  final bool allowRemoteRegister;

  /// Allow remote process deregistration.
  final bool allowRemoteDeregister;

  /// Allow remote process start.
  final bool allowRemoteStart;

  /// Allow remote process stop.
  final bool allowRemoteStop;

  /// Allow remote enable/disable.
  final bool allowRemoteDisable;

  /// Allow remote autostart changes.
  final bool allowRemoteAutostart;

  /// Allow remote ProcessMonitor restart.
  final bool allowRemoteMonitorRestart;

  /// Glob patterns for allowed executables.
  final List<String> executableWhitelist;

  /// Glob patterns for blocked executables.
  final List<String> executableBlacklist;

  /// Creates a remote access configuration.
  const RemoteAccessConfig({
    this.startRemoteAccess = false,
    this.remotePort = 19881,
    this.trustedHosts = const ['localhost', '127.0.0.1', '::1'],
    this.allowRemoteRegister = true,
    this.allowRemoteDeregister = true,
    this.allowRemoteStart = true,
    this.allowRemoteStop = true,
    this.allowRemoteDisable = true,
    this.allowRemoteAutostart = true,
    this.allowRemoteMonitorRestart = false,
    this.executableWhitelist = const [],
    this.executableBlacklist = const [],
  });

  /// Default remote access configuration.
  static const RemoteAccessConfig defaultConfig = RemoteAccessConfig();

  /// Creates a RemoteAccessConfig from JSON.
  factory RemoteAccessConfig.fromJson(Map<String, dynamic> json) {
    return RemoteAccessConfig(
      startRemoteAccess: json['startRemoteAccess'] as bool? ?? false,
      remotePort: json['remotePort'] as int? ?? 19881,
      trustedHosts:
          (json['trustedHosts'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const ['localhost', '127.0.0.1', '::1'],
      allowRemoteRegister: json['allowRemoteRegister'] as bool? ?? true,
      allowRemoteDeregister: json['allowRemoteDeregister'] as bool? ?? true,
      allowRemoteStart: json['allowRemoteStart'] as bool? ?? true,
      allowRemoteStop: json['allowRemoteStop'] as bool? ?? true,
      allowRemoteDisable: json['allowRemoteDisable'] as bool? ?? true,
      allowRemoteAutostart: json['allowRemoteAutostart'] as bool? ?? true,
      allowRemoteMonitorRestart:
          json['allowRemoteMonitorRestart'] as bool? ?? false,
      executableWhitelist:
          (json['executableWhitelist'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      executableBlacklist:
          (json['executableBlacklist'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      'startRemoteAccess': startRemoteAccess,
      'remotePort': remotePort,
      'trustedHosts': trustedHosts,
      'allowRemoteRegister': allowRemoteRegister,
      'allowRemoteDeregister': allowRemoteDeregister,
      'allowRemoteStart': allowRemoteStart,
      'allowRemoteStop': allowRemoteStop,
      'allowRemoteDisable': allowRemoteDisable,
      'allowRemoteAutostart': allowRemoteAutostart,
      'allowRemoteMonitorRestart': allowRemoteMonitorRestart,
      'executableWhitelist': executableWhitelist,
      'executableBlacklist': executableBlacklist,
    };
  }

  /// Creates a copy with modified values.
  RemoteAccessConfig copyWith({
    bool? startRemoteAccess,
    int? remotePort,
    List<String>? trustedHosts,
    bool? allowRemoteRegister,
    bool? allowRemoteDeregister,
    bool? allowRemoteStart,
    bool? allowRemoteStop,
    bool? allowRemoteDisable,
    bool? allowRemoteAutostart,
    bool? allowRemoteMonitorRestart,
    List<String>? executableWhitelist,
    List<String>? executableBlacklist,
  }) {
    return RemoteAccessConfig(
      startRemoteAccess: startRemoteAccess ?? this.startRemoteAccess,
      remotePort: remotePort ?? this.remotePort,
      trustedHosts: trustedHosts ?? this.trustedHosts,
      allowRemoteRegister: allowRemoteRegister ?? this.allowRemoteRegister,
      allowRemoteDeregister:
          allowRemoteDeregister ?? this.allowRemoteDeregister,
      allowRemoteStart: allowRemoteStart ?? this.allowRemoteStart,
      allowRemoteStop: allowRemoteStop ?? this.allowRemoteStop,
      allowRemoteDisable: allowRemoteDisable ?? this.allowRemoteDisable,
      allowRemoteAutostart: allowRemoteAutostart ?? this.allowRemoteAutostart,
      allowRemoteMonitorRestart:
          allowRemoteMonitorRestart ?? this.allowRemoteMonitorRestart,
      executableWhitelist: executableWhitelist ?? this.executableWhitelist,
      executableBlacklist: executableBlacklist ?? this.executableBlacklist,
    );
  }
}
