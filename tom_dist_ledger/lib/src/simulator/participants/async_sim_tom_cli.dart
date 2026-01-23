import '../async_simulation.dart';

/// Async simulated Tom CLI (initiator) using Ledger API.
class AsyncSimTomCLI extends AsyncSimParticipant {
  AsyncSimTomCLI({
    required String basePath,
    required super.printer,
    required super.config,
    void Function(String)? onBackupCreated,
  }) : super(
          name: 'CLI',
          pid: 111,
          basePath: basePath,
          onBackupCreated: onBackupCreated,
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
