/// Distributed Ledger Multi-Process Example - Simplified Orchestrator
///
/// This example demonstrates the same functionality as orchestrator.dart
/// but uses the exec helper methods for a much cleaner implementation:
/// - execFileResultWorker() for file-based workers
/// - execStdioWorker() for stdout-based workers
/// - execServerCall() for server processes with custom work
///
/// Run with: dart run example/real_multiprocess/orchestrator2.dart
library;

import 'dart:io';

import 'package:tom_dist_ledger/tom_dist_ledger.dart';

void main() async {
  print('═══════════════════════════════════════════════════════════════════');
  print('Distributed Ledger Multi-Process Example (Simplified with Helpers)');
  print('═══════════════════════════════════════════════════════════════════\n');

  // Create temp directory for ledger
  final tempDir = Directory.systemTemp.createTempSync('multiprocess_simple_');
  print('Ledger directory: ${tempDir.path}');

  final ledger = Ledger(
    basePath: tempDir.path,
    onBackupCreated: (path) {
      print('📦 Backup created: ${path.split('/').last}');
    },
  );

  // Track start time for elapsed formatting
  DateTime? operationStartTime;

  try {
    // Start the operation
    final operation = await ledger.createOperation(
      participantId: 'orchestrator',
      participantPid: pid,
      getElapsedFormatted: () {
        // Use operation.startTime if available, else current time
        final start = operationStartTime ?? DateTime.now();
        final elapsed = DateTime.now().difference(start);
        return '${elapsed.inSeconds.toString().padLeft(3, '0')}.${(elapsed.inMilliseconds % 1000).toString().padLeft(3, '0')}';
      },
      description: 'Simplified multi-process demo',
    );
    
    // Now we can use operation.startTime
    operationStartTime = operation.startTime;

    print('✅ Started operation: ${operation.operationId}');
    print('   Start time: ${operation.startTimeIso}');
    print('   Start time (ms): ${operation.startTimeMs}\n');

    await operation.log('Operation started', level: LogLevel.info);

    // Get the path to this example directory
    final scriptDir = Platform.script.toFilePath();
    final exampleDir = Directory(scriptDir).parent.path;

    // ─────────────────────────────────────────────────────────────────────
    // SCENARIO 1: File-based worker using execFileResultWorker
    // ─────────────────────────────────────────────────────────────────────
    print('═══════════════════════════════════════════════════════════════════');
    print('SCENARIO 1: File-based Worker (using execFileResultWorker)');
    print('═══════════════════════════════════════════════════════════════════\n');

    final fileResultPath = '${tempDir.path}/file_worker_result.json';
    await operation.log('Starting file-based worker with helper', level: LogLevel.info);

    // One line to spawn, wait, and get result!
    final fileWorker = operation.execFileResultWorker<Map<String, dynamic>>(
      executable: 'dart',
      arguments: [
        'run',
        '$exampleDir/file_worker.dart',
        fileResultPath,
        '--start-time=${operation.startTimeMs}', // Pass start time to worker!
      ],
      resultFilePath: fileResultPath,
      description: 'File-based worker',
      deleteResultFile: false, // Keep for inspection
      timeout: Duration(seconds: 30),
      onStdout: (line) => print('[FileWorker] $line'),
      onStderr: (line) => print('[FileWorker ERR] $line'),
    );

    // Wait for completion
    await fileWorker.future;

    if (fileWorker.isSuccess) {
      final result = fileWorker.result;
      print('\n📄 File Worker Result:');
      print('   Status: ${result['status']}');
      print('   Value: ${result['computed_value']}');
      print('   Timestamp: ${result['timestamp']}');
      await operation.log('File worker completed successfully', level: LogLevel.info);
      print('✅ File-based worker completed\n');
    } else {
      print('❌ File worker failed: ${fileWorker.error}');
    }

    // ─────────────────────────────────────────────────────────────────────
    // SCENARIO 2: Stdout-based worker using execStdioWorker
    // ─────────────────────────────────────────────────────────────────────
    print('═══════════════════════════════════════════════════════════════════');
    print('SCENARIO 2: Stdout-based Worker (using execStdioWorker)');
    print('═══════════════════════════════════════════════════════════════════\n');

    await operation.log('Starting stdout-based worker with helper', level: LogLevel.info);

    // One line to spawn, wait, and parse stdout!
    final stdoutWorker = operation.execStdioWorker<Map<String, dynamic>>(
      executable: 'dart',
      arguments: ['run', '$exampleDir/stdout_worker.dart'],
      description: 'Stdout-based worker',
      onStderr: (line) => print('[StdoutWorker INFO] $line'),
    );

    await stdoutWorker.future;

    if (stdoutWorker.isSuccess) {
      final result = stdoutWorker.result;
      print('\n📤 Stdout Worker Result:');
      print('   Result: ${result['result']}');
      print('   Value: ${result['value']}');
      print('   Worker: ${result['worker']}');
      await operation.log('Stdout worker completed successfully', level: LogLevel.info);
      print('✅ Stdout-based worker completed\n');
    } else {
      print('❌ Stdout worker failed: ${stdoutWorker.error}');
    }

    // ─────────────────────────────────────────────────────────────────────
    // SCENARIO 3: Server process using execServerCall
    // ─────────────────────────────────────────────────────────────────────
    print('═══════════════════════════════════════════════════════════════════');
    print('SCENARIO 3: Server Process (using execServerCall)');
    print('═══════════════════════════════════════════════════════════════════\n');

    final serverResultPath = '${tempDir.path}/server_result.json';
    await operation.log('Starting server process with helper', level: LogLevel.info);

    // Spawn server and execute custom work with it
    final serverCall = operation.execServerCall<Map<String, dynamic>>(
      executable: 'dart',
      arguments: ['run', '$exampleDir/server_worker.dart', serverResultPath],
      description: 'Server process',
      startupDelay: Duration(milliseconds: 100), // Wait for server to start
      onStdout: (line) => print('[Server] $line'),
      onStderr: (line) => print('[Server ERR] $line'),
      failOnCrash: false, // Server crash shouldn't fail entire operation
      work: (server) async {
        // This is where you would make HTTP calls, socket connections, etc.
        // For this example, we just wait for the server to write its result file
        print('Waiting for server to complete work...');

        // Poll for the server result file
        final result = await OperationHelper.pollFile<Map<String, dynamic>>(
          path: serverResultPath,
          delete: false,
          timeout: Duration(seconds: 60),
        )();

        return result;
      },
    );

    await serverCall.future;

    if (serverCall.isSuccess) {
      final result = serverCall.result;
      print('\n📊 Server Result:');
      print('   Requests handled: ${result['requests_handled']}');
      print('   Total time: ${result['total_time_ms']}ms');

      final requests = result['request_results'] as List;
      for (final req in requests) {
        print('   - ${req['request_id']}: ${req['status']} (${req['delay_ms']}ms)');
      }
      await operation.log('Server completed successfully', level: LogLevel.info);
      print('✅ Server process completed\n');
    } else {
      print('❌ Server call failed: ${serverCall.error}');
    }

    // ─────────────────────────────────────────────────────────────────────
    // BONUS: Run multiple workers in parallel using syncTyped
    // ─────────────────────────────────────────────────────────────────────
    print('═══════════════════════════════════════════════════════════════════');
    print('BONUS: Parallel Workers with syncTyped');
    print('═══════════════════════════════════════════════════════════════════\n');

    await operation.log('Starting parallel workers', level: LogLevel.info);

    // Spawn multiple workers in parallel
    final worker1 = operation.execStdioWorker<Map<String, dynamic>>(
      executable: 'dart',
      arguments: ['run', '$exampleDir/stdout_worker.dart'],
      description: 'Parallel worker 1',
    );

    final worker2 = operation.execStdioWorker<Map<String, dynamic>>(
      executable: 'dart',
      arguments: ['run', '$exampleDir/stdout_worker.dart'],
      description: 'Parallel worker 2',
    );

    // Wait for all workers using syncTyped
    final syncResult = await operation.syncTyped([worker1, worker2]);

    if (syncResult.allSucceeded) {
      print('✅ All ${syncResult.successfulCalls.length} parallel workers completed!');
      print('   Worker 1 value: ${worker1.result['value']}');
      print('   Worker 2 value: ${worker2.result['value']}');
    } else {
      print('❌ Some workers failed: ${syncResult.failedCalls.length} failed');
    }

    // ─────────────────────────────────────────────────────────────────────
    // Complete the operation
    // ─────────────────────────────────────────────────────────────────────
    print('\n═══════════════════════════════════════════════════════════════════');
    print('Completing Operation');
    print('═══════════════════════════════════════════════════════════════════\n');

    final elapsed = operation.elapsedDuration;
    await operation.log('All workers completed in ${elapsed.inSeconds}s', level: LogLevel.info);
    await operation.complete();
    print('✅ Operation completed successfully!');
    print('   Total elapsed: ${elapsed.inMilliseconds}ms\n');

    // Show comparison
    print('═══════════════════════════════════════════════════════════════════');
    print('Code Comparison');
    print('═══════════════════════════════════════════════════════════════════');
    print('');
    print('Original orchestrator.dart: ~170 lines for 3 scenarios');
    print('Simplified orchestrator2.dart: ~100 lines for 4 scenarios');
    print('');
    print('Key differences:');
    print('  - No manual Process.start() calls');
    print('  - No manual stdout/stderr stream handling');
    print('  - No manual CallCallback creation');
    print('  - No manual callId management');
    print('  - startTime available for passing to workers');
    print('  - Built-in timeout and error handling');
    print('');

  } catch (e, st) {
    print('❌ Error: $e');
    print(st);
  } finally {
    ledger.dispose();
    print('🧹 Ledger disposed');
    print('📁 Temp directory (not deleted for inspection): ${tempDir.path}');
  }
}
