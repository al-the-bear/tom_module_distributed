import 'dart:io';

import 'package:tom_process_monitor_tool/tom_process_monitor_tool.dart';

/// Main entry point for the process_monitor CLI.
///
/// This is the default ProcessMonitor instance that manages processes
/// and is monitored by the watcher instance.
///
/// Default ports:
/// - Aliveness: 5681
/// - Remote API: 5679
void main(List<String> args) async {
  final command = ProcessMonitorCommand();
  final exitCode = await command.run(args);
  exit(exitCode);
}
