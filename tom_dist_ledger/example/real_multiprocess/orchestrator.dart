/// Distributed Ledger Multi-Process Example - Orchestrator
///
/// This is the main initiator process that:
/// 1. Creates a ledger and starts an operation
/// 2. Spawns worker processes using `dart run ...`
/// 3. Monitors their progress and collects results
/// 4. Demonstrates both file-based and stdout-based result passing
///
/// Run with: dart run example/real_multiprocess/orchestrator.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:tom_dist_ledger/tom_dist_ledger.dart';

void main() async {
  print('═══════════════════════════════════════════════════════════════════');
  print('Distributed Ledger Multi-Process Example');
  print('═══════════════════════════════════════════════════════════════════\n');

  // Create temp directory for ledger
  final tempDir = Directory.systemTemp.createTempSync('multiprocess_real_');
  print('Ledger directory: ${tempDir.path}');

  final ledger = Ledger(
    basePath: tempDir.path,
    participantId: 'orchestrator',
    onBackupCreated: (path) {
      print('📦 Backup created: ${path.split('/').last}');
    },
  );

  try {
    // Start the operation
    final operation = await ledger.createOperation(
      description: 'multiprocess_demo',
    );

    print('✅ Started operation: ${operation.operationId}\n');
    await operation.log('Operation started', level: LogLevel.info);

    // Get the path to this example directory
    final scriptDir = Platform.script.toFilePath();
    final exampleDir = Directory(scriptDir).parent.path;

    // ─────────────────────────────────────────────────────────────────────
    // SCENARIO 1: File-based worker
    // ─────────────────────────────────────────────────────────────────────
    print('═══════════════════════════════════════════════════════════════════');
    print('SCENARIO 1: File-based Worker');
    print('═══════════════════════════════════════════════════════════════════\n');

    final fileResultPath = '${tempDir.path}/file_worker_result.json';
    await operation.log('Starting file-based worker', level: LogLevel.info);

    final fileCall = await operation.startCall(
      callback: CallCallback(
        onCleanup: () async {
          final file = File(fileResultPath);
          if (await file.exists()) {
            await file.delete();
            print('[Cleanup] Deleted result file');
            await operation.log('Cleanup: deleted result file', level: LogLevel.debug);
          }
        },
      ),
      description: 'File-based worker',
    );

    // Spawn the file worker process
    print('Spawning file_worker.dart...');
    final fileWorkerProcess = await Process.start(
      'dart',
      ['run', '$exampleDir/file_worker.dart', fileResultPath],
      workingDirectory: Directory.current.path,
    );

    // Log worker stdout/stderr
    fileWorkerProcess.stdout.transform(utf8.decoder).listen((line) {
      print('[FileWorker] $line');
    });
    fileWorkerProcess.stderr.transform(utf8.decoder).listen((line) {
      print('[FileWorker ERR] $line');
    });

    // Wait for result file using OperationHelper
    print('Waiting for result file...');
    final fileResult = await OperationHelper.pollFile<Map<String, dynamic>>(
      path: fileResultPath,
      delete: false, // Keep for inspection
      timeout: Duration(seconds: 30),
    )();

    await fileWorkerProcess.exitCode;

    print('\n📄 File Worker Result:');
    print('   Status: ${fileResult['status']}');
    print('   Value: ${fileResult['computed_value']}');
    print('   Timestamp: ${fileResult['timestamp']}');

    await operation.log('File worker completed: ${jsonEncode(fileResult)}', level: LogLevel.info);
    await fileCall.end();
    print('✅ File-based worker completed\n');

    // ─────────────────────────────────────────────────────────────────────
    // SCENARIO 2: Stdout-based worker
    // ─────────────────────────────────────────────────────────────────────
    print('═══════════════════════════════════════════════════════════════════');
    print('SCENARIO 2: Stdout-based Worker');
    print('═══════════════════════════════════════════════════════════════════\n');

    await operation.log('Starting stdout-based worker', level: LogLevel.info);

    final stdoutCall = await operation.startCall(
      callback: CallCallback(
        onCleanup: () async {
          print('[Cleanup] Stdout worker (no resources)');
        },
      ),
      description: 'Stdout-based worker',
    );

    // Spawn the stdout worker process
    print('Spawning stdout_worker.dart...');
    final stdoutWorkerProcess = await Process.start(
      'dart',
      ['run', '$exampleDir/stdout_worker.dart'],
      workingDirectory: Directory.current.path,
    );

    // Collect stdout
    final stdoutBuffer = StringBuffer();
    await for (final line in stdoutWorkerProcess.stdout.transform(utf8.decoder)) {
      stdoutBuffer.write(line);
    }

    await stdoutWorkerProcess.exitCode;

    final stdoutResult = jsonDecode(stdoutBuffer.toString()) as Map<String, dynamic>;

    print('\n📤 Stdout Worker Result:');
    print('   Result: ${stdoutResult['result']}');
    print('   Value: ${stdoutResult['value']}');
    print('   Worker: ${stdoutResult['worker']}');

    await operation.log('Stdout worker completed: ${jsonEncode(stdoutResult)}', level: LogLevel.info);
    await stdoutCall.end();
    print('✅ Stdout-based worker completed\n');

    // ─────────────────────────────────────────────────────────────────────
    // SCENARIO 3: Server-type process
    // ─────────────────────────────────────────────────────────────────────
    print('═══════════════════════════════════════════════════════════════════');
    print('SCENARIO 3: Server Process');
    print('═══════════════════════════════════════════════════════════════════\n');

    final serverResultPath = '${tempDir.path}/server_result.json';
    await operation.log('Starting server process', level: LogLevel.info);

    final serverCall = await operation.startCall(
      callback: CallCallback(
        onCleanup: () async {
          print('[Cleanup] Server process');
        },
      ),
      description: 'Server process',
      failOnCrash: false, // Server crash shouldn't fail entire operation
    );

    // Spawn the server process
    print('Spawning server_worker.dart...');
    final serverProcess = await Process.start(
      'dart',
      ['run', '$exampleDir/server_worker.dart', serverResultPath],
      workingDirectory: Directory.current.path,
    );

    // Log server output
    serverProcess.stdout.transform(utf8.decoder).listen((line) {
      print('[Server] $line');
    });
    serverProcess.stderr.transform(utf8.decoder).listen((line) {
      print('[Server ERR] $line');
    });

    // Wait for server result file
    print('Waiting for server to complete...');
    final serverResult = await OperationHelper.pollFile<Map<String, dynamic>>(
      path: serverResultPath,
      delete: false,
      timeout: Duration(seconds: 60),
    )();

    await serverProcess.exitCode;

    print('\n📊 Server Result:');
    print('   Requests handled: ${serverResult['requests_handled']}');
    print('   Total time: ${serverResult['total_time_ms']}ms');

    final requests = serverResult['request_results'] as List;
    for (final req in requests) {
      print('   - ${req['request_id']}: ${req['status']} (${req['delay_ms']}ms)');
    }

    await operation.log('Server completed: ${jsonEncode(serverResult)}', level: LogLevel.info);
    await serverCall.end();
    print('✅ Server process completed\n');

    // ─────────────────────────────────────────────────────────────────────
    // Complete the operation
    // ─────────────────────────────────────────────────────────────────────
    print('═══════════════════════════════════════════════════════════════════');
    print('Completing Operation');
    print('═══════════════════════════════════════════════════════════════════\n');

    await operation.log('All workers completed successfully', level: LogLevel.info);
    await operation.complete();
    print('✅ Operation completed successfully!\n');

    // Show logs
    print('📋 Operation Log:');
    final logFile = File('${tempDir.path}/${operation.operationId}.operation.log');
    if (logFile.existsSync()) {
      final logLines = logFile.readAsLinesSync();
      for (final line in logLines.take(20)) {
        print('   $line');
      }
      if (logLines.length > 20) {
        print('   ... (${logLines.length - 20} more lines)');
      }
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
