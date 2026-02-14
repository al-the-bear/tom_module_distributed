// D4rt Bridge - Generated file, do not edit
// Dartscript registration for tom_process_monitor
// Generated: 2026-02-14T12:48:07.968980

/// D4rt Bridge Registration for tom_process_monitor
library;

import 'package:tom_d4rt/d4rt.dart';
import 'src/d4rt_bridges/tom_process_monitor_bridges.b.dart' as all_bridges;

/// Combined bridge registration for tom_process_monitor.
class TomProcessMonitorBridges {
  /// Register all bridges with D4rt interpreter.
  static void register([D4rt? interpreter]) {
    final d4rt = interpreter ?? D4rt();

    all_bridges.AllBridge.registerBridges(
      d4rt,
      'tom_process_monitor.dart',
    );
    all_bridges.AllBridge.registerBridges(
      d4rt,
      'lib/tom_process_monitor.dart',
    );
    // Register under sub-package barrels for direct imports
    for (final barrel in all_bridges.AllBridge.subPackageBarrels()) {
      all_bridges.AllBridge.registerBridges(d4rt, barrel);
    }
  }

  /// Get import block for all modules.
  static String getImportBlock() {
    final buffer = StringBuffer();
    buffer.writeln(all_bridges.AllBridge.getImportBlock());
    return buffer.toString();
  }
}
