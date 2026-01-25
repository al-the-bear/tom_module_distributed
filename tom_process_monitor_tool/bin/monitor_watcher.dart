import 'dart:io';

import 'package:tom_process_monitor_tool/tom_process_monitor_tool.dart';

/// Main entry point for the monitor_watcher CLI.
///
/// This is the watcher ProcessMonitor instance that monitors the default
/// instance and can restart it if it becomes unresponsive.
///
/// Default ports:
/// - Aliveness: 19884
/// - Remote API: 19882
void main(List<String> args) async {
  final command = MonitorWatcherCommand();
  final exitCode = await command.run(args);
  exit(exitCode);
}
