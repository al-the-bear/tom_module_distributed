import 'dart:async';

import '../cli_runner.dart';

/// Command handler for the monitor_watcher CLI.
class MonitorWatcherCommand {
  final CliRunner _runner = CliRunner();

  /// Runs the monitor_watcher command with the given arguments.
  Future<int> run(List<String> args) => _runner.runWatcher(args);
}
