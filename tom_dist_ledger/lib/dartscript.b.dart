// D4rt Bridge - Generated file, do not edit
// Dartscript registration for tom_dist_ledger
// Generated: 2026-02-07T22:15:12.019873

/// D4rt Bridge Registration for tom_dist_ledger
library;

import 'package:tom_d4rt/d4rt.dart';
import 'src/d4rt_bridges/tom_dist_ledger_bridges.b.dart' as all_bridges;

/// Combined bridge registration for tom_dist_ledger.
class TomDistLedgerBridges {
  /// Register all bridges with D4rt interpreter.
  static void register([D4rt? interpreter]) {
    final d4rt = interpreter ?? D4rt();

    all_bridges.AllBridge.registerBridges(
      d4rt,
      'tom_dist_ledger.dart',
    );
    all_bridges.AllBridge.registerBridges(
      d4rt,
      'lib/tom_dist_ledger.dart',
    );
  }

  /// Get import block for all modules.
  static String getImportBlock() {
    final buffer = StringBuffer();
    buffer.writeln(all_bridges.AllBridge.getImportBlock());
    return buffer.toString();
  }
}
