/// Tests for server discovery and spawned server connections.
///
/// These tests spawn a real LedgerServer process and test:
/// - Auto-discovery of servers
/// - Connection to servers on custom ports
/// - Full operation lifecycle through the server
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_dist_ledger/tom_dist_ledger.dart';

void main() {
  group('Server Discovery', () {
    late Directory tempDir;
    late LedgerServer server;
    late int serverPort;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('discovery_test_');
      // Start server on a random available port
      server = await LedgerServer.start(
        basePath: tempDir.path,
        port: 0, // OS assigns port
      );
      serverPort = server.port;
    });

    tearDownAll(() async {
      await server.stop();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('/status endpoint returns server info', () async {
      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri.parse('http://localhost:$serverPort/status'),
        );
        final response = await request.close();
        expect(response.statusCode, equals(200));

        final body = await response.transform(const SystemEncoding().decoder).join();
        expect(body, contains('tom_dist_ledger'));
        expect(body, contains('status'));
        expect(body, contains('ok'));
      } finally {
        client.close();
      }
    });

    test('ServerDiscovery.discover finds running server', () async {
      final discovered = await ServerDiscovery.discover(
        DiscoveryOptions(
          port: serverPort,
          timeout: const Duration(seconds: 1),
          scanSubnet: false, // Only scan localhost for test speed
        ),
      );

      expect(discovered, isNotNull);
      expect(discovered!.serverUrl, contains('$serverPort'));
      expect(discovered.service, equals('tom_dist_ledger'));
    });

    test('ServerDiscovery.discoverAll finds all servers', () async {
      final discovered = await ServerDiscovery.discoverAll(
        DiscoveryOptions(
          port: serverPort,
          timeout: const Duration(seconds: 1),
          scanSubnet: false,
        ),
      );

      expect(discovered, isNotEmpty);
      expect(discovered.first.service, equals('tom_dist_ledger'));
    });

    test('RemoteLedgerClient.connect with auto-discovery connects to server', () async {
      // ignore: deprecated_member_use_from_same_package
      final client = await RemoteLedgerClient.connect(
        participantId: 'discovery_test_client',
        port: serverPort,
        scanSubnet: false,
        timeout: const Duration(seconds: 1),
      );

      expect(client, isNotNull);
      expect(client!.serverUrl, contains('$serverPort'));

      // Test that we can create an operation
      final op = await client.createOperation();
      expect(op.operationId, isNotEmpty);

      await op.complete();
      client.dispose();
    });

    test('RemoteLedgerClient.connect with explicit serverUrl connects directly', () async {
      final client = await RemoteLedgerClient.connect(
        participantId: 'direct_connect_client',
        serverUrl: 'http://localhost:$serverPort',
        timeout: const Duration(seconds: 1),
      );

      expect(client, isNotNull);
      expect(client!.serverUrl, equals('http://localhost:$serverPort'));

      final op = await client.createOperation();
      expect(op.operationId, isNotEmpty);

      await op.complete();
      client.dispose();
    });
  });

  group('Spawned Server Connection', () {
    late Directory tempDir;
    late LedgerServer server;
    late int serverPort;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('spawned_server_test_');
      server = await LedgerServer.start(
        basePath: tempDir.path,
        port: 0,
      );
      serverPort = server.port;
    });

    tearDownAll(() async {
      await server.stop();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('client connects to server on custom port', () async {
      final client = RemoteLedgerClient(
        serverUrl: 'http://localhost:$serverPort',
        participantId: 'custom_port_client',
      );

      // Verify connection by creating an operation
      final op = await client.createOperation();
      expect(op, isNotNull);
      expect(op.operationId, isNotEmpty);

      await op.complete();
      client.dispose();
    });

    test('full operation lifecycle through server', () async {
      final client = RemoteLedgerClient(
        serverUrl: 'http://localhost:$serverPort',
        participantId: 'lifecycle_client',
      );

      // Create operation
      final op = await client.createOperation();
      expect(op.isInitiator, isTrue);

      // Start a call
      final call = await op.startCall<String>();
      expect(call.callId, isNotEmpty);

      // End the call with a result
      await call.end('test_result');
      expect(call.isCompleted, isTrue);

      // Complete the operation
      await op.complete();

      client.dispose();
    });

    test('spawned call works through server', () async {
      final client = RemoteLedgerClient(
        serverUrl: 'http://localhost:$serverPort',
        participantId: 'spawn_client',
      );

      final op = await client.createOperation();

      // Spawn a call with work
      final spawned = op.spawnCall<int>(
        work: (call, operation) async {
          await Future.delayed(const Duration(milliseconds: 50));
          return 42;
        },
      );

      expect(spawned.callId, isNotEmpty);

      // Wait for completion
      await spawned.future;
      expect(spawned.isSuccess, isTrue);
      expect(spawned.result, equals(42));

      await op.complete();
      client.dispose();
    });

    test('multiple clients can connect to same server', () async {
      final client1 = RemoteLedgerClient(
        serverUrl: 'http://localhost:$serverPort',
        participantId: 'multi_client_1',
      );
      final client2 = RemoteLedgerClient(
        serverUrl: 'http://localhost:$serverPort',
        participantId: 'multi_client_2',
      );

      // Client 1 creates operation
      final op1 = await client1.createOperation();

      // Client 2 joins the operation
      final op2 = await client2.joinOperation(operationId: op1.operationId);

      expect(op2.operationId, equals(op1.operationId));
      expect(op2.isInitiator, isFalse);

      // Both do work
      final call1 = await op1.startCall<int>();
      final call2 = await op2.startCall<int>();

      await call1.end(1);
      await call2.end(2);

      // Client 2 leaves
      op2.leave();

      // Client 1 completes
      await op1.complete();

      client1.dispose();
      client2.dispose();
    });

    test('heartbeat works through server', () async {
      final client = RemoteLedgerClient(
        serverUrl: 'http://localhost:$serverPort',
        participantId: 'heartbeat_client',
        heartbeatInterval: const Duration(milliseconds: 200),
      );

      final op = await client.createOperation();

      // Wait for a few heartbeats
      await Future.delayed(const Duration(milliseconds: 500));

      // Operation should still be healthy
      final isAborted = await op.checkAbort();
      expect(isAborted, isFalse);

      await op.complete();
      client.dispose();
    });
  });

  group('Discovery Edge Cases', () {
    test('connect returns null when no server running', () async {
      // Use a port that's unlikely to have a server
      final client = await RemoteLedgerClient.connect(
        participantId: 'no_server_client',
        port: 59999,
        scanSubnet: false,
        timeout: const Duration(milliseconds: 100),
      );

      expect(client, isNull);
    });

    test('connect with invalid serverUrl returns null', () async {
      final client = await RemoteLedgerClient.connect(
        participantId: 'invalid_url_client',
        serverUrl: 'http://localhost:59999',
        timeout: const Duration(milliseconds: 100),
      );

      expect(client, isNull);
    });

    test('connect with logger logs progress', () async {
      final logs = <String>[];

      await RemoteLedgerClient.connect(
        participantId: 'logging_client',
        port: 59999,
        scanSubnet: false,
        timeout: const Duration(milliseconds: 100),
        logger: logs.add,
      );

      expect(logs, isNotEmpty);
      expect(logs.any((l) => l.contains('Trying')), isTrue);
    });
  });
}
