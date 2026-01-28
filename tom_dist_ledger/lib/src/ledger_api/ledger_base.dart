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
import 'package:tom_dist_ledger/src/ledger_local/file_ledger.dart';

// Re-export types for convenience
export 'package:tom_dist_ledger/src/ledger_api/ledger_types.dart';

/// Callback for heartbeat errors.
///
/// This callback receives the operation and the error that occurred.
/// Used by both local and remote ledger implementations.
typedef HeartbeatErrorCallback =
    void Function(Operation operation, HeartbeatError error);

/// Callback for successful heartbeat.
///
/// This callback receives the operation and the heartbeat result.
/// Used by both local and remote ledger implementations.
typedef HeartbeatSuccessCallback =
    void Function(Operation operation, HeartbeatResult result);

/// Abstract base class for operation handles.
///
/// Both [LocalOperation] (local) and [RemoteOperation] extend this class,
/// providing a common type for callbacks and polymorphic code.
///
/// ## Common Operations
///
/// All operation types support:
/// - Starting and tracking calls with [startCall]
/// - Syncing multiple spawned calls with [sync]
/// - Awaiting specific calls with [awaitCall]
/// - Waiting for call completion with [waitForCompletion]
/// - Abort handling with [setAbortFlag], [checkAbort], [triggerAbort]
/// - Logging with [log]
/// - Completing the operation with [complete] (initiator only)
/// - Leaving with [leave]
abstract class Operation {
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

  /// Future that completes when operation fails.
  Future<OperationFailedInfo> get onFailure;

  /// Elapsed time formatted as "SSS.mmm" (seconds.milliseconds).
  String get elapsedFormatted;

  /// Elapsed duration since operation start.
  Duration get elapsedDuration;

  /// Start time as ISO 8601 string.
  String get startTimeIso;

  /// Start time as milliseconds since epoch.
  int get startTimeMs;

  /// Number of pending calls for this session.
  int get pendingCallCount;

  /// Start a new call with typed result.
  ///
  /// Returns a [Call] object that must be ended with [Call.end].
  /// Optionally provide a [callback] for completion handling.
  ///
  /// Parameters:
  /// - [callback] - Optional callbacks for completion, crash, cleanup
  /// - [description] - Optional description for logging
  /// - [failOnCrash] - Whether crash should fail entire operation (default: true)
  Future<Call<T>> startCall<T>({
    CallCallback<T>? callback,
    String? description,
    bool failOnCrash = true,
  });

  /// Check if this session has any pending calls.
  bool hasPendingCalls();

  /// Spawn a call that runs asynchronously and is tracked by this session.
  ///
  /// The [work] function receives the [SpawnedCall] and this [Operation].
  /// The call is tracked in this session's pending calls.
  SpawnedCall<T> spawnCall<T>({
    required Future<T> Function(SpawnedCall<T> call, Operation operation) work,
    CallCallback<T>? callback,
    String? description,
    bool failOnCrash = true,
  });

  /// Sync multiple spawned calls, waiting for all to complete.
  ///
  /// Returns a [SyncResult] with success and failure counts.
  Future<SyncResult> sync(
    List<SpawnedCall<dynamic>> calls, {
    Future<void> Function(OperationFailedInfo info)? onOperationFailed,
    Future<void> Function()? onCompletion,
  });

  /// Wait for a specific spawned call to complete.
  Future<SyncResult> awaitCall<T>(
    SpawnedCall<T> call, {
    Future<void> Function(OperationFailedInfo info)? onOperationFailed,
    Future<void> Function()? onCompletion,
  });

  /// Wait for work while monitoring for operation failure.
  Future<T> waitForCompletion<T>(
    Future<T> Function() work, {
    Future<void> Function(OperationFailedInfo info)? onOperationFailed,
    Future<T> Function(Object error, StackTrace stackTrace)? onError,
  });

  /// Leave this session of the operation.
  ///
  /// For local operations, this is synchronous.
  /// For remote operations, this returns a Future.
  FutureOr<void> leave({bool cancelPendingCalls = false});

  /// Write an entry to the operation log.
  Future<void> log(String message, {DLLogLevel level = DLLogLevel.info});

  /// Complete the operation (for initiator only).
  Future<void> complete();

  /// Set the abort flag on the operation.
  Future<void> setAbortFlag(bool value);

  /// Check if the operation is aborted.
  Future<bool> checkAbort();

  /// Trigger local abort for this participant.
  void triggerAbort();

  /// Start heartbeat monitoring for this operation.
  void startHeartbeat({
    HeartbeatErrorCallback? onError,
    HeartbeatSuccessCallback? onSuccess,
  });

  // ─────────────────────────────────────────────────────────────────────
  // Low-level call frame operations
  // ─────────────────────────────────────────────────────────────────────

  /// Cached operation data from the last ledger read.
  ///
  /// For local operations, this is updated after each ledger modification.
  /// For remote operations, this is updated from server responses.
  LedgerData? get cachedData;

  /// Create a call frame directly (low-level operation).
  ///
  /// This is a lower-level method that directly manipulates call frames.
  /// For most use cases, prefer [startCall] which provides structured
  /// call tracking with callbacks.
  ///
  /// Use this method when:
  /// - You need direct control over call frame management
  /// - Testing call frame behavior without callback overhead
  /// - Implementing custom call patterns
  Future<void> createCallFrame({required String callId});

  /// Delete a call frame directly (low-level operation).
  ///
  /// This is a lower-level method that directly manipulates call frames.
  /// For most use cases, prefer [Call.end] which provides structured
  /// call completion with callbacks.
  Future<void> deleteCallFrame({required String callId});

  // ─────────────────────────────────────────────────────────────────────
  // Temporary resource management
  // ─────────────────────────────────────────────────────────────────────

  /// Register a temporary resource for cleanup tracking.
  ///
  /// For local operations, this registers the resource in the ledger file.
  /// For remote operations, this tracks the resource locally for cleanup
  /// on process exit or signal interruption.
  ///
  /// Registered resources should be cleaned up when the operation completes
  /// or if the process crashes/is interrupted.
  Future<void> registerTempResource({required String path});

  /// Unregister a temporary resource.
  ///
  /// Call this after successfully cleaning up a temporary resource.
  Future<void> unregisterTempResource({required String path});
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
  /// Creates a new operation and returns an [Operation] handle.
  /// The operation ID is auto-generated based on timestamp and participantId.
  ///
  /// **Automatic heartbeat management:** The heartbeat is automatically
  /// started when the operation is created.
  Future<Operation> createOperation({
    String? description,
    OperationCallback? callback,
  });

  /// Join an existing operation.
  ///
  /// Returns an [Operation] handle for the participant to interact with.
  /// Each call returns a new handle with its own session, even if joining
  /// the same operation multiple times.
  ///
  /// **Automatic heartbeat management:** The heartbeat is automatically
  /// started on first join and stopped when the last session leaves.
  Future<Operation> joinOperation({
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
    LedgerCallback? callback,
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
        callback: callback,
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

