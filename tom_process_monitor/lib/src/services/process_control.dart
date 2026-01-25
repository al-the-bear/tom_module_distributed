import 'dart:io';

import 'package:path/path.dart' as path;

import '../models/process_entry.dart';

/// Service for starting, stopping, and checking processes.
class ProcessControl {
  /// Log directory for process output.
  final String logDirectory;

  /// Logger function.
  final void Function(String message)? logger;

  /// Creates a process control service.
  ProcessControl({required this.logDirectory, this.logger});

  /// Checks if a process is alive.
  Future<bool> isProcessAlive(int pid) async {
    if (Platform.isWindows) {
      return _isProcessAliveWindows(pid);
    }

    try {
      // Signal 0 checks existence without sending actual signal
      return Process.killPid(pid, ProcessSignal.sigcont);
    } catch (e) {
      return false;
    }
  }

  Future<bool> _isProcessAliveWindows(int pid) async {
    final result = await Process.run('tasklist', ['/FI', 'PID eq $pid', '/NH']);
    return result.stdout.toString().contains('$pid');
  }

  /// Starts a process in detached mode.
  Future<int> startProcess(ProcessEntry process) async {
    final logDir = _getProcessLogDir(process.id);
    await Directory(logDir).create(recursive: true);

    _log(
      'Starting process ${process.id}: ${process.command} ${process.args.join(' ')}',
    );

    if (Platform.isWindows) {
      return _startProcessWindows(process, logDir);
    } else {
      return _startProcessUnix(process, logDir);
    }
  }

  Future<int> _startProcessUnix(ProcessEntry process, String logDir) async {
    final stdoutPath = path.join(logDir, 'stdout.log');
    final stderrPath = path.join(logDir, 'stderr.log');

    // Build command with redirections
    final escapedArgs = process.args.map(_escapeUnix).join(' ');
    final cmd = '${_escapeUnix(process.command)} $escapedArgs';
    final fullCmd = 'nohup $cmd > "$stdoutPath" 2> "$stderrPath" & echo \$!';

    final result = await Process.run(
      'sh',
      ['-c', fullCmd],
      workingDirectory: process.workingDirectory,
      environment: process.environment,
    );

    final pidStr = result.stdout.toString().trim();
    final pid = int.tryParse(pidStr);
    if (pid == null) {
      throw ProcessException(
        process.command,
        process.args,
        'Failed to get PID: ${result.stderr}',
        result.exitCode,
      );
    }

    _log('Process ${process.id} started with PID $pid');
    return pid;
  }

  Future<int> _startProcessWindows(ProcessEntry process, String logDir) async {
    final stdoutPath = path.join(logDir, 'stdout.log');
    final stderrPath = path.join(logDir, 'stderr.log');

    // Use cmd /c start /b with redirection
    final escapedArgs = process.args.map(_escapeWindows).join(' ');
    final cmdLine =
        '${_escapeWindows(process.command)} $escapedArgs > "$stdoutPath" 2> "$stderrPath"';

    final result = await Process.run(
      'cmd',
      ['/c', 'start', '/b', cmdLine],
      workingDirectory: process.workingDirectory,
      environment: process.environment,
    );

    // Get PID using wmic (more reliable)
    final wmicResult = await Process.run('wmic', [
      'process',
      'where',
      'name="${path.basename(process.command)}"',
      'get',
      'processid',
      '/format:list',
    ]);

    final pidMatch = RegExp(
      r'ProcessId=(\d+)',
    ).firstMatch(wmicResult.stdout.toString());
    if (pidMatch == null) {
      throw ProcessException(
        process.command,
        process.args,
        'Failed to get PID',
        result.exitCode,
      );
    }

    return int.parse(pidMatch.group(1)!);
  }

  /// Stops a process.
  Future<bool> stopProcess(int pid, {bool force = false}) async {
    _log('Stopping process $pid (force: $force)');

    if (Platform.isWindows) {
      return _killProcessWindows(pid, force: force);
    }

    try {
      final signal = force ? ProcessSignal.sigkill : ProcessSignal.sigterm;
      return Process.killPid(pid, signal);
    } catch (e) {
      return false;
    }
  }

  Future<bool> _killProcessWindows(int pid, {bool force = false}) async {
    final args = force ? ['/F', '/PID', '$pid'] : ['/PID', '$pid'];
    final result = await Process.run('taskkill', args);
    return result.exitCode == 0;
  }

  /// Gracefully stops a process with timeout.
  Future<void> stopProcessGracefully(
    int pid, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    // Try graceful shutdown first
    if (!await stopProcess(pid, force: false)) {
      return; // Process already dead
    }

    // Wait for process to exit
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!await isProcessAlive(pid)) {
        return; // Process exited gracefully
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    // Force kill if still alive
    _log('Process $pid did not exit gracefully, forcing kill');
    await stopProcess(pid, force: true);
  }

  String _getProcessLogDir(String processId) {
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('-', '')
        .substring(0, 15);
    return path.join(logDirectory, processId, timestamp);
  }

  String _escapeUnix(String arg) {
    if (arg.contains(' ') || arg.contains('"') || arg.contains("'")) {
      return "'${arg.replaceAll("'", "'\\''")}'";
    }
    return arg;
  }

  String _escapeWindows(String arg) {
    if (arg.contains(' ') || arg.contains('"')) {
      return '"${arg.replaceAll('"', '\\"')}"';
    }
    return arg;
  }

  void _log(String message) {
    logger?.call(message);
  }
}
