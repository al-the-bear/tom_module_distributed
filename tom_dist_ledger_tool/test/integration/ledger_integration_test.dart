/// Integration tests for the distributed ledger system.
///
/// These tests run against a locally running ledger server to verify
/// client-server interactions, retry behavior, and server restart resilience.
///
/// IMPORTANT: These are integration tests that require server processes.
/// They are designed to be run manually or in CI with proper setup.
/// Use `dart test test/integration/` to run only integration tests.
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_dist_ledger/tom_dist_ledger.dart';

/// Default ledger server port for tests.
const int kTestLedgerPort = 19890;

/// Test directory for ledger files.
late Directory _testDir;

/// The ledger server process.
Process? _serverProcess;

void main() {
  setUpAll(() async {
    _testDir = await Directory.systemTemp.createTemp('ledger_integration_test_');
    print('Test directory: ${_testDir.path}');
  });

  tearDownAll(() async {
    await _stopServer();
    try {
      await _testDir.delete(recursive: true);
    } catch (e) {
      print('Warning: Could not delete test directory: $e');
    }
  });

  group('Ledger Server Startup', () {
    test('server starts and responds to health check', () async {
      await _startServer();

      // Give server time to start
      await Future.delayed(const Duration(seconds: 2));

      // Check health endpoint
      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri.parse('http://localhost:$kTestLedgerPort/health'),
        );
        final response = await request.close();
        expect(response.statusCode, equals(200));
      } finally {
        client.close();
      }
    });
  });

  group('RemoteLedgerClient Basic Operations', () {
    late RemoteLedgerClient ledgerClient;

    setUp(() async {
      await _ensureServerRunning();
      ledgerClient = RemoteLedgerClient(
        serverUrl: 'http://localhost:$kTestLedgerPort',
        participantId: 'test_client_${DateTime.now().millisecondsSinceEpoch}',
      );
    });

    tearDown(() {
      ledgerClient.dispose();
    });

    test('client connects and creates operation', () async {
      final op = await ledgerClient.createOperation();
      expect(op, isNotNull);
      expect(op.operationId, isNotEmpty);
      await op.complete();
    });

    test('client creates and ends call with result', () async {
      final op = await ledgerClient.createOperation();

      final call = await op.startCall<int>();
      expect(call, isNotNull);
      expect(call.callId, isNotEmpty);

      await call.end(42);
      await op.complete();
    });

    test('client handles multiple sequential operations', () async {
      for (var i = 0; i < 5; i++) {
        final op = await ledgerClient.createOperation();
        final call = await op.startCall<String>();
        await call.end('result_$i');
        await op.complete();
      }
    });

    test('client logs messages during operation', () async {
      final op = await ledgerClient.createOperation();
      await op.log('Test log message');
      await op.log('Warning message', level: LogLevel.warning);
      await op.complete();
    });
  });

  group('Server Kill and Restart', () {
    late RemoteLedgerClient ledgerClient;

    setUp(() async {
      await _ensureServerRunning();
      ledgerClient = RemoteLedgerClient(
        serverUrl: 'http://localhost:$kTestLedgerPort',
        participantId: 'restart_test_${DateTime.now().millisecondsSinceEpoch}',
      );
    });

    tearDown(() {
      ledgerClient.dispose();
    });

    test('operation fails when server is killed', () async {
      final op = await ledgerClient.createOperation();
      final call = await op.startCall<int>();

      // Kill server
      await _stopServer();
      await Future.delayed(const Duration(milliseconds: 500));

      // Next operation should fail after retries
      expect(
        () async => await call.end(42),
        throwsA(isA<RetryExhaustedException>()),
      );
    }, timeout: Timeout(Duration(minutes: 2)));

    test('operations succeed after server restart', () async {
      // Start with working operation
      final op1 = await ledgerClient.createOperation();
      await op1.log('Before restart');
      await op1.complete();

      // Kill and restart server
      await _stopServer();
      await Future.delayed(const Duration(seconds: 1));
      await _startServer();
      await Future.delayed(const Duration(seconds: 2));

      // New operation should work
      final op2 = await ledgerClient.createOperation();
      await op2.log('After restart');
      await op2.complete();
    });

    test('client retries during brief server unavailability', () async {
      final op = await ledgerClient.createOperation();

      // Kill server briefly
      await _stopServer();

      // Start retry in background (will wait ~2s for first retry)
      final logFuture = op.log('During restart');

      // Restart server within retry window
      await Future.delayed(const Duration(milliseconds: 1500));
      await _startServer();
      await Future.delayed(const Duration(seconds: 1));

      // Log should eventually succeed
      await logFuture;
      await op.complete();
    }, timeout: Timeout(Duration(minutes: 2)));
  });

  group('Concurrent Client Operations', () {
    test('multiple clients can operate concurrently', () async {
      await _ensureServerRunning();

      final clients = List.generate(
        3,
        (i) => RemoteLedgerClient(
          serverUrl: 'http://localhost:$kTestLedgerPort',
          participantId: 'concurrent_client_$i',
        ),
      );

      try {
        // All clients create operations simultaneously
        final operations = await Future.wait(
          clients.map((c) => c.createOperation()),
        );

        // All log simultaneously
        await Future.wait(
          operations.map((op) => op.log('Concurrent log')),
        );

        // All complete
        await Future.wait(
          operations.map((op) => op.complete()),
        );
      } finally {
        for (final client in clients) {
          client.dispose();
        }
      }
    });
  });
}

/// Starts the ledger server using dart run.
Future<void> _startServer() async {
  if (_serverProcess != null) {
    return; // Already running
  }

  final toolDir = Directory.current.path.endsWith('tom_dist_ledger_tool')
      ? Directory.current.path
      : '${Directory.current.path}/xternal/tom_module_distributed/tom_dist_ledger_tool';

  _serverProcess = await Process.start(
    'dart',
    [
      'run',
      'bin/ledger_server.dart',
      '--port=$kTestLedgerPort',
      '--path=${_testDir.path}',
    ],
    workingDirectory: toolDir,
    environment: Platform.environment,
  );

  // Forward output for debugging
  _serverProcess!.stdout.transform(utf8.decoder).listen(
        (data) => print('[Server] $data'),
      );
  _serverProcess!.stderr.transform(utf8.decoder).listen(
        (data) => print('[Server Error] $data'),
      );

  print('Started ledger server with PID: ${_serverProcess!.pid}');
}

/// Stops the ledger server.
Future<void> _stopServer() async {
  if (_serverProcess != null) {
    print('Stopping ledger server (PID: ${_serverProcess!.pid})');
    _serverProcess!.kill(ProcessSignal.sigterm);
    await _serverProcess!.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _serverProcess!.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    _serverProcess = null;
  }
}

/// Ensures server is running.
Future<void> _ensureServerRunning() async {
  if (_serverProcess == null) {
    await _startServer();
    // Wait for server to be ready
    await Future.delayed(const Duration(seconds: 2));
  }
}
