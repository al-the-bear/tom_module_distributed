/// Stdout-based Worker Process
///
/// This worker:
/// 1. Does some "work" (simulated with a delay)
/// 2. Returns the result via stdout (JSON format)
///
/// Run with: dart run example/real_multiprocess/stdout_worker.dart
library;

import 'dart:convert';
import 'dart:io';

void main() async {
  // All status messages go to stderr so stdout is clean JSON
  stderr.writeln('Starting stdout worker...');
  stderr.writeln('PID: $pid');

  // Simulate work
  stderr.writeln('Working...');
  await Future.delayed(Duration(milliseconds: 500));

  // Create result and output to stdout
  final result = {
    'result': 'computation_complete',
    'value': 123.45,
    'worker': 'stdout_worker',
    'pid': pid,
    'timestamp': DateTime.now().toIso8601String(),
  };

  // Only the result goes to stdout
  stdout.write(jsonEncode(result));

  stderr.writeln('Done!');
}
