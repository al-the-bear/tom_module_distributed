import 'dart:io';

import 'package:tom_dist_ledger/tom_dist_ledger.dart';
import 'package:test/test.dart';

void main() {
  group('Ledger', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dpl_test_');
      ledger = Ledger(basePath: tempDir.path);
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('can start an operation', () async {
      final operation = await ledger.startOperation(
        operationId: 'test_op_1',
        initiatorPid: pid,
        participantId: 'test',
        getElapsedFormatted: () => '000.000',
      );

      expect(operation.operationId, equals('test_op_1'));
      expect(operation.isInitiator, isTrue);
    });

    test('can track call execution', () async {
      final operation = await ledger.startOperation(
        operationId: 'test_op_2',
        initiatorPid: pid,
        participantId: 'test',
        getElapsedFormatted: () => '000.000',
      );

      await operation.startCallExecution(callId: 'call-1');
      expect(operation.cachedData?.stack.length, greaterThan(1));

      await operation.endCallExecution(callId: 'call-1');
      // Stack should have only the root frame now
      expect(operation.cachedData?.stack.length, equals(1));
    });
  });
}
