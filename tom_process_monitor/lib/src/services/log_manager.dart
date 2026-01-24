import 'dart:io';

import 'package:path/path.dart' as path;

/// Service for managing ProcessMonitor log files.
class LogManager {
  /// Base log directory.
  final String baseDirectory;

  /// Instance ID for log naming.
  final String instanceId;

  /// Maximum number of log files to keep.
  final int maxLogFiles;

  /// Current log file.
  IOSink? _logSink;

  /// Current log file path.
  String? _currentLogPath;

  /// Creates a log manager.
  LogManager({
    required this.baseDirectory,
    required this.instanceId,
    this.maxLogFiles = 10,
  });

  /// Initializes logging, creating a new log file.
  Future<void> initialize() async {
    final logDir = path.join(baseDirectory, '${instanceId}_logs');
    await Directory(logDir).create(recursive: true);

    // Clean up old log files
    await _cleanupOldLogs(logDir);

    // Create new log file
    final timestamp = _formatTimestamp(DateTime.now());
    _currentLogPath = path.join(logDir, '${timestamp}_$instanceId.log');
    final logFile = File(_currentLogPath!);
    _logSink = logFile.openWrite(mode: FileMode.writeOnly);

    log('Log file created: $_currentLogPath');
  }

  /// Logs a message.
  void log(String message, {String level = 'INFO'}) {
    final timestamp = DateTime.now().toIso8601String();
    final logLine = '[$timestamp] [$level] $message\n';
    _logSink?.write(logLine);
  }

  /// Logs an info message.
  void info(String message) => log(message, level: 'INFO');

  /// Logs a warning message.
  void warn(String message) => log(message, level: 'WARN');

  /// Logs an error message.
  void error(String message) => log(message, level: 'ERROR');

  /// Closes the log file.
  Future<void> close() async {
    await _logSink?.flush();
    await _logSink?.close();
    _logSink = null;
  }

  /// Gets the path for process logs.
  String getProcessLogDir(String processId) {
    final timestamp = _formatTimestamp(DateTime.now());
    return path.join(baseDirectory, '${instanceId}_logs', processId, timestamp);
  }

  /// Cleans up old process logs.
  Future<void> cleanupProcessLogs(String processId) async {
    final processLogDir = path.join(
      baseDirectory,
      '${instanceId}_logs',
      processId,
    );
    final dir = Directory(processLogDir);
    if (!await dir.exists()) return;

    final entries = await dir.list().toList();
    if (entries.length <= maxLogFiles) return;

    // Sort by name (which includes timestamp)
    entries.sort((a, b) => a.path.compareTo(b.path));

    // Delete oldest entries
    final toDelete = entries.length - maxLogFiles;
    for (var i = 0; i < toDelete; i++) {
      final entry = entries[i];
      if (entry is Directory) {
        await entry.delete(recursive: true);
      }
    }
  }

  Future<void> _cleanupOldLogs(String logDir) async {
    final dir = Directory(logDir);
    if (!await dir.exists()) return;

    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.log'))
        .toList();

    if (files.length < maxLogFiles) return;

    // Sort by name (which includes timestamp)
    files.sort((a, b) => a.path.compareTo(b.path));

    // Delete oldest files
    final toDelete = files.length - maxLogFiles + 1; // +1 for new file
    for (var i = 0; i < toDelete; i++) {
      await files[i].delete();
    }
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.year}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}_'
        '${dt.hour.toString().padLeft(2, '0')}'
        '${dt.minute.toString().padLeft(2, '0')}'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}
