import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:tom_process_monitor/tom_process_monitor.dart';

/// CLI Runner for ProcessMonitor commands.
///
/// Handles argument parsing and execution of ProcessMonitor CLI commands.
class CliRunner {
  /// Creates a CLI runner.
  CliRunner();

  /// Parses command-line arguments for the process_monitor command.
  ArgParser createProcessMonitorParser() {
    final parser = ArgParser()
      ..addFlag(
        'help',
        abbr: 'h',
        negatable: false,
        help: 'Show this help message.',
      )
      ..addFlag(
        'version',
        negatable: false,
        help: 'Show version information.',
      )
      ..addOption(
        'directory',
        abbr: 'd',
        help: 'Base directory for ProcessMonitor files. '
            'Defaults to ~/.tom/process_monitor/',
      )
      ..addFlag(
        'foreground',
        abbr: 'f',
        negatable: false,
        help: 'Run in foreground (do not detach).',
      )
      ..addFlag(
        'stop',
        negatable: false,
        help: 'Stop the running ProcessMonitor instance.',
      )
      ..addFlag(
        'status',
        negatable: false,
        help: 'Show status of the ProcessMonitor instance.',
      )
      ..addFlag(
        'restart',
        negatable: false,
        help: 'Restart the ProcessMonitor instance.',
      )
      ..addOption(
        'instance',
        help: 'Instance ID of the ProcessMonitor.',
        hide: true,
      );

    return parser;
  }

  /// Parses command-line arguments for the monitor_watcher command.
  ArgParser createWatcherParser() {
    final parser = ArgParser()
      ..addFlag(
        'help',
        abbr: 'h',
        negatable: false,
        help: 'Show this help message.',
      )
      ..addFlag(
        'version',
        negatable: false,
        help: 'Show version information.',
      )
      ..addOption(
        'directory',
        abbr: 'd',
        help: 'Base directory for MonitorWatcher files. '
            'Defaults to ~/.tom/process_monitor/',
      )
      ..addFlag(
        'foreground',
        abbr: 'f',
        negatable: false,
        help: 'Run in foreground (do not detach).',
      )
      ..addFlag(
        'stop',
        negatable: false,
        help: 'Stop the running MonitorWatcher instance.',
      )
      ..addFlag(
        'status',
        negatable: false,
        help: 'Show status of the MonitorWatcher instance.',
      )
      ..addFlag(
        'restart',
        negatable: false,
        help: 'Restart the MonitorWatcher instance.',
      )
      ..addOption(
        'instance',
        help: 'Instance ID of the MonitorWatcher.',
        hide: true,
      );

    return parser;
  }

  /// Runs the process_monitor CLI command.
  Future<int> runProcessMonitor(List<String> args) async {
    final parser = createProcessMonitorParser();
    final ArgResults results;

    try {
      results = parser.parse(args);
    } on FormatException catch (e) {
      stderr.writeln('Error: ${e.message}');
      stderr.writeln();
      _printUsage('process_monitor', parser);
      return 1;
    }

    if (results['help'] as bool) {
      _printUsage('process_monitor', parser);
      return 0;
    }

    if (results['version'] as bool) {
      stdout.writeln('process_monitor version 1.0.0');
      return 0;
    }

    final directory = results['directory'] as String?;
    final foreground = results['foreground'] as bool;
    final stop = results['stop'] as bool;
    final status = results['status'] as bool;
    final restart = results['restart'] as bool;
    final instanceId = results['instance'] as String? ?? 'default';

    // Use remote client to interact with running instance
    final remoteClient = RemoteProcessMonitorClient(
      baseUrl: 'http://localhost:19881',
    );

    if (stop) {
      return _stopMonitor(remoteClient, 'ProcessMonitor');
    }

    if (status) {
      return _showStatus(remoteClient, 'ProcessMonitor');
    }

    if (restart) {
      return _restartMonitor(remoteClient, 'ProcessMonitor');
    }

    // Start the ProcessMonitor
    return _startMonitor(
      instanceId: instanceId,
      directory: directory,
      foreground: foreground,
    );
  }

  /// Runs the monitor_watcher CLI command.
  Future<int> runWatcher(List<String> args) async {
    final parser = createWatcherParser();
    final ArgResults results;

    try {
      results = parser.parse(args);
    } on FormatException catch (e) {
      stderr.writeln('Error: ${e.message}');
      stderr.writeln();
      _printUsage('monitor_watcher', parser);
      return 1;
    }

    if (results['help'] as bool) {
      _printUsage('monitor_watcher', parser);
      return 0;
    }

    if (results['version'] as bool) {
      stdout.writeln('monitor_watcher version 1.0.0');
      return 0;
    }

    final directory = results['directory'] as String?;
    final foreground = results['foreground'] as bool;
    final stop = results['stop'] as bool;
    final status = results['status'] as bool;
    final restart = results['restart'] as bool;
    final instanceId = results['instance'] as String? ?? 'watcher';

    // Use remote client to interact with running instance
    final remoteClient = RemoteProcessMonitorClient(
      baseUrl: 'http://localhost:19882',
    );

    if (stop) {
      return _stopMonitor(remoteClient, 'MonitorWatcher');
    }

    if (status) {
      return _showStatus(remoteClient, 'MonitorWatcher');
    }

    if (restart) {
      return _restartMonitor(remoteClient, 'MonitorWatcher');
    }

    // Start the MonitorWatcher
    return _startMonitor(
      instanceId: instanceId,
      directory: directory,
      foreground: foreground,
    );
  }

  Future<int> _stopMonitor(
    RemoteProcessMonitorClient client,
    String name,
  ) async {
    try {
      await client.restartMonitor();
      stdout.writeln('$name stop signal sent.');
      client.dispose();
      return 0;
    } catch (e) {
      stderr.writeln('$name is not running or unreachable.');
      client.dispose();
      return 1;
    }
  }

  Future<int> _showStatus(
    RemoteProcessMonitorClient client,
    String name,
  ) async {
    try {
      final status = await client.getMonitorStatus();
      stdout.writeln('$name Status:');
      stdout.writeln('  Instance: ${status.instanceId}');
      stdout.writeln('  State: ${status.state}');
      stdout.writeln('  PID: ${status.pid}');
      stdout.writeln('  Uptime: ${status.uptime}s');
      stdout.writeln('  Managed Processes: ${status.managedProcessCount}');
      stdout.writeln('  Running Processes: ${status.runningProcessCount}');
      stdout.writeln('  Standalone Mode: ${status.standaloneMode}');
      client.dispose();
      return 0;
    } catch (e) {
      stderr.writeln('$name is not running or unreachable.');
      client.dispose();
      return 1;
    }
  }

  Future<int> _restartMonitor(
    RemoteProcessMonitorClient client,
    String name,
  ) async {
    try {
      await client.restartMonitor();
      stdout.writeln('$name restart initiated.');
      client.dispose();
      return 0;
    } catch (e) {
      stderr.writeln('Error restarting $name: $e');
      client.dispose();
      return 1;
    }
  }

  Future<int> _startMonitor({
    required String instanceId,
    String? directory,
    required bool foreground,
  }) async {
    final name = instanceId == 'watcher' ? 'Watcher' : 'ProcessMonitor';

    final monitor = ProcessMonitor(
      instanceId: instanceId,
      directory: directory,
    );

    if (foreground) {
      stdout.writeln('Starting $name in foreground...');
      stdout.writeln('Press Ctrl+C to stop.');

      // Handle shutdown signals
      final completer = Completer<void>();

      ProcessSignal.sigint.watch().listen((_) async {
        stdout.writeln('\nShutting down $name...');
        await monitor.stop();
        completer.complete();
      });

      ProcessSignal.sigterm.watch().listen((_) async {
        await monitor.stop();
        completer.complete();
      });

      await monitor.start();
      await completer.future;

      return 0;
    } else {
      // Detached mode - spawn as detached process
      stdout.writeln('Starting $name in background...');

      final executable = Platform.resolvedExecutable;
      final script = Platform.script.toFilePath();

      final processArgs = <String>[
        script,
        '--foreground',
        '--instance=$instanceId',
        if (directory != null) '--directory=$directory',
      ];

      final process = await Process.start(
        executable,
        processArgs,
        mode: ProcessStartMode.detached,
      );

      stdout.writeln('$name started with PID: ${process.pid}');

      return 0;
    }
  }

  void _printUsage(String command, ArgParser parser) {
    stdout.writeln('Usage: $command [options]');
    stdout.writeln();
    stdout.writeln('Options:');
    stdout.writeln(parser.usage);
  }
}
