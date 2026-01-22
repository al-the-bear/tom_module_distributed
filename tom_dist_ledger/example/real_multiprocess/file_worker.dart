/// File-based Worker Process
///
/// This worker demonstrates file-based result communication:
/// 1. Receives an output file path and parameters via command-line arguments
/// 2. Does some "work" with a significant delay (visible in heartbeat log)
/// 3. Writes the result (based on parameters) to the specified file
///
/// Expected arguments:
/// - `<output_path>` - Path to write the result JSON
/// - `--param1=<value>` - First parameter
/// - `--param2=<value>` - Second parameter
/// - `--delay=<seconds>` - Optional delay in seconds (default: 5)
///
/// The result includes: combined_result = "$param1-$param2"
///
/// Run with: dart run example/real_multiprocess/file_worker.dart /tmp/result.json --param1=hello --param2=world
library;

import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run file_worker.dart <output_path> --param1=<value> --param2=<value> [--delay=<seconds>]');
    exit(1);
  }

  final outputPath = args[0];
  String param1 = 'default1';
  String param2 = 'default2';
  int delaySeconds = 5;
  
  // Parse named arguments
  for (final arg in args.skip(1)) {
    if (arg.startsWith('--param1=')) {
      param1 = arg.substring('--param1='.length);
    } else if (arg.startsWith('--param2=')) {
      param2 = arg.substring('--param2='.length);
    } else if (arg.startsWith('--delay=')) {
      delaySeconds = int.parse(arg.substring('--delay='.length));
    }
  }

  print('Starting file worker...');
  print('Output path: $outputPath');
  print('Parameters: param1=$param1, param2=$param2');
  print('Delay: ${delaySeconds}s');
  print('PID: $pid');

  // Simulate significant work with delay
  // This delay is long enough to see multiple heartbeat entries in debug.log
  print('Working for ${delaySeconds}s (check debug.log for heartbeats)...');
  await Future.delayed(Duration(seconds: delaySeconds));

  // Create result combining the parameters
  final result = {
    'status': 'success',
    'combined_result': '$param1-$param2',
    'param1': param1,
    'param2': param2,
    'delay_seconds': delaySeconds,
    'worker': 'file_worker',
    'pid': pid,
    'timestamp': DateTime.now().toIso8601String(),
  };

  // Write result to file
  print('Writing result to file...');
  final file = File(outputPath);
  await file.writeAsString(jsonEncode(result));

  print('Done! Result written to: $outputPath');
}
