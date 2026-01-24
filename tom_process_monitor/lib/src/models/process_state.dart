/// Process lifecycle states.
enum ProcessState {
  /// Process is not running and hasn't been started.
  stopped,

  /// Process is in the process of starting.
  starting,

  /// Process is running normally.
  running,

  /// Process is being stopped.
  stopping,

  /// Process has crashed and may be restarted.
  crashed,

  /// Process is waiting for retry after crash.
  retrying,

  /// Process failed after exhausting restart attempts.
  failed,

  /// Process is disabled and cannot be started.
  disabled,
}

/// Extension methods for ProcessState.
extension ProcessStateExtension on ProcessState {
  /// Converts the state to a JSON-compatible string.
  String toJson() => name;

  /// Parses a ProcessState from a JSON string.
  static ProcessState fromJson(String value) {
    return ProcessState.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ProcessState.stopped,
    );
  }
}
