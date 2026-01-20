import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A stack frame in the operation.
class StackFrame {
  final String participantId;
  final String callId;
  final int pid;
  final DateTime startTime;

  StackFrame({
    required this.participantId,
    required this.callId,
    required this.pid,
    required this.startTime,
  });

  Map<String, dynamic> toJson() => {
        'participantId': participantId,
        'callId': callId,
        'pid': pid,
        'startTime': startTime.toIso8601String(),
      };

  factory StackFrame.fromJson(Map<String, dynamic> json) => StackFrame(
        participantId: json['participantId'] as String,
        callId: json['callId'] as String,
        pid: json['pid'] as int,
        startTime: DateTime.parse(json['startTime'] as String),
      );

  @override
  String toString() =>
      'Frame(participant: $participantId, call: $callId, pid: $pid)';
}

/// A temporary resource registered in the ledger.
class TempResource {
  final String path;
  final int owner;
  final DateTime registeredAt;

  TempResource({
    required this.path,
    required this.owner,
    required this.registeredAt,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'owner': owner,
        'registeredAt': registeredAt.toIso8601String(),
      };

  factory TempResource.fromJson(Map<String, dynamic> json) => TempResource(
        path: json['path'] as String,
        owner: json['owner'] as int,
        registeredAt: DateTime.parse(json['registeredAt'] as String),
      );

  @override
  String toString() => 'TempResource(path: $path, owner: $owner)';
}

/// Operation ledger data structure.
class LedgerData {
  final String operationId;
  String status;
  bool aborted;
  DateTime lastHeartbeat;
  final List<StackFrame> stack;
  final List<TempResource> tempResources;

  LedgerData({
    required this.operationId,
    this.status = 'running',
    this.aborted = false,
    DateTime? lastHeartbeat,
    List<StackFrame>? stack,
    List<TempResource>? tempResources,
  })  : lastHeartbeat = lastHeartbeat ?? DateTime.now(),
        stack = stack ?? [],
        tempResources = tempResources ?? [];

  Map<String, dynamic> toJson() => {
        'operationId': operationId,
        'status': status,
        'aborted': aborted,
        'lastHeartbeat': lastHeartbeat.toIso8601String(),
        'stack': stack.map((f) => f.toJson()).toList(),
        'tempResources': tempResources.map((r) => r.toJson()).toList(),
      };

  factory LedgerData.fromJson(Map<String, dynamic> json) => LedgerData(
        operationId: json['operationId'] as String,
        status: json['status'] as String? ?? 'running',
        aborted: json['aborted'] as bool? ?? false,
        lastHeartbeat: json['lastHeartbeat'] != null
            ? DateTime.parse(json['lastHeartbeat'] as String)
            : null,
        stack: (json['stack'] as List<dynamic>?)
                ?.map((e) => StackFrame.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        tempResources: (json['tempResources'] as List<dynamic>?)
                ?.map((e) => TempResource.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  bool get isEmpty => stack.isEmpty && tempResources.isEmpty;
}

/// Result of heartbeat checks.
class HeartbeatResult {
  /// Whether the abort flag is set.
  final bool abortFlag;

  /// Whether the ledger file exists.
  final bool ledgerExists;

  /// Whether the heartbeat was successfully updated.
  final bool heartbeatUpdated;

  /// Number of stack frames.
  final int stackDepth;

  /// Number of temp resources.
  final int tempResourceCount;

  /// Age of the last heartbeat in milliseconds.
  final int heartbeatAgeMs;

  /// Whether the heartbeat is stale (>10s).
  final bool isStale;

  /// List of stack frame participant IDs.
  final List<String> stackParticipants;

  HeartbeatResult({
    required this.abortFlag,
    required this.ledgerExists,
    required this.heartbeatUpdated,
    required this.stackDepth,
    required this.tempResourceCount,
    required this.heartbeatAgeMs,
    required this.isStale,
    required this.stackParticipants,
  });

  /// Create a result for when ledger doesn't exist.
  factory HeartbeatResult.noLedger() => HeartbeatResult(
        abortFlag: true,
        ledgerExists: false,
        heartbeatUpdated: false,
        stackDepth: 0,
        tempResourceCount: 0,
        heartbeatAgeMs: 0,
        isStale: true,
        stackParticipants: [],
      );
}

/// Helper class that ensures all file operations create backups.
/// 
/// This class wraps file operations to guarantee that:
/// 1. A backup is always created before any modification
/// 2. File locking is properly handled
/// 3. JSON encoding is consistent
class LedgerFileHelper {
  final Directory ledgerDir;
  final OnBackupCreated? onBackupCreated;
  static const _lockTimeout = Duration(seconds: 2);
  static const _lockRetryInterval = Duration(milliseconds: 50);

  LedgerFileHelper({required this.ledgerDir, this.onBackupCreated});

  String _ledgerPath(String operationId) =>
      '${ledgerDir.path}/$operationId.json';

  String _lockPath(String operationId) =>
      '${ledgerDir.path}/$operationId.json.lock';

  String _backupPath(String operationId, String elapsedFormatted) {
    return '${ledgerDir.path}/${operationId}_trail/${elapsedFormatted}_$operationId.json';
  }

  String trailPath(String operationId) {
    return '${ledgerDir.path}/${operationId}_trail';
  }

  /// Acquire a lock on the ledger file.
  Future<bool> acquireLock({required String operationId}) async {
    final lockFile = File(_lockPath(operationId));
    final startTime = DateTime.now();

    while (true) {
      try {
        if (lockFile.existsSync()) {
          final stat = lockFile.statSync();
          final age = DateTime.now().difference(stat.modified);
          if (age > _lockTimeout) {
            lockFile.deleteSync();
          }
        }

        await lockFile.create(exclusive: true);
        await lockFile.writeAsString(
          '{"pid": ${pid}, "timestamp": "${DateTime.now().toIso8601String()}"}',
        );
        return true;
      } catch (e) {
        if (DateTime.now().difference(startTime) > const Duration(seconds: 1)) {
          return false;
        }
        await Future.delayed(_lockRetryInterval);
      }
    }
  }

  /// Release the lock.
  Future<void> releaseLock({required String operationId}) async {
    final lockFile = File(_lockPath(operationId));
    if (lockFile.existsSync()) {
      await lockFile.delete();
    }
  }

  /// Create a backup of the current ledger state.
  Future<String> createBackup({
    required String operationId,
    required String elapsedFormatted,
  }) async {
    final sourceFile = File(_ledgerPath(operationId));
    if (!sourceFile.existsSync()) return '';

    final backupPath = _backupPath(operationId, elapsedFormatted);
    final backupDir = Directory(trailPath(operationId));
    if (!backupDir.existsSync()) {
      await backupDir.create(recursive: true);
    }

    await sourceFile.copy(backupPath);
    onBackupCreated?.call(backupPath);
    return backupPath;
  }

  /// Read ledger data (with locking).
  Future<LedgerData?> read({required String operationId}) async {
    final file = File(_ledgerPath(operationId));
    if (!file.existsSync()) return null;

    final acquired = await acquireLock(operationId: operationId);
    if (!acquired) {
      throw StateError('Failed to acquire lock for operation $operationId');
    }

    try {
      final content = await file.readAsString();
      return LedgerData.fromJson(json.decode(content) as Map<String, dynamic>);
    } finally {
      await releaseLock(operationId: operationId);
    }
  }

  /// Write ledger data (with locking and backup).
  /// ALWAYS creates a backup before writing.
  Future<void> write({
    required String operationId,
    required LedgerData data,
    required String elapsedFormatted,
  }) async {
    final acquired = await acquireLock(operationId: operationId);
    if (!acquired) {
      throw StateError('Failed to acquire lock for operation $operationId');
    }

    try {
      final file = File(_ledgerPath(operationId));
      
      // Create backup before writing (if file exists)
      if (file.existsSync()) {
        await createBackup(
          operationId: operationId,
          elapsedFormatted: elapsedFormatted,
        );
      }

      // Write new data
      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(data.toJson()));
    } finally {
      await releaseLock(operationId: operationId);
    }
  }

  /// Modify ledger with read-modify-write (with locking and backup).
  /// ALWAYS creates a backup before modifying.
  Future<void> modify({
    required String operationId,
    required String elapsedFormatted,
    required LedgerData Function(LedgerData ledger) updater,
  }) async {
    final acquired = await acquireLock(operationId: operationId);
    if (!acquired) {
      throw StateError('Failed to acquire lock for operation $operationId');
    }

    try {
      final file = File(_ledgerPath(operationId));
      if (!file.existsSync()) {
        throw StateError('Ledger file does not exist: $operationId');
      }

      // Create backup before modifying
      await createBackup(
        operationId: operationId,
        elapsedFormatted: elapsedFormatted,
      );

      // Read current state
      final content = await file.readAsString();
      final ledger =
          LedgerData.fromJson(json.decode(content) as Map<String, dynamic>);

      // Apply update
      final updated = updater(ledger);

      // Write back
      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(updated.toJson()));
    } finally {
      await releaseLock(operationId: operationId);
    }
  }

  /// Delete ledger file (with final backup).
  Future<void> delete({
    required String operationId,
    required String elapsedFormatted,
  }) async {
    final acquired = await acquireLock(operationId: operationId);
    if (!acquired) return;

    try {
      // Create final backup before deletion
      await createBackup(
        operationId: operationId,
        elapsedFormatted: elapsedFormatted,
      );

      final file = File(_ledgerPath(operationId));
      if (file.existsSync()) {
        await file.delete();
      }
    } finally {
      await releaseLock(operationId: operationId);
    }
  }

  /// Perform heartbeat update with all checks.
  /// Returns detailed results of all checks performed.
  Future<HeartbeatResult> performHeartbeat({
    required String operationId,
    required int pid,
    required String elapsedFormatted,
  }) async {
    final file = File(_ledgerPath(operationId));
    if (!file.existsSync()) {
      return HeartbeatResult.noLedger();
    }

    final acquired = await acquireLock(operationId: operationId);
    if (!acquired) {
      return HeartbeatResult.noLedger();
    }

    try {
      // Create backup for heartbeat (now we always backup)
      await createBackup(
        operationId: operationId,
        elapsedFormatted: elapsedFormatted,
      );

      // Read current state
      final content = await file.readAsString();
      final ledger =
          LedgerData.fromJson(json.decode(content) as Map<String, dynamic>);

      // Calculate heartbeat age before updating
      final heartbeatAge =
          DateTime.now().difference(ledger.lastHeartbeat).inMilliseconds;
      final isStale = heartbeatAge > 10000;

      // Update heartbeat
      ledger.lastHeartbeat = DateTime.now();

      // Write back
      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(ledger.toJson()));

      return HeartbeatResult(
        abortFlag: ledger.aborted,
        ledgerExists: true,
        heartbeatUpdated: true,
        stackDepth: ledger.stack.length,
        tempResourceCount: ledger.tempResources.length,
        heartbeatAgeMs: heartbeatAge,
        isStale: isStale,
        stackParticipants:
            ledger.stack.map((f) => f.participantId).toList(),
      );
    } finally {
      await releaseLock(operationId: operationId);
    }
  }
}

/// Callback type for backup file creation.
typedef OnBackupCreated = void Function(String backupPath);

/// File-based operation ledger with locking and backup.
class FileLedger {
  final Directory ledgerDir;
  final OnBackupCreated? onBackupCreated;
  static const _lockTimeout = Duration(seconds: 2);
  static const _lockRetryInterval = Duration(milliseconds: 50);

  FileLedger({required String basePath, this.onBackupCreated})
      : ledgerDir = Directory(basePath) {
    if (!ledgerDir.existsSync()) {
      ledgerDir.createSync(recursive: true);
    }
  }

  String _ledgerPath(String operationId) =>
      '${ledgerDir.path}/$operationId.json';

  String _lockPath(String operationId) =>
      '${ledgerDir.path}/$operationId.json.lock';

  String _backupPath(String operationId, String elapsedFormatted) {
    return '${ledgerDir.path}/${operationId}_trail/${elapsedFormatted}_$operationId.json';
  }

  /// Get the trail directory path for an operation.
  String trailPath(String operationId) {
    return '${ledgerDir.path}/${operationId}_trail';
  }

  /// Acquire a lock on the ledger file.
  Future<bool> _acquireLock({required String operationId}) async {
    final lockFile = File(_lockPath(operationId));
    final startTime = DateTime.now();

    while (true) {
      try {
        // Check for stale lock (> 2 seconds old)
        if (lockFile.existsSync()) {
          final stat = lockFile.statSync();
          final age = DateTime.now().difference(stat.modified);
          if (age > _lockTimeout) {
            // Force delete stale lock
            lockFile.deleteSync();
          }
        }

        // Try to create lock file exclusively
        await lockFile.create(exclusive: true);
        // Write our PID and timestamp
        await lockFile.writeAsString(
          '{"pid": ${pid}, "timestamp": "${DateTime.now().toIso8601String()}"}',
        );
        return true;
      } catch (e) {
        // Lock exists, check timeout
        if (DateTime.now().difference(startTime) > const Duration(seconds: 1)) {
          return false; // Give up after 1 second
        }
        await Future.delayed(_lockRetryInterval);
      }
    }
  }

  /// Release the lock.
  Future<void> _releaseLock({required String operationId}) async {
    final lockFile = File(_lockPath(operationId));
    if (lockFile.existsSync()) {
      await lockFile.delete();
    }
  }

  /// Create a backup of the current ledger state.
  Future<String> _createBackup({
    required String operationId,
    required String elapsedFormatted,
  }) async {
    final sourceFile = File(_ledgerPath(operationId));
    if (!sourceFile.existsSync()) return '';

    final backupPath = _backupPath(operationId, elapsedFormatted);
    final backupDir = Directory(trailPath(operationId));
    if (!backupDir.existsSync()) {
      await backupDir.create(recursive: true);
    }

    await sourceFile.copy(backupPath);
    onBackupCreated?.call(backupPath);
    return backupPath;
  }

  /// Create a new operation ledger.
  Future<LedgerData> createOperation({
    required String operationId,
    required int initiatorPid,
    required String description,
  }) async {
    final timestamp = DateTime.now();
    final acquired = await _acquireLock(operationId: operationId);
    if (!acquired) {
      throw StateError('Failed to acquire lock for operation $operationId');
    }

    try {
      final ledger = LedgerData(
        operationId: operationId,
        lastHeartbeat: timestamp,
      );
      // Add initiator frame
      ledger.stack.add(StackFrame(
        participantId: 'initiator',
        callId: 'root',
        pid: initiatorPid,
        startTime: timestamp,
      ));

      final file = File(_ledgerPath(operationId));
      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(ledger.toJson()));

      return ledger;
    } finally {
      await _releaseLock(operationId: operationId);
    }
  }

  /// Read the ledger data with locking.
  Future<LedgerData?> readLedger({required String operationId}) async {
    final file = File(_ledgerPath(operationId));
    if (!file.existsSync()) return null;

    final acquired = await _acquireLock(operationId: operationId);
    if (!acquired) {
      throw StateError('Failed to acquire lock for operation $operationId');
    }

    try {
      final content = await file.readAsString();
      return LedgerData.fromJson(json.decode(content) as Map<String, dynamic>);
    } finally {
      await _releaseLock(operationId: operationId);
    }
  }

  /// Update the ledger with an atomic read-modify-write operation.
  /// [elapsedFormatted] is the elapsed time string (sss.mmm) for backup naming.
  Future<void> updateLedger({
    required String operationId,
    required int callerPid,
    required String elapsedFormatted,
    required LedgerData Function(LedgerData ledger) updater,
  }) async {
    final acquired = await _acquireLock(operationId: operationId);
    if (!acquired) {
      throw StateError('Failed to acquire lock for operation $operationId');
    }

    try {
      final file = File(_ledgerPath(operationId));
      if (!file.existsSync()) {
        throw StateError('Ledger file does not exist: $operationId');
      }

      // Create backup before modifying
      await _createBackup(operationId: operationId, elapsedFormatted: elapsedFormatted);

      // Read current state
      final content = await file.readAsString();
      final ledger =
          LedgerData.fromJson(json.decode(content) as Map<String, dynamic>);

      // Apply update
      final updated = updater(ledger);

      // Write back
      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(updated.toJson()));
    } finally {
      await _releaseLock(operationId: operationId);
    }
  }

  /// Push a stack frame.
  Future<void> pushFrame({
    required String operationId,
    required String participantId,
    required String callId,
    required int pid,
    required String elapsedFormatted,
  }) async {
    await updateLedger(
      operationId: operationId,
      callerPid: pid,
      elapsedFormatted: elapsedFormatted,
      updater: (ledger) {
        ledger.stack.add(StackFrame(
          participantId: participantId,
          callId: callId,
          pid: pid,
          startTime: DateTime.now(),
        ));
        return ledger;
      },
    );
  }

  /// Pop a stack frame.
  Future<void> popFrame({
    required String operationId,
    required String callId,
    required int pid,
    required String elapsedFormatted,
  }) async {
    await updateLedger(
      operationId: operationId,
      callerPid: pid,
      elapsedFormatted: elapsedFormatted,
      updater: (ledger) {
        final index = ledger.stack.lastIndexWhere((f) => f.callId == callId);
        if (index >= 0) {
          ledger.stack.removeAt(index);
        }
        return ledger;
      },
    );
  }

  /// Update heartbeat for the calling process.
  /// Now creates backups like all other file modifications.
  Future<void> updateHeartbeat({
    required String operationId,
    required int pid,
    required String elapsedFormatted,
  }) async {
    final acquired = await _acquireLock(operationId: operationId);
    if (!acquired) return;

    try {
      final file = File(_ledgerPath(operationId));
      if (!file.existsSync()) return;

      // Create backup before modifying
      await _createBackup(
        operationId: operationId,
        elapsedFormatted: elapsedFormatted,
      );

      final content = await file.readAsString();
      final ledger =
          LedgerData.fromJson(json.decode(content) as Map<String, dynamic>);
      ledger.lastHeartbeat = DateTime.now();

      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(ledger.toJson()));
    } finally {
      await _releaseLock(operationId: operationId);
    }
  }

  /// Perform heartbeat with all checks and return detailed results.
  /// Creates a backup and returns comprehensive check information.
  Future<HeartbeatResult> performHeartbeatWithChecks({
    required String operationId,
    required int pid,
    required String elapsedFormatted,
  }) async {
    final file = File(_ledgerPath(operationId));
    if (!file.existsSync()) {
      return HeartbeatResult.noLedger();
    }

    final acquired = await _acquireLock(operationId: operationId);
    if (!acquired) {
      return HeartbeatResult.noLedger();
    }

    try {
      // Create backup before modifying
      await _createBackup(
        operationId: operationId,
        elapsedFormatted: elapsedFormatted,
      );

      // Read current state
      final content = await file.readAsString();
      final ledger =
          LedgerData.fromJson(json.decode(content) as Map<String, dynamic>);

      // Calculate heartbeat age before updating
      final heartbeatAge =
          DateTime.now().difference(ledger.lastHeartbeat).inMilliseconds;
      final isStale = heartbeatAge > 10000;

      // Update heartbeat
      ledger.lastHeartbeat = DateTime.now();

      // Write back
      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(ledger.toJson()));

      return HeartbeatResult(
        abortFlag: ledger.aborted,
        ledgerExists: true,
        heartbeatUpdated: true,
        stackDepth: ledger.stack.length,
        tempResourceCount: ledger.tempResources.length,
        heartbeatAgeMs: heartbeatAge,
        isStale: isStale,
        stackParticipants:
            ledger.stack.map((f) => f.participantId).toList(),
      );
    } finally {
      await _releaseLock(operationId: operationId);
    }
  }

  /// Check if the operation is aborted.
  Future<bool> checkAbort({
    required String operationId,
    required int pid,
  }) async {
    final ledger = await readLedger(operationId: operationId);
    return ledger?.aborted ?? true;
  }

  /// Set the abort flag.
  Future<void> setAbortFlag({
    required String operationId,
    required int pid,
    required bool value,
    required String elapsedFormatted,
  }) async {
    await updateLedger(
      operationId: operationId,
      callerPid: pid,
      elapsedFormatted: elapsedFormatted,
      updater: (ledger) {
        ledger.aborted = value;
        return ledger;
      },
    );
  }

  /// Check if heartbeat is stale (>10 seconds old).
  Future<bool> isHeartbeatStale({
    required String operationId,
    required int pid,
  }) async {
    final ledger = await readLedger(operationId: operationId);
    if (ledger == null) return true;
    return DateTime.now().difference(ledger.lastHeartbeat).inSeconds > 10;
  }

  /// Register a temporary resource.
  Future<void> registerTempResource({
    required String operationId,
    required String path,
    required int owner,
    required String elapsedFormatted,
  }) async {
    await updateLedger(
      operationId: operationId,
      callerPid: owner,
      elapsedFormatted: elapsedFormatted,
      updater: (ledger) {
        ledger.tempResources.add(TempResource(
          path: path,
          owner: owner,
          registeredAt: DateTime.now(),
        ));
        return ledger;
      },
    );
  }

  /// Unregister a temporary resource.
  Future<void> unregisterTempResource({
    required String operationId,
    required String path,
    required int pid,
    required String elapsedFormatted,
  }) async {
    await updateLedger(
      operationId: operationId,
      callerPid: pid,
      elapsedFormatted: elapsedFormatted,
      updater: (ledger) {
        ledger.tempResources.removeWhere((r) => r.path == path);
        return ledger;
      },
    );
  }

  /// Complete the operation - move ledger file to trail folder.
  /// The operation file is preserved as 'final_{operationId}.json' in the trail.
  Future<void> completeOperation({
    required String operationId,
    required int pid,
    required String elapsedFormatted,
  }) async {
    final acquired = await _acquireLock(operationId: operationId);
    if (!acquired) return;

    try {
      final file = File(_ledgerPath(operationId));
      if (!file.existsSync()) return;

      // Update status to 'completed'
      final content = await file.readAsString();
      final ledger =
          LedgerData.fromJson(json.decode(content) as Map<String, dynamic>);
      ledger.status = 'completed';

      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(ledger.toJson()));

      // Ensure trail directory exists
      final trailDir = Directory(trailPath(operationId));
      if (!trailDir.existsSync()) {
        await trailDir.create(recursive: true);
      }

      // Move to trail folder as final file
      final finalPath =
          '${trailPath(operationId)}/${elapsedFormatted}_final_$operationId.json';
      await file.rename(finalPath);
      onBackupCreated?.call(finalPath);
    } finally {
      await _releaseLock(operationId: operationId);
    }
  }

  /// Delete the ledger file (operation complete).
  /// @deprecated Use [completeOperation] instead to preserve the file.
  Future<void> deleteOperation({
    required String operationId,
    required int pid,
    required String elapsedFormatted,
  }) async {
    // Redirect to completeOperation for backwards compatibility
    await completeOperation(
      operationId: operationId,
      pid: pid,
      elapsedFormatted: elapsedFormatted,
    );
  }

  /// Check if a child frame exists in the stack.
  Future<bool> verifyChildExists({
    required String operationId,
    required int childPid,
    required int callerPid,
  }) async {
    final ledger = await readLedger(operationId: operationId);
    if (ledger == null) return false;
    return ledger.stack.any((f) => f.pid == childPid);
  }
}
