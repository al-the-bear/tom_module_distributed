/// Socket Server Worker Process
///
/// This worker demonstrates a true socket server that:
/// 1. Binds to a port and listens for connections
/// 2. Receives request data from the orchestrator
/// 3. Executes work with a significant delay (visible in heartbeat log)
/// 4. Returns the result via the socket connection
///
/// The orchestrator passes:
/// - `--port=<port>` - The port to bind to
/// - `--ledger-path=<path>` - Optional ledger path for joining the operation
/// - `--operation-id=<id>` - Optional operation ID to join
///
/// Run with: dart run example/real_multiprocess/server_worker.dart --port=19876
library;

import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  // Parse arguments
  int? port;
  String? ledgerPath;
  String? operationId;
  
  for (final arg in args) {
    if (arg.startsWith('--port=')) {
      port = int.parse(arg.substring('--port='.length));
    } else if (arg.startsWith('--ledger-path=')) {
      ledgerPath = arg.substring('--ledger-path='.length);
    } else if (arg.startsWith('--operation-id=')) {
      operationId = arg.substring('--operation-id='.length);
    }
  }

  if (port == null) {
    stderr.writeln('Usage: dart run server_worker.dart --port=<port> [--ledger-path=<path>] [--operation-id=<id>]');
    exit(1);
  }

  print('Server worker starting on port $port...');
  print('PID: $pid');
  if (ledgerPath != null) print('Ledger path: $ledgerPath');
  if (operationId != null) print('Operation ID: $operationId');

  // Bind to the port
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
  print('Server listening on port $port');

  try {
    // Wait for a single connection from the orchestrator
    await for (final socket in server) {
      print('Client connected from ${socket.remoteAddress.address}:${socket.remotePort}');
      
      // Read the request
      final requestBuffer = StringBuffer();
      await for (final data in socket) {
        requestBuffer.write(utf8.decode(data));
        // Look for end-of-request marker
        if (requestBuffer.toString().contains('\n')) {
          break;
        }
      }

      final requestJson = requestBuffer.toString().trim();
      print('Received request: $requestJson');
      
      Map<String, dynamic> request;
      try {
        request = json.decode(requestJson) as Map<String, dynamic>;
      } catch (e) {
        print('Error parsing request: $e');
        socket.write(json.encode({'error': 'Invalid JSON: $e'}));
        await socket.close();
        continue;
      }

      // Extract parameters from the request
      final param1 = request['param1'] as String? ?? 'default1';
      final param2 = request['param2'] as String? ?? 'default2';
      final delaySeconds = request['delay_seconds'] as int? ?? 5;

      print('Processing request with params: $param1, $param2');
      print('Simulating work with ${delaySeconds}s delay (check debug.log for heartbeats)...');

      // Simulate significant work with delay
      // This delay is long enough to see multiple heartbeat entries in debug.log
      await Future.delayed(Duration(seconds: delaySeconds));

      // Create the result combining the parameters
      final result = {
        'status': 'success',
        'combined_result': '$param1-$param2',
        'param1': param1,
        'param2': param2,
        'delay_seconds': delaySeconds,
        'worker': 'server_worker',
        'pid': pid,
        'port': port,
        'timestamp': DateTime.now().toIso8601String(),
      };

      print('Sending result: ${json.encode(result)}');
      socket.write(json.encode(result));
      await socket.flush();
      await socket.close();
      
      // Only handle one request then shutdown
      print('Request completed, shutting down server');
      break;
    }
  } finally {
    await server.close();
    print('Server shutdown complete');
  }
}

