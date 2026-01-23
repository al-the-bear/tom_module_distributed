import '../async_simulation.dart';

/// Async simulated DartScript Bridge using Ledger API.
class AsyncSimDartScriptBridge extends AsyncSimParticipant {
  AsyncSimDartScriptBridge({
    required String basePath,
    required super.printer,
    required super.config,
    void Function(String)? onBackupCreated,
  }) : super(
          name: 'Bridge',
          pid: 222,
          basePath: basePath,
          onBackupCreated: onBackupCreated,
        );

  /// Simulate file deletion.
  Future<void> fsDelete({
    required int depth,
    required String path,
  }) async {
    log(depth: depth, message: 'fs.delete("$path")');
    // Simulated - would actually delete the file in real implementation
    await Future.delayed(const Duration(milliseconds: 1));
  }

  /// Cleanup temp resources owned by this participant.
  Future<void> cleanupTempResources({required int depth}) async {
    log(depth: depth, message: 'cleanup tempResources (owner: $pid)');
    final data = operation.cachedData;
    if (data == null) return;

    for (final resource in data.tempResources.where((r) => r.owner == pid)) {
      await fsDelete(depth: depth, path: resource.path);
      await unregisterTempResource(depth: depth, path: resource.path);
    }
  }
}
