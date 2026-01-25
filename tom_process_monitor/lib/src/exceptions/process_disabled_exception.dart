import 'process_monitor_exception.dart';

/// Thrown when trying to start a disabled process.
class ProcessDisabledException extends ProcessMonitorException {
  /// The process ID that is disabled.
  final String processId;

  /// Creates a ProcessDisabledException.
  ProcessDisabledException(this.processId)
    : super('Process is disabled: $processId');

  @override
  String toString() =>
      'ProcessDisabledException: Process $processId is disabled';
}
