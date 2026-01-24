/// Restart policy configuration.
class RestartPolicy {
  /// Maximum restart attempts before marking as failed.
  final int maxAttempts;

  /// Backoff delays between restart attempts (in milliseconds).
  final List<int> backoffIntervalsMs;

  /// Reset attempt counter after this duration of stable running.
  final int resetAfterMs;

  /// Continue retrying after maxAttempts at a longer interval.
  final bool retryIndefinitely;

  /// Retry interval in indefinite mode (default: 6 hours).
  final int indefiniteIntervalMs;

  /// Creates a restart policy.
  const RestartPolicy({
    this.maxAttempts = 5,
    this.backoffIntervalsMs = const [1000, 2000, 5000],
    this.resetAfterMs = 300000,
    this.retryIndefinitely = false,
    this.indefiniteIntervalMs = 21600000,
  });

  /// Default restart policy.
  static const RestartPolicy defaultPolicy = RestartPolicy();

  /// Creates a RestartPolicy from JSON.
  factory RestartPolicy.fromJson(Map<String, dynamic> json) {
    return RestartPolicy(
      maxAttempts: json['maxAttempts'] as int? ?? 5,
      backoffIntervalsMs:
          (json['backoffIntervalsMs'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          const [1000, 2000, 5000],
      resetAfterMs: json['resetAfterMs'] as int? ?? 300000,
      retryIndefinitely: json['retryIndefinitely'] as bool? ?? false,
      indefiniteIntervalMs: json['indefiniteIntervalMs'] as int? ?? 21600000,
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      'maxAttempts': maxAttempts,
      'backoffIntervalsMs': backoffIntervalsMs,
      'resetAfterMs': resetAfterMs,
      'retryIndefinitely': retryIndefinitely,
      'indefiniteIntervalMs': indefiniteIntervalMs,
    };
  }

  /// Creates a copy with modified values.
  RestartPolicy copyWith({
    int? maxAttempts,
    List<int>? backoffIntervalsMs,
    int? resetAfterMs,
    bool? retryIndefinitely,
    int? indefiniteIntervalMs,
  }) {
    return RestartPolicy(
      maxAttempts: maxAttempts ?? this.maxAttempts,
      backoffIntervalsMs: backoffIntervalsMs ?? this.backoffIntervalsMs,
      resetAfterMs: resetAfterMs ?? this.resetAfterMs,
      retryIndefinitely: retryIndefinitely ?? this.retryIndefinitely,
      indefiniteIntervalMs: indefiniteIntervalMs ?? this.indefiniteIntervalMs,
    );
  }
}
