import 'dart:async';

import '../cli_runner.dart';

/// Command handler for the process_monitor CLI.
class ProcessMonitorCommand {
  final CliRunner _runner = CliRunner();

  /// Runs the process_monitor command with the given arguments.
  Future<int> run(List<String> args) => _runner.runProcessMonitor(args);
}
