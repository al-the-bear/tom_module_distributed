import '../async_simulation.dart';

/// Async simulated VS Code Extension using Ledger API.
class AsyncSimVSCodeExtension extends AsyncSimParticipant {
  AsyncSimVSCodeExtension({
    required super.basePath,
    required super.printer,
    required super.config,
    super.onBackupCreated,
  }) : super(
          name: 'VSCode',
          pid: 222, // Same PID as Bridge (same process)
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
