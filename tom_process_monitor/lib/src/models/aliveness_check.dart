import 'startup_check.dart';

/// HTTP aliveness check configuration.
class AlivenessCheck {
  /// Whether aliveness check is enabled.
  final bool enabled;

  /// URL to check (e.g., http://localhost:8080/health).
  final String url;

  /// URL to fetch process status/PID.
  final String? statusUrl;

  /// Check interval in milliseconds.
  final int intervalMs;

  /// Request timeout in milliseconds.
  final int timeoutMs;

  /// Number of consecutive failures before declaring dead.
  final int consecutiveFailuresRequired;

  /// Optional startup health verification.
  final StartupCheck? startupCheck;

  /// Creates an aliveness check configuration.
  const AlivenessCheck({
    required this.enabled,
    required this.url,
    this.statusUrl,
    this.intervalMs = 3000,
    this.timeoutMs = 2000,
    this.consecutiveFailuresRequired = 2,
    this.startupCheck,
  });

  /// Creates an AlivenessCheck from JSON.
  factory AlivenessCheck.fromJson(Map<String, dynamic> json) {
    return AlivenessCheck(
      enabled: json['enabled'] as bool? ?? false,
      url: json['url'] as String? ?? '',
      statusUrl: json['statusUrl'] as String?,
      intervalMs: json['intervalMs'] as int? ?? 3000,
      timeoutMs: json['timeoutMs'] as int? ?? 2000,
      consecutiveFailuresRequired:
          json['consecutiveFailuresRequired'] as int? ?? 2,
      startupCheck: json['startupCheck'] != null
          ? StartupCheck.fromJson(json['startupCheck'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'url': url,
      if (statusUrl != null) 'statusUrl': statusUrl,
      'intervalMs': intervalMs,
      'timeoutMs': timeoutMs,
      'consecutiveFailuresRequired': consecutiveFailuresRequired,
      if (startupCheck != null) 'startupCheck': startupCheck!.toJson(),
    };
  }

  /// Creates a copy with modified values.
  AlivenessCheck copyWith({
    bool? enabled,
    String? url,
    String? statusUrl,
    int? intervalMs,
    int? timeoutMs,
    int? consecutiveFailuresRequired,
    StartupCheck? startupCheck,
  }) {
    return AlivenessCheck(
      enabled: enabled ?? this.enabled,
      url: url ?? this.url,
      statusUrl: statusUrl ?? this.statusUrl,
      intervalMs: intervalMs ?? this.intervalMs,
      timeoutMs: timeoutMs ?? this.timeoutMs,
      consecutiveFailuresRequired:
          consecutiveFailuresRequired ?? this.consecutiveFailuresRequired,
      startupCheck: startupCheck ?? this.startupCheck,
    );
  }
}
