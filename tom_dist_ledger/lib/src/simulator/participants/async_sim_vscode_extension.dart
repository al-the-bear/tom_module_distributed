import '../async_simulation.dart';
import '../../ledger_api/ledger_api.dart';
import '../simulation_config.dart';

/// Async simulated VS Code Extension using Ledger API.
class AsyncSimVSCodeExtension extends AsyncSimParticipant {
  AsyncSimVSCodeExtension({
    required Ledger ledger,
    required AsyncSimulationPrinter printer,
    required SimulationConfig config,
  }) : super(
          name: 'VSCode',
          pid: 222, // Same PID as Bridge (same process)
          ledger: ledger,
          printer: printer,
          config: config,
        );

  /// Cancel chat polling.
  void cancelChatPolling({required int depth}) {
    log(depth: depth, message: 'cancel chat polling');
  }

  /// Apply document edits.
  Future<void> applyEdits({required int depth}) async {
    log(depth: depth, message: 'applyEdits()');
    await simulateWork(duration: const Duration(milliseconds: 100));
  }
}
