/// Startup health check configuration.
class StartupCheck {
  /// Whether startup health verification is enabled.
  final bool enabled;

  /// Wait before first check (allow process to initialize).
  final int initialDelayMs;

  /// Interval between startup checks.
  final int checkIntervalMs;

  /// Maximum check attempts before declaring failure.
  final int maxAttempts;

  /// Action on failure: "restart", "disable", or "fail".
  final String failAction;

  /// Creates a startup check configuration.
  const StartupCheck({
    this.enabled = true,
    this.initialDelayMs = 2000,
    this.checkIntervalMs = 1000,
    this.maxAttempts = 30,
    this.failAction = 'restart',
  });

  /// Creates a StartupCheck from JSON.
  factory StartupCheck.fromJson(Map<String, dynamic> json) {
    return StartupCheck(
      enabled: json['enabled'] as bool? ?? true,
      initialDelayMs: json['initialDelayMs'] as int? ?? 2000,
      checkIntervalMs: json['checkIntervalMs'] as int? ?? 1000,
      maxAttempts: json['maxAttempts'] as int? ?? 30,
      failAction: json['failAction'] as String? ?? 'restart',
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'initialDelayMs': initialDelayMs,
      'checkIntervalMs': checkIntervalMs,
      'maxAttempts': maxAttempts,
      'failAction': failAction,
    };
  }

  /// Creates a copy with modified values.
  StartupCheck copyWith({
    bool? enabled,
    int? initialDelayMs,
    int? checkIntervalMs,
    int? maxAttempts,
    String? failAction,
  }) {
    return StartupCheck(
      enabled: enabled ?? this.enabled,
      initialDelayMs: initialDelayMs ?? this.initialDelayMs,
      checkIntervalMs: checkIntervalMs ?? this.checkIntervalMs,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      failAction: failAction ?? this.failAction,
    );
  }
}
