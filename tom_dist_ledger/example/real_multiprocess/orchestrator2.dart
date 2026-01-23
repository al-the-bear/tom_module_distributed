/// Distributed Ledger Multi-Process Example - Simplified Orchestrator
///
/// This example demonstrates the same functionality as orchestrator.dart
/// but uses the exec helper methods for a much cleaner implementation:
/// - execFileResultWorker() for file-based workers
/// - execStdioWorker() for stdout-based workers
/// - execServerRequest() for server processes with socket communication
///
/// All workers receive parameters and return "$param1-$param2" to verify
/// correct parameter passing. Workers have 5s delays to show heartbeat entries.
///
/// Run with: dart run example/real_multiprocess/orchestrator2.dart
library;

import 'dart:convert';
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
    participantId: 'orchestrator',
    heartbeatInterval: const Duration(seconds: 2),
    onBackupCreated: (path) {
      print('📦 Backup created: ${path.split('/').last}');
    },
  );

  try {
    // Start the operation
    final operation = await ledger.createOperation(
      description: 'Simplified multi-process demo',
    );

    // Reconfigure heartbeat with custom interval (replaces auto-started heartbeat)
    operation.startHeartbeat(
      interval: const Duration(seconds: 2),
    );

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
    await operation.log('Starting file-based worker with param1=alpha, param2=beta', level: LogLevel.info);

    // Spawn file-based worker with parameters
    final fileWorker = operation.execFileResultWorker<Map<String, dynamic>>(
      executable: 'dart',
      arguments: [
        'run',
        '$exampleDir/file_worker.dart',
        fileResultPath,
        '--param1=alpha',
        '--param2=beta',
        '--delay=5',
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
      print('   Combined result: ${result['combined_result']}');
      print('   (Expected: alpha-beta)');
      print('   Delay: ${result['delay_seconds']}s');
      print('   Timestamp: ${result['timestamp']}');
      await operation.log('File worker completed: ${result['combined_result']}', level: LogLevel.info);
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

    await operation.log('Starting stdout-based worker with param1=gamma, param2=delta', level: LogLevel.info);

    // Spawn stdout-based worker with parameters
    // Note: execStdioWorker requires worker to output ONLY JSON to stdout
    final stdoutWorker = operation.execStdioWorker<Map<String, dynamic>>(
      executable: 'dart',
      arguments: [
        'run',
        '$exampleDir/stdout_worker.dart',
        '--param1=gamma',
        '--param2=delta',
        '--delay=5',
      ],
      description: 'Stdout-based worker',
      onStderr: (line) => print('[StdoutWorker INFO] $line'),
    );

    await stdoutWorker.future;

    if (stdoutWorker.isSuccess) {
      final result = stdoutWorker.result;
      print('\n📤 Stdout Worker Result:');
      print('   Status: ${result['status']}');
      print('   Combined result: ${result['combined_result']}');
      print('   (Expected: gamma-delta)');
      print('   Delay: ${result['delay_seconds']}s');
      print('   Worker: ${result['worker']}');
      await operation.log('Stdout worker completed: ${result['combined_result']}', level: LogLevel.info);
      print('✅ Stdout-based worker completed\n');
    } else {
      print('❌ Stdout worker failed: ${stdoutWorker.error}');
    }

    // ─────────────────────────────────────────────────────────────────────
    // SCENARIO 3: Server process with socket communication
    // ─────────────────────────────────────────────────────────────────────
    print('═══════════════════════════════════════════════════════════════════');
    print('SCENARIO 3: Server Process (socket communication)');
    print('═══════════════════════════════════════════════════════════════════\n');

    const serverPort = 18765;
    await operation.log('Starting server process on port $serverPort', level: LogLevel.info);

    // Start the server process
    final serverProcess = await Process.start(
      'dart',
      [
        'run',
        '$exampleDir/server_worker.dart',
        '--port=$serverPort',
      ],
    );
    serverProcess.stdout.transform(utf8.decoder).listen(
      (line) => print('[Server] $line'),
    );
    serverProcess.stderr.transform(utf8.decoder).listen(
      (line) => print('[Server ERR] $line'),
    );

    // Wait for server to start listening
    await Future.delayed(Duration(milliseconds: 500));

    // Use execServerRequest to track the work with the server
    final serverCall = operation.execServerRequest<Map<String, dynamic>>(
      description: 'Server request',
      failOnCrash: false,
      work: () async {
        // Connect to the server via socket
        print('Connecting to server on port $serverPort...');
        final socket = await Socket.connect(InternetAddress.loopbackIPv4, serverPort);
        
        // Send request with parameters
        final request = {
          'param1': 'epsilon',
          'param2': 'zeta',
          'delay_seconds': 5,
        };
        socket.write('${json.encode(request)}\n');
        await socket.flush();
        
        // Read response
        final responseBuffer = StringBuffer();
        await for (final data in socket) {
          responseBuffer.write(utf8.decode(data));
        }
        await socket.close();
        
        final result = json.decode(responseBuffer.toString()) as Map<String, dynamic>;
        return result;
      },
    );

    await serverCall.future;

    // Wait for server to shutdown gracefully
    await Future.delayed(Duration(milliseconds: 100));
    serverProcess.kill();

    if (serverCall.isSuccess) {
      final result = serverCall.result;
      print('\n📊 Server Result:');
      print('   Status: ${result['status']}');
      print('   Combined result: ${result['combined_result']}');
      print('   (Expected: epsilon-zeta)');
      print('   Delay: ${result['delay_seconds']}s');
      print('   Port: ${result['port']}');
      await operation.log('Server completed: ${result['combined_result']}', level: LogLevel.info);
      print('✅ Server process completed\n');
    } else {
      print('❌ Server call failed: ${serverCall.error}');
    }

    // ─────────────────────────────────────────────────────────────────────
    // BONUS: Run multiple workers in parallel using sync
    // ─────────────────────────────────────────────────────────────────────
    print('═══════════════════════════════════════════════════════════════════');
    print('BONUS: Parallel Workers with sync');
    print('═══════════════════════════════════════════════════════════════════\n');

    await operation.log('Starting parallel workers', level: LogLevel.info);

    // Spawn multiple workers in parallel with different parameters
    final worker1 = operation.execStdioWorker<Map<String, dynamic>>(
      executable: 'dart',
      arguments: [
        'run',
        '$exampleDir/stdout_worker.dart',
        '--param1=worker1',
        '--param2=parallel',
        '--delay=3',
      ],
      description: 'Parallel worker 1',
      onStderr: (line) => print('[Worker1] $line'),
    );

    final worker2 = operation.execStdioWorker<Map<String, dynamic>>(
      executable: 'dart',
      arguments: [
        'run',
        '$exampleDir/stdout_worker.dart',
        '--param1=worker2',
        '--param2=parallel',
        '--delay=3',
      ],
      description: 'Parallel worker 2',
      onStderr: (line) => print('[Worker2] $line'),
    );

    // Wait for all workers using sync
    final syncResult = await operation.sync([worker1, worker2]);

    if (syncResult.allSucceeded) {
      print('✅ All ${syncResult.successfulCalls.length} parallel workers completed!');
      print('   Worker 1 result: ${worker1.result['combined_result']} (expected: worker1-parallel)');
      print('   Worker 2 result: ${worker2.result['combined_result']} (expected: worker2-parallel)');
    } else {
      print('❌ Some workers failed: ${syncResult.failedCalls.length} failed');
    }

    // ─────────────────────────────────────────────────────────────────────
    // Complete the operation and show heartbeat log
    // ─────────────────────────────────────────────────────────────────────
    print('\n═══════════════════════════════════════════════════════════════════');
    print('Completing Operation');
    print('═══════════════════════════════════════════════════════════════════\n');

    final elapsed = operation.elapsedDuration;
    await operation.log('All workers completed in ${elapsed.inSeconds}s', level: LogLevel.info);
    operation.stopHeartbeat();
    await operation.complete();
    print('✅ Operation completed successfully!');
    print('   Total elapsed: ${elapsed.inMilliseconds}ms\n');

    // Show debug log to demonstrate heartbeat entries
    print('═══════════════════════════════════════════════════════════════════');
    print('Debug Log (showing heartbeat entries)');
    print('═══════════════════════════════════════════════════════════════════\n');
    
    final debugLogPath = '${tempDir.path}/${operation.operationId}.operation.debug.log';
    final debugLogFile = File(debugLogPath);
    if (debugLogFile.existsSync()) {
      final lines = debugLogFile.readAsLinesSync();
      // Show last 20 lines
      final showLines = lines.length > 20 ? lines.sublist(lines.length - 20) : lines;
      for (final line in showLines) {
        print('  $line');
      }
      print('\n  (${lines.length} total lines, showing last 20)');
    }

  } catch (e, st) {
    print('❌ Error: $e');
    print(st);
  } finally {
    ledger.dispose();
    print('\n🧹 Ledger disposed');
    print('📁 Temp directory (not deleted for inspection): ${tempDir.path}');
  }
}

