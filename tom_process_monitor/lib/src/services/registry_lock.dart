import 'dart:convert';
import 'dart:io';

import '../exceptions/lock_timeout_exception.dart';

/// Lock file content.
class LockInfo {
  /// Instance that holds the lock.
  final String lockedBy;

  /// When the lock was acquired.
  final DateTime lockedAt;

  /// PID of the lock holder.
  final int pid;

  /// Operation type.
  final String operation;

  /// Creates lock info.
  const LockInfo({
    required this.lockedBy,
    required this.lockedAt,
    required this.pid,
    required this.operation,
  });

  /// Creates LockInfo from JSON.
  factory LockInfo.fromJson(Map<String, dynamic> json) {
    return LockInfo(
      lockedBy: json['lockedBy'] as String,
      lockedAt: DateTime.parse(json['lockedAt'] as String),
      pid: json['pid'] as int,
      operation: json['operation'] as String,
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      'lockedBy': lockedBy,
      'lockedAt': lockedAt.toIso8601String(),
      'pid': pid,
      'operation': operation,
    };
  }
}

/// Registry lock for safe concurrent access.
class RegistryLock {
  /// Path to the lock file.
  final String lockPath;

  /// Instance identifier.
  final String instanceId;

  /// Lock timeout.
  final Duration timeout;

  /// Creates a registry lock.
  RegistryLock({
    required this.lockPath,
    required this.instanceId,
    this.timeout = const Duration(milliseconds: 5000),
  });

  /// Executes an operation while holding the lock.
  Future<T> withLock<T>(Future<T> Function() operation) async {
    await _acquireLock();
    try {
      return await operation();
    } finally {
      await _releaseLock();
    }
  }

  Future<void> _acquireLock() async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      try {
        final lockFile = File(lockPath);

        // Check for stale lock
        if (await lockFile.exists()) {
          final content = await lockFile.readAsString();
          final lockInfo = LockInfo.fromJson(
            jsonDecode(content) as Map<String, dynamic>,
          );

          if (!await _isProcessAlive(lockInfo.pid)) {
            // Stale lock, remove it
            await lockFile.delete();
          } else {
            // Lock held by another process
            await Future<void>.delayed(const Duration(milliseconds: 50));
            continue;
          }
        }

        // Create lock file
        await lockFile.parent.create(recursive: true);
        final lockInfo = LockInfo(
          lockedBy: instanceId,
          lockedAt: DateTime.now(),
          pid: pid,
          operation: 'write',
        );
        await lockFile.writeAsString(jsonEncode(lockInfo.toJson()));

        // Verify we got the lock (handle race condition)
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (await lockFile.exists()) {
          final verifyContent = await lockFile.readAsString();
          final verifyInfo = LockInfo.fromJson(
            jsonDecode(verifyContent) as Map<String, dynamic>,
          );
          if (verifyInfo.lockedBy == instanceId && verifyInfo.pid == pid) {
            return; // Lock acquired successfully
          }
        }

        // Lost the race, retry
        await Future<void>.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    throw LockTimeoutException('Failed to acquire lock within $timeout');
  }

  Future<void> _releaseLock() async {
    try {
      final lockFile = File(lockPath);
      if (await lockFile.exists()) {
        await lockFile.delete();
      }
    } catch (e) {
      // Ignore errors during release
    }
  }

  Future<bool> _isProcessAlive(int targetPid) async {
    if (Platform.isWindows) {
      final result = await Process.run('tasklist', [
        '/FI',
        'PID eq $targetPid',
        '/NH',
      ]);
      return result.stdout.toString().contains('$targetPid');
    } else {
      try {
        // Signal 0 checks if process exists
        return Process.killPid(targetPid, ProcessSignal.sigcont);
      } catch (e) {
        return false;
      }
    }
  }
}
