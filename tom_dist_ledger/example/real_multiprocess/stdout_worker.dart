/// Stdout-based Worker Process
///
/// This worker demonstrates stdout-based result communication:
/// 1. Receives parameters via command-line arguments
/// 2. Does some "work" with a significant delay (visible in heartbeat log)
/// 3. Returns the result via stdout (JSON format)
///
/// **CRITICAL**: All status messages go to stderr so stdout is ONLY the JSON result.
/// This is required for execStdioWorker() to correctly parse the result.
///
/// Expected arguments:
/// - `--param1=<value>` - First parameter
/// - `--param2=<value>` - Second parameter
/// - `--delay=<seconds>` - Optional delay in seconds (default: 5)
///
/// The result includes: combined_result = "$param1-$param2"
///
/// Run with: dart run example/real_multiprocess/stdout_worker.dart --param1=hello --param2=world
library;

import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  String param1 = 'default1';
  String param2 = 'default2';
  int delaySeconds = 5;
  
  // Parse named arguments
  for (final arg in args) {
    if (arg.startsWith('--param1=')) {
      param1 = arg.substring('--param1='.length);
    } else if (arg.startsWith('--param2=')) {
      param2 = arg.substring('--param2='.length);
    } else if (arg.startsWith('--delay=')) {
      delaySeconds = int.parse(arg.substring('--delay='.length));
    }
  }

  // All status messages go to stderr so stdout is clean JSON
  stderr.writeln('Starting stdout worker...');
  stderr.writeln('Parameters: param1=$param1, param2=$param2');
  stderr.writeln('Delay: ${delaySeconds}s');
  stderr.writeln('PID: $pid');

  // Simulate significant work with delay
  // This delay is long enough to see multiple heartbeat entries in debug.log
  stderr.writeln('Working for ${delaySeconds}s (check debug.log for heartbeats)...');
  await Future.delayed(Duration(seconds: delaySeconds));

  // Create result combining the parameters
  final result = {
    'status': 'success',
    'combined_result': '$param1-$param2',
    'param1': param1,
    'param2': param2,
    'delay_seconds': delaySeconds,
    'worker': 'stdout_worker',
    'pid': pid,
    'timestamp': DateTime.now().toIso8601String(),
  };

  // Only the result goes to stdout (as JSON)
  // This is critical for execStdioWorker to parse the result!
  stdout.write(jsonEncode(result));

  stderr.writeln('Done!');
}
