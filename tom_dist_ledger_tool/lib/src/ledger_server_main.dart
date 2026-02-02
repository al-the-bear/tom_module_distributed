/// Distributed Ledger Server CLI entry point.
library;

import 'dart:async';
import 'dart:io';

import 'package:tom_dist_ledger/tom_dist_ledger.dart';

/// Main entry point for ledger server CLI.
Future<void> ledgerServerMain(List<String> arguments) async {
  // Parse command line arguments
  final port = _parsePort(arguments);
  final basePath = _parseBasePath(arguments);

  if (arguments.contains('--help') || arguments.contains('-h')) {
    printLedgerServerUsage();
    return;
  }

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

/// Parse port from arguments, defaults to 19880.
int _parsePort(List<String> arguments) {
  for (final arg in arguments) {
    if (arg.startsWith('--port=')) {
      return int.tryParse(arg.substring(7)) ?? 19880;
    }
    if (arg == '--port' || arg == '-p') {
      final index = arguments.indexOf(arg);
      if (index + 1 < arguments.length) {
        return int.tryParse(arguments[index + 1]) ?? 19880;
      }
    }
  }
  return 19880;
}

/// Parse base path from arguments, defaults to ~/.tom/distributed_ledger.
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
  return _getDefaultLedgerPath();
}

/// Returns the default ledger storage path: ~/.tom/distributed_ledger
String _getDefaultLedgerPath() {
  final home = Platform.environment['HOME'] ?? 
               Platform.environment['USERPROFILE'] ?? 
               Directory.current.path;
  return '$home/.tom/distributed_ledger';
}

/// Prints usage information.
void printLedgerServerUsage() {
  print('''
Distributed Ledger Server

Usage:
  ledger_server [options]

Options:
  --port=<port>    Port to listen on (default: 19880)
  -p <port>        Port to listen on
  --path=<path>    Base path for ledger storage (default: ~/.tom/distributed_ledger)
  -d <path>        Base path for ledger storage
  -h, --help       Show this help message
''');
}
