import 'dart:async';
import 'dart:io';

import 'package:tom_dist_ledger/tom_dist_ledger.dart';

/// Distributed Ledger HTTP Server
///
/// Runs an HTTP server that exposes the ledger API for remote clients.
/// Each request contains a participantId and the server uses LocalLedger
/// to process requests statelessly.
void main(List<String> arguments) async {
  // Parse command line arguments
  final port = _parsePort(arguments);
  final basePath = _parseBasePath(arguments);

  print('Starting Distributed Ledger Server...');
  print('  Port: $port');
  print('  Base path: $basePath');

  // Create the server
  final server = await LedgerServer.start(
    basePath: basePath,
    port: port,
  );

  print('Server listening on http://localhost:$port');
  print('Press Ctrl+C to stop.');

  // Handle shutdown
  ProcessSignal.sigint.watch().listen((_) async {
    print('\nShutting down...');
    await server.stop();
    exit(0);
  });

  // Keep running
  await Completer<void>().future;
}

/// Parse port from arguments, defaults to 19876.
int _parsePort(List<String> arguments) {
  for (final arg in arguments) {
    if (arg.startsWith('--port=')) {
      return int.tryParse(arg.substring(7)) ?? 19876;
    }
    if (arg == '--port' || arg == '-p') {
      final index = arguments.indexOf(arg);
      if (index + 1 < arguments.length) {
        return int.tryParse(arguments[index + 1]) ?? 19876;
      }
    }
  }
  return 19876;
}

/// Parse base path from arguments, defaults to current directory.
String _parseBasePath(List<String> arguments) {
  for (final arg in arguments) {
    if (arg.startsWith('--path=')) {
      return arg.substring(7);
    }
    if (arg == '--path' || arg == '-d') {
      final index = arguments.indexOf(arg);
      if (index + 1 < arguments.length) {
        return arguments[index + 1];
      }
    }
  }
  return Directory.current.path;
}
