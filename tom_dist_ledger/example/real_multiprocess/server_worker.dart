/// Server-type Worker Process
///
/// This worker simulates a long-running server that:
/// 1. Handles multiple "requests" with random delays (3-10 seconds)
/// 2. Writes the final result to a file when done
///
/// Run with: dart run example/real_multiprocess/server_worker.dart `<output_path>`
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

void main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run server_worker.dart <output_path>');
    exit(1);
  }

  final outputPath = args[0];
  final random = Random();
  
  print('Starting server worker...');
  print('Output path: $outputPath');
  print('PID: $pid');

  final startTime = DateTime.now();
  final results = <Map<String, dynamic>>[];

  // Handle 3 "requests" with random delays
  for (var i = 1; i <= 3; i++) {
    final requestId = 'request_$i';
    final delay = Duration(seconds: 3 + random.nextInt(8)); // 3-10 seconds
    
    print('Processing $requestId (delay: ${delay.inSeconds}s)...');
    await Future.delayed(delay);
    
    results.add({
      'request_id': requestId,
      'status': 'processed',
      'delay_ms': delay.inMilliseconds,
      'completed_at': DateTime.now().toIso8601String(),
    });
    
    print('$requestId completed');
  }

  final endTime = DateTime.now();
  final totalTime = endTime.difference(startTime);

  // Create final result
  final result = {
    'status': 'server_shutdown',
    'requests_handled': results.length,
    'total_time_ms': totalTime.inMilliseconds,
    'request_results': results,
    'worker': 'server_worker',
    'pid': pid,
    'started_at': startTime.toIso8601String(),
    'ended_at': endTime.toIso8601String(),
  };

  // Write result to file
  print('Writing result to file...');
  final file = File(outputPath);
  await file.writeAsString(jsonEncode(result));

  print('Server shutdown complete. Result written to: $outputPath');
}
