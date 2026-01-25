/// Abstract base class for ledger implementations.
///
/// This provides the common interface for both local and remote ledger access.
/// The local implementation uses file-based storage, while the remote
/// implementation communicates with a ledger server via HTTP.
///
/// ## Unified Factory
///
/// Use [Ledger.connect] to create the appropriate implementation:
///
/// ```dart
/// // Local file-based ledger
/// final ledger = await Ledger.connect(
///   participantId: 'orchestrator',
///   basePath: '/tmp/ledger',
/// );
///
/// // Remote ledger via server URL
/// final ledger = await Ledger.connect(
///   participantId: 'worker',
///   serverUrl: 'http://localhost:19880',
/// );
///
/// // Remote with auto-discovery (no basePath or serverUrl)
/// final ledger = await Ledger.connect(
///   participantId: 'worker',
/// );
/// ```
library;

import 'dart:async';

import 'package:tom_dist_ledger/src/ledger_api/ledger_api.dart';
import 'package:tom_dist_ledger/src/ledger_client/remote_ledger_client.dart';

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
/// Both [LocalLedger] (file-based) and [RemoteLedgerClient] (HTTP) extend
/// this class, providing identical APIs except for initialization.
///
/// ## Factory Method
///
/// Use [Ledger.connect] to create the appropriate implementation based on
/// the parameters provided:
///
/// ```dart
/// // Local file-based ledger
/// final ledger = await Ledger.connect(
///   participantId: 'orchestrator',
///   basePath: '/tmp/ledger',
/// );
///
/// // Remote ledger with explicit server URL
/// final ledger = await Ledger.connect(
///   participantId: 'worker',
///   serverUrl: 'http://localhost:19880',
/// );
///
/// // Remote ledger with auto-discovery
/// final ledger = await Ledger.connect(
///   participantId: 'worker',
/// );
/// ```
abstract class Ledger {
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

  /// Create a new operation (for the initiator).
  ///
  /// Creates a new operation and returns an [OperationBase] handle.
  /// The operation ID is auto-generated based on timestamp and participantId.
  ///
  /// **Automatic heartbeat management:** The heartbeat is automatically
  /// started when the operation is created.
  Future<OperationBase> createOperation({
    String? description,
    OperationCallback? callback,
  });

  /// Join an existing operation.
  ///
  /// Returns an [OperationBase] handle for the participant to interact with.
  /// Each call returns a new handle with its own session, even if joining
  /// the same operation multiple times.
  ///
  /// **Automatic heartbeat management:** The heartbeat is automatically
  /// started on first join and stopped when the last session leaves.
  Future<OperationBase> joinOperation({
    required String operationId,
    OperationCallback? callback,
  });

  /// Dispose of the ledger and stop all heartbeats.
  void dispose();

  /// Connect to a ledger using the appropriate implementation.
  ///
  /// This factory method determines which implementation to use:
  /// - If [basePath] is provided: Creates a [LocalLedger] (file-based)
  /// - If [serverUrl] is provided: Creates a [RemoteLedgerClient] (direct connection)
  /// - If neither: Uses auto-discovery to find a remote server
  ///
  /// Throws [ArgumentError] if both [basePath] and [serverUrl] are provided.
  /// Returns `null` if auto-discovery fails to find a server.
  ///
  /// ## Examples
  ///
  /// ```dart
  /// // Local file-based ledger
  /// final ledger = await Ledger.connect(
  ///   participantId: 'orchestrator',
  ///   basePath: '/tmp/ledger',
  /// );
  ///
  /// // Remote ledger with explicit URL
  /// final ledger = await Ledger.connect(
  ///   participantId: 'worker',
  ///   serverUrl: 'http://localhost:19880',
  /// );
  ///
  /// // Remote with auto-discovery
  /// final ledger = await Ledger.connect(
  ///   participantId: 'worker',
  /// );
  /// if (ledger == null) {
  ///   print('No server found');
  /// }
  /// ```
  static Future<Ledger?> connect({
    required String participantId,
    String? basePath,
    String? serverUrl,
    int? participantPid,
    int maxBackups = 20,
    Duration heartbeatInterval = const Duration(seconds: 5),
    Duration staleThreshold = const Duration(seconds: 15),
  }) async {
    if (basePath != null && serverUrl != null) {
      throw ArgumentError(
        'Cannot specify both basePath and serverUrl. '
        'Use basePath for local file-based ledger, '
        'or serverUrl for remote ledger connection.',
      );
    }

    if (basePath != null) {
      // Local file-based ledger
      return LocalLedger(
        basePath: basePath,
        participantId: participantId,
        participantPid: participantPid,
        maxBackups: maxBackups,
        heartbeatInterval: heartbeatInterval,
        staleThreshold: staleThreshold,
      );
    }

    // Remote ledger - either explicit URL or auto-discovery
    return RemoteLedgerClient.connect(
      serverUrl: serverUrl,
      participantId: participantId,
      participantPid: participantPid,
      maxBackups: maxBackups,
      heartbeatInterval: heartbeatInterval,
      staleThreshold: staleThreshold,
    );
  }
}

/// Backwards compatibility alias for [Ledger].
@Deprecated('Use Ledger instead')
typedef LedgerBase = Ledger;
