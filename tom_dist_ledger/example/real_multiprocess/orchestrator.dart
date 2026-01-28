/// Distributed Ledger Multi-Process Example - Orchestrator
///
/// This example demonstrates TRUE multi-process ledger participation:
/// - Orchestrator creates an operation
/// - Workers JOIN the operation using the shared ledger
/// - Each worker pushes its own call frame
/// - Workers are visible in the ledger while running
/// - Validation confirms all workers appeared and disappeared correctly
///
/// Run with: dart run example/real_multiprocess/orchestrator.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:tom_dist_ledger/tom_dist_ledger.dart';

void main() async {
  print('═══════════════════════════════════════════════════════════════════');
  print('Distributed Ledger - TRUE Multi-Process Example');
  print('═══════════════════════════════════════════════════════════════════\n');

  // Create temp directory for ledger
  final tempDir = Directory.systemTemp.createTempSync('multiprocess_dist_');
  print('Ledger directory: ${tempDir.path}');

  // Track all backups for validation
  final backups = <String>[];
  
  final ledger = (await Ledger.connect(
    basePath: tempDir.path,
    participantId: 'orchestrator',
    callback: LedgerCallback(
      onBackupCreated: (path) {
        backups.add(path);
        print('📦 Backup created: ${path.split('/').last}');
      },
    ),
  ))!;

  // Track max call frame count observed
  int maxCallFrameCount = 0;
  final observedParticipants = <String>{};

  try {
    // Start the operation
    final operation = await ledger.createOperation(
      description: 'True distributed multi-process demo',
    );

    print('✅ Started operation: ${operation.operationId}');
    print('   Start time: ${operation.startTimeIso}');
    print('   Ledger path: ${tempDir.path}\n');

    await operation.log('Operation started by orchestrator', level: DLLogLevel.info);

    // Push orchestrator's call frame
    await operation.createCallFrame(callId: 'orchestrator-main');
    print('📌 Orchestrator pushed call frame\n');

    // Get the path to this example directory
    final scriptDir = Platform.script.toFilePath();
    final exampleDir = Directory(scriptDir).parent.path;

    // ─────────────────────────────────────────────────────────────────────
    // Launch workers that JOIN the operation
    // ─────────────────────────────────────────────────────────────────────
    print('═══════════════════════════════════════════════════════════════════');
    print('Launching Distributed Workers');
    print('═══════════════════════════════════════════════════════════════════\n');

    // Heartbeat auto-started by createOperation

    // Launch 3 workers that will join the operation
    final workers = <String>['worker1', 'worker2', 'worker3'];
    final processes = <Future<ProcessResult>>[];

    for (final workerId in workers) {
      print('🚀 Launching $workerId...');
      
      final process = Process.run(
        'dart',
        [
          'run',
          '$exampleDir/ledger_worker.dart',
          '--ledger-path=${tempDir.path}',
          '--operation-id=${operation.operationId}',
          '--participant-id=$workerId',
          '--work-duration=2000',
        ],
      );
      processes.add(process);
      
      // Stagger worker launches slightly
      await Future.delayed(Duration(milliseconds: 300));
    }

    print('\n⏳ Waiting for all workers to complete...\n');

    // Wait for all workers
    final results = await Future.wait(processes);

    print('\n═══════════════════════════════════════════════════════════════════');
    print('Worker Results');
    print('═══════════════════════════════════════════════════════════════════\n');

    final workerResults = <Map<String, dynamic>>[];
    for (var i = 0; i < results.length; i++) {
      final result = results[i];
      print('${workers[i]}:');
      print('  Exit code: ${result.exitCode}');
      
      if (result.stdout.toString().isNotEmpty) {
        try {
          final json = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
          workerResults.add(json);
          print('  Status: ${json['status']}');
          print('  PID: ${json['pid']}');
        } catch (e) {
          print('  Output: ${result.stdout}');
        }
      }
      
      if (result.stderr.toString().isNotEmpty) {
        final lines = result.stderr.toString().trim().split('\n');
        if (lines.length <= 5) {
          for (final line in lines) {
            print('  [stderr] $line');
          }
        } else {
          print('  [stderr] ... ${lines.length} lines (showing last 3)');
          for (final line in lines.sublist(lines.length - 3)) {
            print('  [stderr] $line');
          }
        }
      }
      print('');
    }

    // Pop orchestrator's call frame
    await operation.deleteCallFrame(callId: 'orchestrator-main');
    print('📌 Orchestrator popped call frame\n');

    // Complete the operation
    await operation.log('All workers completed', level: DLLogLevel.info);
    await operation.complete();
    print('✅ Operation completed!\n');

    // ─────────────────────────────────────────────────────────────────────
    // VALIDATION
    // ─────────────────────────────────────────────────────────────────────
    print('═══════════════════════════════════════════════════════════════════');
    print('VALIDATION');
    print('═══════════════════════════════════════════════════════════════════\n');

    var validationPassed = true;

    // 1. Check all workers completed successfully
    print('1. Worker completion status:');
    final successfulWorkers = workerResults.where((r) => r['status'] == 'success').length;
    if (successfulWorkers == workers.length) {
      print('   ✅ All ${workers.length} workers completed successfully');
    } else {
      print('   ❌ Only $successfulWorkers/${workers.length} workers succeeded');
      validationPassed = false;
    }

    // 2. Check all workers were observed in the call frames
    print('\n2. Stack participation:');
    print('   Max call frame count observed: $maxCallFrameCount');
    print('   Participants observed: $observedParticipants');
    
    final missingParticipants = workers.where((w) => !observedParticipants.contains(w)).toList();
    if (missingParticipants.isEmpty) {
      print('   ✅ All workers appeared in the call frames during execution');
    } else {
      print('   ❌ Missing workers from stack: $missingParticipants');
      validationPassed = false;
    }

    // 3. Check final stack is empty (operation is completed, check backup)
    print('\n3. Final stack state:');
    final backupFolder = Directory('${tempDir.path}/backup/${operation.operationId}');
    if (backupFolder.existsSync()) {
      final backupOpFile = File('${backupFolder.path}/operation.json');
      if (backupOpFile.existsSync()) {
        final backupData = LedgerData.fromJson(
          jsonDecode(backupOpFile.readAsStringSync()) as Map<String, dynamic>,
        );
        if (backupData.callFrames.isEmpty) {
          print('   ✅ Final stack is empty (verified from backup)');
        } else {
          print('   ❌ Stack still has ${backupData.callFrames.length} frames!');
          for (final frame in backupData.callFrames) {
            print('      - ${frame.participantId}: ${frame.callId}');
          }
          validationPassed = false;
        }
      } else {
        print('   ⚠️  Backup operation file not found');
      }
    } else {
      print('   ⚠️  Backup folder not found');
    }

    // 4. Check backups were created
    print('\n4. Backup trail:');
    print('   Total backups created: ${backups.length}');
    if (backups.length >= workers.length * 2) { // At least push+pop per worker
      print('   ✅ Sufficient backup trail for debugging');
    } else {
      print('   ⚠️  Fewer backups than expected (may be OK)');
    }

    // 5. Check log file
    print('\n5. Log file:');
    final logFile = File('${tempDir.path}/backup/${operation.operationId}/operation.log');
    if (logFile.existsSync()) {
      final logLines = logFile.readAsLinesSync();
      print('   Log entries: ${logLines.length}');
      
      final workerLogEntries = logLines.where((l) => l.contains('Worker')).length;
      if (workerLogEntries >= workers.length) {
        print('   ✅ Worker activity logged');
      } else {
        print('   ⚠️  Only $workerLogEntries worker log entries found');
      }
    } else {
      print('   ⚠️  Log file not found in backup');
    }

    // Summary
    print('\n═══════════════════════════════════════════════════════════════════');
    if (validationPassed) {
      print('🎉 VALIDATION PASSED - All checks succeeded!');
    } else {
      print('❌ VALIDATION FAILED - Some checks failed');
    }
    print('═══════════════════════════════════════════════════════════════════\n');

    print('📁 Ledger directory (not deleted for inspection): ${tempDir.path}');
    print('   - backup/${operation.operationId}/operation.json  (final state)');
    print('   - backup/${operation.operationId}/operation.log   (execution log)');
    print('   - ${operation.operationId}_trail/                 (per-modification snapshots)');

  } catch (e, st) {
    print('❌ Error: $e');
    print(st);
  } finally {
    ledger.dispose();
    print('\n🧹 Ledger disposed');
  }
}
