/// D4rt Bridge Registration for tom_process_monitor
library;

import 'package:tom_d4rt/d4rt.dart';
import 'src/d4rt_bridges/tom_process_monitor_bridges.dart' as all_bridges;

export 'tom_process_monitor.dart';

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
