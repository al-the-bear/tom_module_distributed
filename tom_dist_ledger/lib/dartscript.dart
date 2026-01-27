/// D4rt Bridge Registration for tom_dist_ledger
library;

import 'package:tom_d4rt/d4rt.dart';
import 'src/d4rt_bridges/tom_dist_ledger_bridges.dart' as all_bridges;

export 'tom_dist_ledger.dart';

/// Combined bridge registration for tom_dist_ledger.
class TomDistLedgerBridges {
  /// Register all bridges with D4rt interpreter.
  static void register([D4rt? interpreter]) {
    final d4rt = interpreter ?? D4rt();
    all_bridges.AllBridge.registerBridges(
      d4rt,
      'package:tom_dist_ledger/tom_dist_ledger.dart',
    );
  }

  /// Legacy method for backward compatibility.
  /// The [importPath] parameter is ignored (kept for backward compatibility).
  @Deprecated('Use register() instead')
  static void registerAllBridges(D4rt interpreter, [String? importPath]) {
    register(interpreter);
  }

  /// Get all bridge classes.
  static List<BridgedClass> bridgeClasses() {
    return [
      ...all_bridges.AllBridge.bridgeClasses(),
    ];
  }

  /// Get import block for all modules.
  static String getImportBlock() {
    final buffer = StringBuffer();
    buffer.writeln(all_bridges.AllBridge.getImportBlock());
    return buffer.toString();
  }

  /// Get global initialization script.
  static String getGlobalInitializationScript() {
    return '';
  }
}
