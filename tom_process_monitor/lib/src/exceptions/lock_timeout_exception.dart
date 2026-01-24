import 'process_monitor_exception.dart';

/// Thrown when lock acquisition times out.
class LockTimeoutException extends ProcessMonitorException {
  /// Creates a LockTimeoutException.
  const LockTimeoutException(super.message);

  @override
  String toString() => 'LockTimeoutException: $message';
}
