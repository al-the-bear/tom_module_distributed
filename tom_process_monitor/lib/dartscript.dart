/// D4rt Bridge Registration for tom_process_monitor
library;

import 'package:tom_d4rt/d4rt.dart';
import 'src/d4rt_bridges/tom_process_monitor_bridges.dart' as all_bridges;

/// Combined bridge registration for tom_process_monitor.
class TomProcessMonitorBridges {
  /// Register all bridges with D4rt interpreter.
  static void register([D4rt? interpreter]) {
    final d4rt = interpreter ?? D4rt();
    all_bridges.AllBridge.registerBridges(
      d4rt,
      'package:tom_process_monitor/tom_process_monitor.dart',
    );
  }

  /// Register all bridges with D4rt interpreter (legacy API).
  static void registerAllBridges(D4rt interpreter, String importPath) {
    all_bridges.AllBridge.registerBridges(interpreter, importPath);
  }

  /// Get all bridge classes (legacy API).
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
