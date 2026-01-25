/// Basic Ledger API Example
///
/// Demonstrates the fundamental operations of the DPL Ledger API:
/// - Starting an operation
/// - Tracking call execution
/// - Completing an operation
///
/// Run with: dart run example/tom_dist_ledger_example.dart
library;

import 'dart:io';

import 'package:tom_dist_ledger/tom_dist_ledger.dart';

void main() async {
  // Create a ledger in a temp directory
  final tempDir = Directory.systemTemp.createTempSync('dpl_example_');

  final ledger = await Ledger.connect(
    basePath: tempDir.path,
    participantId: 'example',
  );

  if (ledger == null) {
    print('Failed to create ledger');
    tempDir.deleteSync(recursive: true);
    return;
  }

  try {
    // Start an operation
    final operation = await ledger.createOperation();

    print('Started operation: ${operation.operationId}');

    // Start a call with typed result tracking
    final call = await operation.startCall<String>();
    print('Started call execution');

    // Simulate work
    await Future.delayed(const Duration(milliseconds: 100));
    final result = 'work completed';

    // End the call with result
    await call.end(result);
    print('Ended call execution with result: $result');

    // Complete the operation
    await operation.complete();
    print('Operation completed');
  } finally {
    ledger.dispose();
    // Clean up temp directory
    tempDir.deleteSync(recursive: true);
  }
}
