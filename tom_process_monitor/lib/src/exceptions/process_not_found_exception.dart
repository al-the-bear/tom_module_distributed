import 'process_monitor_exception.dart';

/// Thrown when a process is not found in the registry.
class ProcessNotFoundException extends ProcessMonitorException {
  /// The process ID that was not found.
  final String processId;

  /// Creates a ProcessNotFoundException.
  ProcessNotFoundException(this.processId)
      : super('Process not found: $processId');

  @override
  String toString() => 'ProcessNotFoundException: Process $processId not found';
}
