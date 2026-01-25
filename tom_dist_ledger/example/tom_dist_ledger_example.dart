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

  final ledger = LocalLedger(
    basePath: tempDir.path,
    participantId: 'example',
    callback: LedgerCallback(onBackupCreated: (path) => print('Backup: $path')),
  );

  try {
    // Start an operation
    final operation = await ledger.createOperation();

    print('Started operation: ${operation.operationId}');

    // Track a call
    await operation.createCallFrame(callId: 'example-call-1');
    print('Started call execution');

    // Simulate work
    await Future.delayed(const Duration(milliseconds: 100));

    // End the call
    await operation.deleteCallFrame(callId: 'example-call-1');
    print('Ended call execution');

    // Complete the operation
    await operation.complete();
    print('Operation completed');
  } finally {
    ledger.dispose();
    // Clean up temp directory
    tempDir.deleteSync(recursive: true);
  }
}
