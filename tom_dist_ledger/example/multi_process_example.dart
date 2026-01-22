/// Multi-Process Distributed Ledger Example
///
/// Demonstrates the Ledger API with multiple communication patterns:
/// 1. File-based result passing - Worker writes result to file
/// 2. Stdout result passing - Worker returns result via stdout
/// 3. Long-running server - Server process handles multiple calls
///
/// This example simulates multi-process coordination without actually
/// spawning separate processes - it uses isolated futures to simulate
/// the behavior.
///
/// Run with: dart run example/multi_process_example.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:tom_dist_ledger/tom_dist_ledger.dart';

/// Simulates a worker process that writes its result to a file.
class FileOutputWorker {
  final String outputPath;
  final Duration workDuration;

  FileOutputWorker({
    required this.outputPath,
    required this.workDuration,
  });

  /// Simulates worker execution - does work then writes result to file.
  Future<void> run() async {
    print('[FileWorker] Starting work...');
    await Future.delayed(workDuration);
    
    final result = {
      'status': 'success',
      'computed_value': 42,
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    final file = File(outputPath);
    await file.writeAsString(jsonEncode(result));
    print('[FileWorker] Wrote result to $outputPath');
  }
}

/// Simulates a worker process that returns result via stdout.
class StdoutOutputWorker {
  final Duration workDuration;

  StdoutOutputWorker({required this.workDuration});

  /// Returns the result that would be written to stdout.
  Future<String> run() async {
    print('[StdoutWorker] Starting work...');
    await Future.delayed(workDuration);
    
    final result = jsonEncode({
      'result': 'computation_complete',
      'value': 123.45,
      'metadata': {'worker_id': 'stdout_worker'},
    });
    
    print('[StdoutWorker] Returning result via stdout');
    return result;
  }
}

/// Simulates a long-running server process that handles multiple requests.
class ServerProcess {
  final int port;
  final Random _random = Random();
  bool _running = false;

  ServerProcess({required this.port});

  /// Starts the server.
  Future<void> start() async {
    _running = true;
    print('[Server:$port] Server started');
  }

  /// Handles a request with random 3-10 second delay.
  Future<Map<String, dynamic>> handleRequest(String requestId) async {
    if (!_running) {
      throw StateError('Server not running');
    }
    
    final delay = Duration(seconds: 3 + _random.nextInt(8)); // 3-10 seconds
    print('[Server:$port] Processing request $requestId (delay: ${delay.inSeconds}s)');
    await Future.delayed(delay);
    
    return {
      'requestId': requestId,
      'status': 'processed',
      'processingTime': delay.inSeconds,
      'port': port,
    };
  }

  /// Stops the server.
  Future<void> stop() async {
    _running = false;
    print('[Server:$port] Server stopped');
  }
}

/// Polls for a file to appear and reads its content.
Future<T> pollFile<T>({
  required String path,
  bool delete = false,
  T Function(String content)? deserializer,
  Duration pollInterval = const Duration(milliseconds: 100),
  Duration? timeout,
}) async {
  final stopwatch = Stopwatch()..start();
  
  while (true) {
    final file = File(path);
    if (await file.exists()) {
      final content = await file.readAsString();
      if (delete) {
        await file.delete();
      }
      
      if (deserializer != null) {
        return deserializer(content);
      }
      // Default handling for common types
      if (T == String) {
        return content as T;
      }
      if (T == dynamic || T.toString().contains('Map')) {
        return jsonDecode(content) as T;
      }
      return content as T;
    }
    
    if (timeout != null && stopwatch.elapsed > timeout) {
      throw TimeoutException('File $path did not appear within $timeout');
    }
    
    await Future.delayed(pollInterval);
  }
}

void main() async {
  print('═══════════════════════════════════════════════════════════════════');
  print('Multi-Process Distributed Ledger Example');
  print('═══════════════════════════════════════════════════════════════════\n');

  final tempDir = Directory.systemTemp.createTempSync('multiprocess_example_');
  print('Working directory: ${tempDir.path}\n');

  final ledger = Ledger(
    basePath: tempDir.path,
    onBackupCreated: (path) => print('📦 Backup created: $path'),
  );

  // Track cleanup callbacks
  ServerProcess? serverProcess;

  try {
    // Start the main operation
    final operation = await ledger.createOperation(
      operationId: 'multi_process_demo',
      participantId: 'orchestrator',
    );

    print('✅ Started operation: ${operation.operationId}\n');

    // ─────────────────────────────────────────────────────────────────────
    // SCENARIO 1: File-based result passing
    // ─────────────────────────────────────────────────────────────────────
    print('═══════════════════════════════════════════════════════════════════');
    print('SCENARIO 1: File-based Result Passing');
    print('═══════════════════════════════════════════════════════════════════\n');

    final fileResultPath = '${tempDir.path}/worker_result.json';
    
    // Create the worker
    final fileWorker = FileOutputWorker(
      outputPath: fileResultPath,
      workDuration: const Duration(seconds: 1),
    );

    // Start a call that will wait for the file result
    final fileCall = await operation.startCall(
      callback: CallCallback(
        onCleanup: () async {
          // Clean up the result file if it exists
          final file = File(fileResultPath);
          if (await file.exists()) {
            await file.delete();
            print('[Cleanup] Deleted $fileResultPath');
          }
        },
      ),
      description: 'File-based worker call',
    );

    // Start the worker (in real scenario, this would be Process.start)
    final workerFuture = fileWorker.run();

    // Poll for the file result
    final fileResult = await pollFile<Map<String, dynamic>>(
      path: fileResultPath,
      delete: true,
      timeout: const Duration(seconds: 10),
    );

    await workerFuture; // Ensure worker completed

    print('\n📄 File Worker Result:');
    print('   Status: ${fileResult['status']}');
    print('   Value: ${fileResult['computed_value']}');
    print('   Timestamp: ${fileResult['timestamp']}');

    await fileCall.end();
    print('✅ File-based call completed\n');

    // ─────────────────────────────────────────────────────────────────────
    // SCENARIO 2: Stdout-based result passing
    // ─────────────────────────────────────────────────────────────────────
    print('═══════════════════════════════════════════════════════════════════');
    print('SCENARIO 2: Stdout-based Result Passing');
    print('═══════════════════════════════════════════════════════════════════\n');

    final stdoutWorker = StdoutOutputWorker(
      workDuration: const Duration(milliseconds: 500),
    );

    final stdoutCall = await operation.startCall(
      callback: CallCallback(
        onCleanup: () async {
          print('[Cleanup] Stdout worker cleanup (no resources to clean)');
        },
      ),
      description: 'Stdout-based worker call',
    );

    // In real scenario, you'd read from process.stdout
    // Here we simulate by calling run() directly
    final stdoutResult = await stdoutWorker.run();
    final parsedStdout = jsonDecode(stdoutResult) as Map<String, dynamic>;

    print('\n📤 Stdout Worker Result:');
    print('   Result: ${parsedStdout['result']}');
    print('   Value: ${parsedStdout['value']}');
    print('   Worker ID: ${parsedStdout['metadata']['worker_id']}');

    await stdoutCall.end();
    print('✅ Stdout-based call completed\n');

    // ─────────────────────────────────────────────────────────────────────
    // SCENARIO 3: Long-running server with multiple calls
    // ─────────────────────────────────────────────────────────────────────
    print('═══════════════════════════════════════════════════════════════════');
    print('SCENARIO 3: Long-running Server with Multiple Calls');
    print('═══════════════════════════════════════════════════════════════════\n');

    serverProcess = ServerProcess(port: 8080);

    // Start server with failOnCrash=false since server runs throughout
    final serverCall = await operation.startCall(
      callback: CallCallback(
        onCleanup: () async {
          print('[Cleanup] Stopping server...');
          await serverProcess?.stop();
          serverProcess = null;
        },
      ),
      description: 'Long-running server',
      failOnCrash: false, // Server crash shouldn't fail entire operation
    );

    await serverProcess!.start();

    // Spawn multiple requests in parallel using the new spawnCall API
    print('\n📡 Sending parallel requests to server...\n');

    final spawnedCalls = <SpawnedCall<Map<String, dynamic>>>[];
    
    for (var i = 1; i <= 3; i++) {
      final requestId = 'request_$i';
      
      final spawnedCall = operation.spawnCall<Map<String, dynamic>>(
        work: () async {
          return await serverProcess!.handleRequest(requestId);
        },
        callback: CallCallback(
          onCleanup: () async {
            print('[Cleanup] Request $requestId cleanup');
          },
        ),
        description: 'Server request $requestId',
        failOnCrash: true, // Individual request failures should be reported
      );
      
      spawnedCalls.add(spawnedCall);
    }

    // Wait for all requests to complete using sync
    final syncResult = await operation.sync(spawnedCalls);

    print('\n📊 Server Request Results:');
    for (final call in spawnedCalls) {
      if (call.isSuccess) {
        final result = call.result;
        print('   ${result['requestId']}: ${result['status']} (${result['processingTime']}s)');
      } else {
        print('   ${call.callId}: FAILED - ${call.error}');
      }
    }

    // Check sync results
    print('   Successful: ${syncResult.successfulCalls.length}');
    print('   Failed: ${syncResult.failedCalls.length}');

    // Clean up server
    await serverProcess!.stop();
    await serverCall.end();
    serverProcess = null;
    print('\n✅ Server scenario completed\n');

    // ─────────────────────────────────────────────────────────────────────
    // Complete the operation
    // ─────────────────────────────────────────────────────────────────────
    print('═══════════════════════════════════════════════════════════════════');
    print('Completing Operation');
    print('═══════════════════════════════════════════════════════════════════\n');

    await operation.complete();
    print('✅ Operation completed successfully!\n');

    // Show final state
    print('📁 Ledger state:');
    final backupDir = Directory('${tempDir.path}/backup');
    if (backupDir.existsSync()) {
      final entries = backupDir.listSync();
      print('   Backup entries: ${entries.length}');
      for (final entry in entries.take(5)) {
        print('   - ${entry.path.split('/').last}');
      }
    }

  } catch (e, stackTrace) {
    print('❌ Error: $e');
    print(stackTrace);
    
    // Ensure server is stopped on error
    if (serverProcess != null) {
      await serverProcess!.stop();
    }
  } finally {
    ledger.dispose();
    
    // Clean up temp directory
    await Future.delayed(const Duration(milliseconds: 100));
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
      print('🧹 Cleaned up temp directory');
    }
  }
}
