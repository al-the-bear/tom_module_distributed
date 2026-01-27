/// Integration tests for the process monitor system.
///
/// These tests run against a locally running process monitor to verify
/// client-server interactions, retry behavior, and monitor restart resilience.
///
/// IMPORTANT: These are integration tests that require process monitor daemon.
/// They are designed to be run manually or in CI with proper setup.
///
/// Before running tests, ensure no process_monitor is running on default ports:
///   lsof -i :19881
///   lsof -i :19883
///
/// Use `dart test test/integration/` to run only integration tests.
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_process_monitor/tom_process_monitor.dart';

/// Test port for process monitor HTTP API (uses default).
const int kTestApiPort = 19881;

/// Test port for process monitor aliveness (uses default).
const int kTestAlivenessPort = 19883;

/// Test directory for process monitor files.
late Directory _testDir;

/// The process monitor daemon process.
Process? _monitorProcess;

/// Whether to skip tests due to port conflicts.
bool _skipDueToPortConflict = false;

/// Helper to skip a test if ports are in use.
/// Returns true if the test should be skipped.
bool _skipIfPortConflict() {
  if (_skipDueToPortConflict) {
    markTestSkipped('Ports in use by running monitor - stop it first to run full tests');
    return true;
  }
  return false;
}

void main() {
  setUpAll(() async {
    _testDir = await Directory.systemTemp.createTemp('monitor_integration_test_');
    print('Test directory: ${_testDir.path}');

    // Check if ports are already in use
    final apiInUse = await _isPortInUse(kTestApiPort);
    final alivenessInUse = await _isPortInUse(kTestAlivenessPort);
    if (apiInUse || alivenessInUse) {
      print(
        'WARNING: Ports already in use. Skipping tests that require starting a new monitor.\n'
        'API port $kTestApiPort in use: $apiInUse\n'
        'Aliveness port $kTestAlivenessPort in use: $alivenessInUse\n'
        'To run full tests, stop the running process_monitor first.',
      );
      _skipDueToPortConflict = true;
    }
  });

  tearDownAll(() async {
    await _stopMonitor();
    try {
      await _testDir.delete(recursive: true);
    } catch (e) {
      print('Warning: Could not delete test directory: $e');
    }
  });

  group('Process Monitor Startup', () {
    test('monitor starts and responds to status request', () async {
      if (_skipIfPortConflict()) return;
      await _startMonitor();

      // Give monitor time to start
      await Future.delayed(const Duration(seconds: 3));

      // Check status endpoint
      final client = RemoteProcessMonitorClient(
        baseUrl: 'http://localhost:$kTestApiPort',
      );
      try {
        final status = await client.getMonitorStatus();
        expect(status, isNotNull);
        expect(status.instanceId, equals('default'));
      } finally {
        client.dispose();
      }
    });
  });

  group('RemoteProcessMonitorClient Basic Operations', () {
    RemoteProcessMonitorClient? monitorClient;

    setUp(() async {
      if (_skipDueToPortConflict) return;
      await _ensureMonitorRunning();
      monitorClient = RemoteProcessMonitorClient(
        baseUrl: 'http://localhost:$kTestApiPort',
      );
    });

    tearDown(() {
      monitorClient?.dispose();
    });

    test('client gets monitor status', () async {
      if (_skipIfPortConflict()) return;
      final status = await monitorClient!.getMonitorStatus();
      expect(status, isNotNull);
      expect(status.instanceId, equals('default'));
    });

    test('client gets all process status (empty initially)', () async {
      if (_skipIfPortConflict()) return;
      final statuses = await monitorClient!.getAllStatus();
      expect(statuses, isA<Map<String, ProcessStatus>>());
    });

    test('client registers and deregisters a process', () async {
      if (_skipIfPortConflict()) return;
      final config = ProcessConfig(
        id: 'test_process_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Test Process',
        command: '/bin/echo',
        args: ['hello'],
        autostart: false,
      );

      // Register
      await monitorClient!.register(config);

      // Verify registered
      final statuses = await monitorClient!.getAllStatus();
      expect(statuses.containsKey(config.id), isTrue);

      // Deregister
      await monitorClient!.deregister(config.id);

      // Verify deregistered
      final statusesAfter = await monitorClient!.getAllStatus();
      expect(statusesAfter.containsKey(config.id), isFalse);
    });

    test('client starts and stops a process', () async {
      if (_skipIfPortConflict()) return;
      final processId = 'sleep_process_${DateTime.now().millisecondsSinceEpoch}';
      final config = ProcessConfig(
        id: processId,
        name: 'Sleep Process',
        command: '/bin/sleep',
        args: ['30'],
        autostart: false,
      );

      try {
        // Register and start
        await monitorClient!.register(config);
        await monitorClient!.start(processId);

        // Wait for process to start
        await Future.delayed(const Duration(seconds: 1));

        // Check status
        final status = await monitorClient!.getStatus(processId);
        expect(status.state, equals(ProcessState.running));

        // Stop
        await monitorClient!.stop(processId);
        await Future.delayed(const Duration(milliseconds: 500));

        // Check stopped
        final stoppedStatus = await monitorClient!.getStatus(processId);
        expect(stoppedStatus.state, equals(ProcessState.stopped));
      } finally {
        // Cleanup
        try {
          await monitorClient!.deregister(processId);
        } catch (_) {
          // Ignore cleanup errors
        }
      }
    });

    test('client enables and disables a process', () async {
      if (_skipIfPortConflict()) return;
      final processId = 'toggle_process_${DateTime.now().millisecondsSinceEpoch}';
      final config = ProcessConfig(
        id: processId,
        name: 'Toggle Process',
        command: '/bin/echo',
        args: ['test'],
        autostart: false,
      );

      try {
        await monitorClient!.register(config);

        // Disable
        await monitorClient!.disable(processId);
        var status = await monitorClient!.getStatus(processId);
        expect(status.state, equals(ProcessState.disabled));

        // Enable
        await monitorClient!.enable(processId);
        status = await monitorClient!.getStatus(processId);
        expect(status.state, isNot(equals(ProcessState.disabled)));
      } finally {
        try {
          await monitorClient!.deregister(processId);
        } catch (_) {}
      }
    });
  });

  group('Monitor Kill and Restart', () {
    RemoteProcessMonitorClient? monitorClient;

    setUp(() async {
      if (_skipDueToPortConflict) return;
      await _ensureMonitorRunning();
      monitorClient = RemoteProcessMonitorClient(
        baseUrl: 'http://localhost:$kTestApiPort',
      );
    });

    tearDown(() {
      monitorClient?.dispose();
    });

    test('operation fails when monitor is killed', () async {
      if (_skipIfPortConflict()) return;
      // Verify working first
      await monitorClient!.getMonitorStatus();

      // Kill monitor
      await _stopMonitor();
      await Future.delayed(const Duration(milliseconds: 500));

      // Next operation should fail after retries
      expect(
        () async => await monitorClient!.getMonitorStatus(),
        throwsA(isA<RetryExhaustedException>()),
      );
    },
        timeout: Timeout(Duration(minutes: 2)),
        skip: 'Long-running test (~62s) - run manually');

    test('operations succeed after monitor restart', () async {
      if (_skipIfPortConflict()) return;
      // Start with working status
      await monitorClient!.getMonitorStatus();

      // Kill and restart monitor
      await _stopMonitor();
      await Future.delayed(const Duration(seconds: 1));
      await _startMonitor();
      await Future.delayed(const Duration(seconds: 3));

      // New status should work
      final status = await monitorClient!.getMonitorStatus();
      expect(status, isNotNull);
    });

    test('client retries during brief monitor unavailability', () async {
      if (_skipIfPortConflict()) return;
      // Verify working
      await monitorClient!.getMonitorStatus();

      // Kill monitor briefly
      await _stopMonitor();

      // Start retry in background (will wait ~2s for first retry)
      final statusFuture = monitorClient!.getMonitorStatus();

      // Restart monitor within retry window
      await Future.delayed(const Duration(milliseconds: 1500));
      await _startMonitor();
      await Future.delayed(const Duration(seconds: 2));

      // Status should eventually succeed
      final status = await statusFuture;
      expect(status, isNotNull);
    },
        timeout: Timeout(Duration(minutes: 2)),
        skip: 'Long-running test - run manually');
  });

  group('Process State Persistence', () {
    test('process registration persists across monitor restart', () async {
      if (_skipIfPortConflict()) return;
      await _ensureMonitorRunning();

      final processId = 'persist_test_${DateTime.now().millisecondsSinceEpoch}';
      final client = RemoteProcessMonitorClient(
        baseUrl: 'http://localhost:$kTestApiPort',
      );

      try {
        // Register a process
        final config = ProcessConfig(
          id: processId,
          name: 'Persist Test',
          command: '/bin/echo',
          args: ['persisted'],
          autostart: false,
        );
        await client.register(config);

        // Verify registered
        var statuses = await client.getAllStatus();
        expect(statuses.containsKey(processId), isTrue);

        // Restart monitor
        await _stopMonitor();
        await Future.delayed(const Duration(seconds: 1));
        await _startMonitor();
        await Future.delayed(const Duration(seconds: 3));

        // Process should still be registered
        statuses = await client.getAllStatus();
        expect(statuses.containsKey(processId), isTrue);
      } finally {
        // Cleanup
        try {
          await client.deregister(processId);
        } catch (_) {}
        client.dispose();
      }
    });
  });

  group('Watcher Kill Scenario', () {
    test('process monitor detects watcher absence and attempts restart', () async {
      // This test would require starting both process_monitor and monitor_watcher
      // and then killing the watcher to verify the mutual monitoring works.
      // For now, this is a placeholder for manual testing.
      // TODO: Implement full watcher kill test
    }, skip: 'Requires manual testing with both processes');
  });
}

/// Starts the process monitor daemon using dart run.
Future<void> _startMonitor() async {
  if (_monitorProcess != null) {
    return; // Already running
  }

  final toolDir = Directory.current.path.endsWith('tom_process_monitor_tool')
      ? Directory.current.path
      : '${Directory.current.path}/xternal/tom_module_distributed/tom_process_monitor_tool';

  _monitorProcess = await Process.start(
    'dart',
    [
      'run',
      'bin/process_monitor.dart',
      '--foreground',
      '--directory=${_testDir.path}',
    ],
    workingDirectory: toolDir,
    environment: Platform.environment,
  );

  // Forward output for debugging
  _monitorProcess!.stdout.transform(utf8.decoder).listen(
        (data) => print('[Monitor] $data'),
      );
  _monitorProcess!.stderr.transform(utf8.decoder).listen(
        (data) => print('[Monitor Error] $data'),
      );

  print('Started process monitor with PID: ${_monitorProcess!.pid}');
}

/// Stops the process monitor daemon.
Future<void> _stopMonitor() async {
  if (_monitorProcess != null) {
    print('Stopping process monitor (PID: ${_monitorProcess!.pid})');
    _monitorProcess!.kill(ProcessSignal.sigterm);
    await _monitorProcess!.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _monitorProcess!.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    _monitorProcess = null;
  }
}

/// Ensures process monitor is running.
Future<void> _ensureMonitorRunning() async {
  if (_monitorProcess == null) {
    await _startMonitor();
    // Wait for monitor to be ready
    await Future.delayed(const Duration(seconds: 3));
  }
}

/// Checks if a port is already in use.
Future<bool> _isPortInUse(int port) async {
  try {
    final socket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    await socket.close();
    return false;
  } on SocketException {
    return true;
  }
}
