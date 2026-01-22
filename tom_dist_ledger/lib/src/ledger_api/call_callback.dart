/// Data classes for call callbacks and info structures.
///
/// These classes support the callback pattern for cleanup and crash notification.
library;

import 'dart:async';

/// Callback structure for call operations.
///
/// Provides hooks for cleanup and notifications during call lifecycle.
class CallCallback {
  /// Called by ledger during cleanup (crash or normal operation end).
  /// Use this to release resources, close connections, delete temp files, etc.
  final Future<void> Function() onCleanup;

  /// Optional: Called when call ends normally.
  final Future<void> Function(CallEndedInfo info)? onEnded;

  /// Optional: Called when this call crashes (detected by another participant).
  final Future<void> Function(CrashedCallInfo info)? onCrashed;

  CallCallback({
    required this.onCleanup,
    this.onEnded,
    this.onCrashed,
  });
}

/// Information passed to [CallCallback.onEnded] when a call completes normally.
class CallEndedInfo {
  /// The unique identifier for this call.
  final String callId;

  /// The operation this call belongs to.
  final String operationId;

  /// The participant that made this call.
  final String participantId;

  /// When the call started.
  final DateTime startedAt;

  /// When the call ended.
  final DateTime endedAt;

  CallEndedInfo({
    required this.callId,
    required this.operationId,
    required this.participantId,
    required this.startedAt,
    required this.endedAt,
  });

  /// Duration of the call.
  Duration get duration => endedAt.difference(startedAt);

  @override
  String toString() =>
      'CallEndedInfo(callId: $callId, duration: ${duration.inMilliseconds}ms)';
}

/// Information passed to [CallCallback.onCrashed] when a call crashes.
class CrashedCallInfo {
  /// The unique identifier for the crashed call.
  final String callId;

  /// The operation this call belongs to.
  final String operationId;

  /// The participant that made this call.
  final String participantId;

  /// When the call started.
  final DateTime startedAt;

  /// When the crash was detected.
  final DateTime detectedAt;

  /// The reason for the crash, if known.
  final String? crashReason;

  CrashedCallInfo({
    required this.callId,
    required this.operationId,
    required this.participantId,
    required this.startedAt,
    required this.detectedAt,
    this.crashReason,
  });

  /// How long the call was running before the crash was detected.
  Duration get uptime => detectedAt.difference(startedAt);

  @override
  String toString() =>
      'CrashedCallInfo(callId: $callId, uptime: ${uptime.inMilliseconds}ms, reason: $crashReason)';
}

/// Information about an operation failure.
///
/// Passed to crash callbacks in [Operation.waitForCompletion] and [Operation.sync].
class OperationFailedInfo {
  /// The operation that failed.
  final String operationId;

  /// When the failure was detected.
  final DateTime failedAt;

  /// The reason for the failure, if known.
  final String? reason;

  /// List of call IDs that crashed.
  final List<String> crashedCallIds;

  OperationFailedInfo({
    required this.operationId,
    required this.failedAt,
    this.reason,
    this.crashedCallIds = const [],
  });

  @override
  String toString() =>
      'OperationFailedInfo(operationId: $operationId, crashedCallIds: $crashedCallIds, reason: $reason)';
}

/// Log levels for operation logging.
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// Extension to convert LogLevel to string.
extension LogLevelExtension on LogLevel {
  String get name => switch (this) {
        LogLevel.debug => 'DEBUG',
        LogLevel.info => 'INFO',
        LogLevel.warning => 'WARNING',
        LogLevel.error => 'ERROR',
      };
}
