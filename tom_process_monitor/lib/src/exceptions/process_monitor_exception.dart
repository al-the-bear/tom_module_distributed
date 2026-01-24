/// Base exception for ProcessMonitor errors.
class ProcessMonitorException implements Exception {
  /// Error message.
  final String message;

  /// Creates a ProcessMonitorException.
  const ProcessMonitorException(this.message);

  @override
  String toString() => 'ProcessMonitorException: $message';
}
