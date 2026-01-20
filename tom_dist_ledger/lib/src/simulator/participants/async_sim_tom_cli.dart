import '../async_simulation.dart';
import '../../ledger_api/ledger_api.dart';
import '../simulation_config.dart';

/// Async simulated Tom CLI (initiator) using Ledger API.
class AsyncSimTomCLI extends AsyncSimParticipant {
  AsyncSimTomCLI({
    required Ledger ledger,
    required AsyncSimulationPrinter printer,
    required SimulationConfig config,
  }) : super(
          name: 'CLI',
          pid: 111,
          ledger: ledger,
          printer: printer,
          config: config,
        );

  /// Simulate CLI exit.
  void exit({
    required int depth,
    required int code,
  }) {
    log(depth: depth, message: 'exit($code)');
  }

  /// Handle simulated SIGINT.
  void receiveSigint({required int depth}) {
    log(depth: depth, message: 'received SIGINT');
  }
}
