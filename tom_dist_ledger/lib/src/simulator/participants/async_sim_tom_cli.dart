import '../async_simulation.dart';

/// Async simulated Tom CLI (initiator) using Ledger API.
class AsyncSimTomCLI extends AsyncSimParticipant {
  AsyncSimTomCLI({
    required super.basePath,
    required super.printer,
    required super.config,
    super.onBackupCreated,
  }) : super(
          name: 'CLI',
          pid: 111,
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
