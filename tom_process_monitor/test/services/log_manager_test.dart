import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:tom_process_monitor/src/services/log_manager.dart';

void main() {
  group('LogManager', () {
    late String tempDir;
    late LogManager logManager;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('log_manager_test_').path;
      logManager = LogManager(
        baseDirectory: tempDir,
        instanceId: 'test',
        maxLogFiles: 3,
      );
    });

    tearDown(() async {
      await logManager.close();
      final dir = Directory(tempDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('initialize creates log directory and file', () async {
      await logManager.initialize();

      final logDir = Directory(path.join(tempDir, 'test_logs'));
      expect(await logDir.exists(), isTrue);

      final files = await logDir.list().toList();
      expect(files, isNotEmpty);
      expect(files.first.path, endsWith('.log'));
    });

    test('log writes messages to file', () async {
      await logManager.initialize();

      logManager.info('Test info message');
      logManager.warn('Test warning');
      logManager.error('Test error');

      await logManager.close();

      final logDir = Directory(path.join(tempDir, 'test_logs'));
      final files = await logDir.list().toList();
      final logFile = files.whereType<File>().first;
      final content = await logFile.readAsString();

      expect(content, contains('[INFO] Test info message'));
      expect(content, contains('[WARN] Test warning'));
      expect(content, contains('[ERROR] Test error'));
    });

    test('log includes timestamp', () async {
      await logManager.initialize();

      logManager.info('Timestamped message');
      await logManager.close();

      final logDir = Directory(path.join(tempDir, 'test_logs'));
      final files = await logDir.list().toList();
      final logFile = files.whereType<File>().first;
      final content = await logFile.readAsString();

      // Should contain ISO8601 timestamp pattern
      expect(content, matches(RegExp(r'\[\d{4}-\d{2}-\d{2}T')));
    });

    test('getProcessLogDir returns correct path', () {
      final processLogDir = logManager.getProcessLogDir('my-process');

      expect(processLogDir, contains('test_logs'));
      expect(processLogDir, contains('my-process'));
    });

    test('cleanupProcessLogs removes old directories', () async {
      await logManager.initialize();

      // Create more than maxLogFiles process log directories
      final processLogBase = path.join(tempDir, 'test_logs', 'my-process');
      await Directory(processLogBase).create(recursive: true);

      for (var i = 0; i < 5; i++) {
        final timestamp = '2026012${i}_100000';
        final dir = Directory(path.join(processLogBase, timestamp));
        await dir.create();
        // Add a small delay to ensure different creation times
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      // Verify we have 5 directories
      var dirs = await Directory(processLogBase).list().toList();
      expect(dirs.length, equals(5));

      // Run cleanup
      await logManager.cleanupProcessLogs('my-process');

      // Should now have at most maxLogFiles (3)
      dirs = await Directory(processLogBase).list().toList();
      expect(dirs.length, equals(3));
    });

    test('cleanup retains newest log files', () async {
      await logManager.initialize();

      final logDir = path.join(tempDir, 'test_logs');

      // Create additional log files (simulating multiple starts)
      for (var i = 0; i < 4; i++) {
        final timestamp = '2026012${i}_10000$i';
        final file = File(path.join(logDir, '${timestamp}_test.log'));
        await file.writeAsString('Log $i');
      }

      // Reinitialize (should trigger cleanup)
      await logManager.close();
      logManager = LogManager(
        baseDirectory: tempDir,
        instanceId: 'test',
        maxLogFiles: 3,
      );
      await logManager.initialize();
      await logManager.close();

      // Should have at most maxLogFiles
      final files = await Directory(logDir)
          .list()
          .where((e) => e is File && e.path.endsWith('.log'))
          .toList();
      expect(files.length, lessThanOrEqualTo(3));
    });

    test('close flushes and closes log sink', () async {
      await logManager.initialize();

      logManager.info('Before close');
      await logManager.close();

      // Logging after close should not throw
      logManager.info('After close');

      // Verify the message before close was written
      final logDir = Directory(path.join(tempDir, 'test_logs'));
      final files = await logDir.list().toList();
      final logFile = files.whereType<File>().first;
      final content = await logFile.readAsString();

      expect(content, contains('Before close'));
    });
  });
}
