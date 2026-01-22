/// File-based Worker Process
///
/// This worker:
/// 1. Receives an output file path as argument
/// 2. Does some "work" (simulated with a delay)
/// 3. Writes the result to the specified file
///
/// Run with: dart run example/real_multiprocess/file_worker.dart `<output_path>`
library;

import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run file_worker.dart <output_path>');
    exit(1);
  }

  final outputPath = args[0];
  print('Starting file worker...');
  print('Output path: $outputPath');

  // Simulate work
  print('Working...');
  await Future.delayed(Duration(seconds: 2));

  // Create result
  final result = {
    'status': 'success',
    'computed_value': 42,
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
