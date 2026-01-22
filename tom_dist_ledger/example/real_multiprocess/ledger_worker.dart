/// Distributed Ledger Worker Process
///
/// This worker demonstrates TRUE multi-process ledger participation:
/// 1. Joins an existing operation using the shared ledger
/// 2. Pushes its own stack frame for tracking
/// 3. Does work while maintaining heartbeat
/// 4. Pops stack frame when done
///
/// This is different from stdout_worker and file_worker which are just
/// subprocesses - this worker actually participates in the distributed
/// ledger system.
///
/// Arguments:
///   `--ledger-path=<path>`     Required: Path to the ledger directory
///   `--operation-id=<id>`      Required: Operation ID to join
///   `--participant-id=<id>`    Required: Unique participant identifier
///   `--work-duration=<ms>`     Optional: Simulated work duration (default: 1000)
///
/// Run with:
///   dart run example/real_multiprocess/ledger_worker.dart \
///     --ledger-path=/tmp/ledger \
///     --operation-id=20260122T10:30:45.123-orchestrator-abc123 \
///     --participant-id=worker1
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tom_dist_ledger/tom_dist_ledger.dart';

void main(List<String> args) async {
  // Parse arguments
  String? ledgerPath;
  String? operationId;
  String? participantId;
  int workDuration = 1000;

  for (final arg in args) {
    if (arg.startsWith('--ledger-path=')) {
      ledgerPath = arg.substring('--ledger-path='.length);
    } else if (arg.startsWith('--operation-id=')) {
      operationId = arg.substring('--operation-id='.length);
    } else if (arg.startsWith('--participant-id=')) {
      participantId = arg.substring('--participant-id='.length);
    } else if (arg.startsWith('--work-duration=')) {
      workDuration = int.parse(arg.substring('--work-duration='.length));
    }
  }

  if (ledgerPath == null || operationId == null || participantId == null) {
    stderr.writeln('Usage: dart run ledger_worker.dart \\');
    stderr.writeln('  --ledger-path=<path> \\');
    stderr.writeln('  --operation-id=<id> \\');
    stderr.writeln('  --participant-id=<id> \\');
    stderr.writeln('  [--work-duration=<ms>]');
    exit(1);
  }

  stderr.writeln('[$participantId] Starting ledger worker (pid: $pid)');
  stderr.writeln('[$participantId] Ledger path: $ledgerPath');
  stderr.writeln('[$participantId] Operation ID: $operationId');

  // Create ledger instance pointing to the same directory
  final ledger = Ledger(
    basePath: ledgerPath,
    onBackupCreated: (path) {
      stderr.writeln('[$participantId] 📦 Backup: ${path.split('/').last}');
    },
  );

  try {
    // Join the existing operation
    stderr.writeln('[$participantId] Joining operation...');
    final operation = await ledger.joinOperation(
      operationId: operationId,
      participantId: participantId,
    );

    stderr.writeln('[$participantId] ✅ Joined operation');
    await operation.log('Worker joined', level: LogLevel.info);

    // Push our own stack frame
    stderr.writeln('[$participantId] Pushing stack frame...');
    await operation.pushStackFrame(callId: '$participantId-work');

    // Verify we're in the stack
    final data = operation.cachedData;
    final myFrame = data?.stack.where((f) => f.participantId == participantId);
    stderr.writeln('[$participantId] Stack has ${data?.stack.length ?? 0} frames');
    stderr.writeln('[$participantId] My frame: ${myFrame?.isNotEmpty == true ? 'present' : 'MISSING'}');

    // Start heartbeat
    operation.startHeartbeat(
      interval: Duration(milliseconds: 500),
      onSuccess: (op, result) {
        stderr.writeln('[$participantId] ♥ heartbeat (stack: ${result.stackDepth})');
      },
    );

    // Do simulated work
    stderr.writeln('[$participantId] Working for ${workDuration}ms...');
    await operation.log('Starting work', level: LogLevel.debug);
    
    // Simulate work in chunks
    final chunks = 5;
    final chunkDuration = workDuration ~/ chunks;
    for (var i = 0; i < chunks; i++) {
      await Future.delayed(Duration(milliseconds: chunkDuration));
      stderr.writeln('[$participantId] Progress: ${((i + 1) / chunks * 100).toInt()}%');
    }

    await operation.log('Work completed', level: LogLevel.info);
    stderr.writeln('[$participantId] Work complete!');

    // Stop heartbeat
    operation.stopHeartbeat();

    // Pop our stack frame
    stderr.writeln('[$participantId] Popping stack frame...');
    await operation.popStackFrame(callId: '$participantId-work');

    // Verify we're no longer in the stack
    final dataAfter = operation.cachedData;
    final myFrameAfter = dataAfter?.stack.where((f) => f.participantId == participantId);
    stderr.writeln('[$participantId] Stack now has ${dataAfter?.stack.length ?? 0} frames');
    stderr.writeln('[$participantId] My frame: ${myFrameAfter?.isEmpty == true ? 'removed ✅' : 'STILL PRESENT ❌'}');

    // Return success result via stdout (JSON)
    final result = {
      'status': 'success',
      'participant_id': participantId,
      'pid': pid,
      'work_duration_ms': workDuration,
      'timestamp': DateTime.now().toIso8601String(),
    };
    stdout.write(jsonEncode(result));

    stderr.writeln('[$participantId] Done!');
  } catch (e, st) {
    stderr.writeln('[$participantId] ERROR: $e');
    stderr.writeln(st);
    
    // Return error result
    final result = {
      'status': 'error',
      'participant_id': participantId,
      'pid': pid,
      'error': e.toString(),
    };
    stdout.write(jsonEncode(result));
    exit(1);
  } finally {
    ledger.dispose();
  }
}
