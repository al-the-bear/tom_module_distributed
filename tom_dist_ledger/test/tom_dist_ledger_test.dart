import 'dart:io';

import 'package:tom_dist_ledger/tom_dist_ledger.dart';
import 'package:test/test.dart';

void main() {
  group('Ledger', () {
    late Directory tempDir;
    late Ledger ledger;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dpl_test_');
      ledger = Ledger(basePath: tempDir.path, participantId: 'test');
    });

    tearDown(() {
      ledger.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('can start an operation', () async {
      final operation = await ledger.createOperation();

      expect(operation.operationId, isNotEmpty);
      expect(operation.isInitiator, isTrue);
    });

    test('can track call execution', () async {
      final operation = await ledger.createOperation();

      await operation.createCallFrame(callId: 'call-1');
      // Stack has 1 frame (createCallFrame adds it)
      expect(operation.cachedData?.callFrames.length, equals(1));

      await operation.deleteCallFrame(callId: 'call-1');
      // Stack should be empty now
      expect(operation.cachedData?.callFrames.length, equals(0));
    });
  });
}
