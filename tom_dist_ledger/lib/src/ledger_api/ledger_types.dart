/// Common types for the ledger API.
///
/// This file contains types that need to be shared between multiple
/// parts of the ledger package, avoiding circular dependencies.
library;

// Re-export types from file_ledger that are needed for callbacks
export 'package:tom_dist_ledger/src/ledger_local/file_ledger.dart'
    show HeartbeatResult;

/// Heartbeat error types.
enum HeartbeatErrorType {
  /// The ledger file was not found.
  ledgerNotFound,

  /// Failed to acquire lock on ledger file.
  lockFailed,

  /// The abort flag is set on the operation.
  abortFlagSet,

  /// Another participant's heartbeat is stale (may have crashed).
  heartbeatStale,

  /// I/O error during heartbeat.
  ioError,
}

/// Heartbeat error with details.
class HeartbeatError {
  /// The type of error that occurred.
  final HeartbeatErrorType type;

  /// Human-readable error message.
  final String message;

  /// Optional underlying cause.
  final Object? cause;

  const HeartbeatError({
    required this.type,
    required this.message,
    this.cause,
  });

  @override
  String toString() => 'HeartbeatError($type): $message';
}
