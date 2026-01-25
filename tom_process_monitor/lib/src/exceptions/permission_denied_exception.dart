import 'process_monitor_exception.dart';

/// Thrown when a remote operation is not permitted.
class PermissionDeniedException extends ProcessMonitorException {
  /// The operation that was denied.
  final String operation;

  /// Creates a PermissionDeniedException.
  PermissionDeniedException(this.operation)
    : super('Permission denied: $operation');

  @override
  String toString() => 'PermissionDeniedException: $operation';
}
