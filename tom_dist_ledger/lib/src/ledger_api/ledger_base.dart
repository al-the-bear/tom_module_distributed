/// Abstract base class for ledger implementations.
///
/// This provides the common interface for both local and remote ledger access.
/// The local implementation uses file-based storage, while the remote
/// implementation communicates with a ledger server via HTTP.
library;

import 'dart:async';

import 'package:tom_dist_ledger/src/ledger_api/ledger_api.dart';

// Re-export types for convenience
export 'package:tom_dist_ledger/src/ledger_api/ledger_types.dart';

/// Callback for heartbeat errors.
///
/// This callback receives the operation and the error that occurred.
/// Used by both local and remote ledger implementations.
typedef HeartbeatErrorCallback =
    void Function(OperationBase operation, HeartbeatError error);

/// Callback for successful heartbeat.
///
/// This callback receives the operation and the heartbeat result.
/// Used by both local and remote ledger implementations.
typedef HeartbeatSuccessCallback =
    void Function(OperationBase operation, HeartbeatResult result);

/// Abstract base class for operation handles.
///
/// Both [Operation] (local) and [RemoteOperation] extend this class, providing
/// a common type for callbacks and polymorphic code.
abstract class OperationBase {
  /// The operation ID.
  String get operationId;

  /// The participant ID.
  String get participantId;

  /// Whether this is the initiator.
  bool get isInitiator;

  /// The session ID for this handle.
  int get sessionId;

  /// When this operation was started.
  DateTime get startTime;

  /// Whether this participant is aborted.
  bool get isAborted;

  /// Future that completes when abort is signaled.
  Future<void> get onAbort;

  /// Leave this session of the operation.
  ///
  /// For local operations, this is synchronous.
  /// For remote operations, this returns a Future.
  FutureOr<void> leave({bool cancelPendingCalls = false});

  /// Write an entry to the operation log.
  Future<void> log(String message, {LogLevel level = LogLevel.info});

  /// Complete the operation (for initiator only).
  Future<void> complete();

  /// Set the abort flag on the operation.
  Future<void> setAbortFlag(bool value);

  /// Check if the operation is aborted.
  Future<bool> checkAbort();

  /// Trigger local abort for this participant.
  void triggerAbort();
}

/// Abstract base class for ledger implementations.
///
/// Both [Ledger] (local) and [RemoteLedgerClient] extend this class, providing
/// identical APIs except for initialization.
///
/// ## Usage
///
/// For local access:
/// ```dart
/// final ledger = Ledger(
///   basePath: '/tmp/ledger',
///   participantId: 'orchestrator',
/// );
/// ```
///
/// For remote access:
/// ```dart
/// final ledger = RemoteLedgerClient(
///   serverUrl: 'http://localhost:19876',
///   participantId: 'remote_worker',
/// );
/// ```
abstract class LedgerBase {
  /// The participant ID for this ledger instance.
  ///
  /// This identifies who is interacting with the ledger. Each participant
  /// (CLI, Bridge, VS Code, etc.) should have its own unique ID.
  String get participantId;

  /// The process ID for this participant.
  int get participantPid;

  /// Maximum number of backup operations to retain.
  int get maxBackups;

  /// Heartbeat interval for global monitoring.
  Duration get heartbeatInterval;

  /// Staleness threshold for detecting crashed operations.
  Duration get staleThreshold;

  /// Dispose of the ledger and stop all heartbeats.
  void dispose();
}
