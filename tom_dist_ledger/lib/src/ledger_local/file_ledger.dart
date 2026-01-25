/// Frame state during cleanup process.
enum FrameState {
  /// Frame is executing normally.
  active,

  /// Frame's participant process has crashed.
  crashed,

  /// Frame marked as cleanup coordinator.
  cleaningUp,

  /// Frame has completed cleanup.
  cleanedUp,
}

/// Operation state during cleanup process.
enum OperationState {
  /// Operation is running normally.
  running,

  /// Failure detected, cleanup in progress.
  cleanup,

  /// Cleanup complete, operation failed.
  failed,

  /// Operation completed successfully.
  completed,
}

/// A call frame in the operation representing an active participant.
class CallFrame {
  final String participantId;
  final String callId;
  final int pid;
  final DateTime startTime;

  /// Last heartbeat timestamp for this participant.
  /// Each participant updates their own heartbeat independently.
  DateTime lastHeartbeat;

  /// State of this frame during cleanup.
  FrameState state;

  /// Optional human-readable description of this call.
  final String? description;

  /// Temporary resources registered by this call.
  final List<String> resources;

  /// Whether a crash in this call should fail the entire operation.
  /// If false, the crash is contained to this call only.
  final bool failOnCrash;

  CallFrame({
    required this.participantId,
    required this.callId,
    required this.pid,
    required this.startTime,
    DateTime? lastHeartbeat,
    FrameState? state,
    this.description,
    List<String>? resources,
    this.failOnCrash = true,
  }) : lastHeartbeat = lastHeartbeat ?? DateTime.now(),
       state = state ?? FrameState.active,
       resources = resources ?? [];

  Map<String, dynamic> toJson() => {
    'participantId': participantId,
    'callId': callId,
    'pid': pid,
    'startTime': startTime.toIso8601String(),
    'lastHeartbeat': lastHeartbeat.toIso8601String(),
    'state': state.name,
    'description': description,
    'resources': resources,
    'failOnCrash': failOnCrash,
  };

  factory CallFrame.fromJson(Map<String, dynamic> json) => CallFrame(
    participantId: json['participantId'] as String,
    callId: json['callId'] as String,
    pid: json['pid'] as int,
    startTime: DateTime.parse(json['startTime'] as String),
    lastHeartbeat: json['lastHeartbeat'] != null
        ? DateTime.parse(json['lastHeartbeat'] as String)
        : null,
    state: json['state'] != null
        ? FrameState.values.byName(json['state'] as String)
        : null,
    description: json['description'] as String?,
    resources: (json['resources'] as List<dynamic>?)
        ?.map((e) => e as String)
        .toList(),
    failOnCrash: json['failOnCrash'] as bool? ?? true,
  );

  /// Calculate the age of this participant's heartbeat in milliseconds.
  int get heartbeatAgeMs =>
      DateTime.now().difference(lastHeartbeat).inMilliseconds;

  /// Check if this participant's heartbeat is stale.
  bool isStale({int timeoutMs = 10000}) => heartbeatAgeMs > timeoutMs;

  @override
  String toString() =>
      'Frame(participant: $participantId, call: $callId, pid: $pid, failOnCrash: $failOnCrash)';
}

/// A temporary resource registered in the ledger.
class TempResource {
  final String path;
  final int owner;
  final DateTime registeredAt;

  TempResource({
    required this.path,
    required this.owner,
    required this.registeredAt,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'owner': owner,
    'registeredAt': registeredAt.toIso8601String(),
  };

  factory TempResource.fromJson(Map<String, dynamic> json) => TempResource(
    path: json['path'] as String,
    owner: json['owner'] as int,
    registeredAt: DateTime.parse(json['registeredAt'] as String),
  );

  @override
  String toString() => 'TempResource(path: $path, owner: $owner)';
}

/// Operation ledger data structure.
class LedgerData {
  final String operationId;

  /// ID of the participant that created this operation.
  final String initiatorId;

  /// When the operation was created.
  /// Participants can use this to calculate elapsed time consistently.
  final DateTime startTime;

  /// Whether the abort flag is set.
  bool aborted;

  DateTime lastHeartbeat;
  final List<CallFrame> callFrames;
  final List<TempResource> tempResources;

  /// Operation state during cleanup.
  OperationState operationState;

  /// Timestamp when cleanup detection occurred.
  DateTime? detectionTimestamp;

  /// Timestamp when frame removal occurred.
  DateTime? removalTimestamp;

  LedgerData({
    required this.operationId,
    required this.initiatorId,
    DateTime? startTime,
    this.aborted = false,
    DateTime? lastHeartbeat,
    List<CallFrame>? callFrames,
    List<TempResource>? tempResources,
    OperationState? operationState,
    this.detectionTimestamp,
    this.removalTimestamp,
  }) : startTime = startTime ?? DateTime.now(),
       lastHeartbeat = lastHeartbeat ?? DateTime.now(),
       callFrames = callFrames ?? [],
       tempResources = tempResources ?? [],
       operationState = operationState ?? OperationState.running;

  Map<String, dynamic> toJson() => {
    'operationId': operationId,
    'initiatorId': initiatorId,
    'startTime': startTime.toIso8601String(),
    'operationState': operationState.name,
    'aborted': aborted,
    'lastHeartbeat': lastHeartbeat.toIso8601String(),
    'callFrames': callFrames.map((f) => f.toJson()).toList(),
    'tempResources': tempResources.map((r) => r.toJson()).toList(),
    'detectionTimestamp': detectionTimestamp?.toIso8601String(),
    'removalTimestamp': removalTimestamp?.toIso8601String(),
  };

  factory LedgerData.fromJson(Map<String, dynamic> json) => LedgerData(
    operationId: json['operationId'] as String,
    initiatorId: json['initiatorId'] as String? ?? 'unknown',
    startTime: json['startTime'] != null
        ? DateTime.parse(json['startTime'] as String)
        : null,
    aborted: json['aborted'] as bool? ?? false,
    lastHeartbeat: json['lastHeartbeat'] != null
        ? DateTime.parse(json['lastHeartbeat'] as String)
        : null,
    // Support both old 'stack' and new 'callFrames' key for backward compatibility
    callFrames:
        ((json['callFrames'] ?? json['stack']) as List<dynamic>?)
            ?.map((e) => CallFrame.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    tempResources:
        (json['tempResources'] as List<dynamic>?)
            ?.map((e) => TempResource.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    operationState: json['operationState'] != null
        ? OperationState.values.byName(json['operationState'] as String)
        : null,
    detectionTimestamp: json['detectionTimestamp'] != null
        ? DateTime.parse(json['detectionTimestamp'] as String)
        : null,
    removalTimestamp: json['removalTimestamp'] != null
        ? DateTime.parse(json['removalTimestamp'] as String)
        : null,
  );

  bool get isEmpty => callFrames.isEmpty && tempResources.isEmpty;
}

/// Result of heartbeat checks.
class HeartbeatResult {
  /// Whether the abort flag is set.
  final bool abortFlag;

  /// Whether the ledger file exists.
  final bool ledgerExists;

  /// Whether the heartbeat was successfully updated.
  final bool heartbeatUpdated;

  /// Number of active call frames.
  final int callFrameCount;

  /// Number of temp resources.
  final int tempResourceCount;

  /// Age of the last heartbeat in milliseconds (global - deprecated).
  final int heartbeatAgeMs;

  /// Whether the heartbeat is stale (>10s) - global check.
  final bool isStale;

  /// List of call frame participant IDs.
  final List<String> participants;

  /// Per-participant heartbeat information.
  /// Key: participantId, Value: heartbeat age in ms.
  final Map<String, int> participantHeartbeatAges;

  /// List of participant IDs with stale heartbeats.
  final List<String> staleParticipants;

  /// The ledger data before the heartbeat update.
  ///
  /// This is null if the ledger didn't exist or couldn't be read.
  final LedgerData? dataBefore;

  /// The ledger data after the heartbeat update.
  ///
  /// This is null if the heartbeat update failed.
  final LedgerData? dataAfter;

  /// Whether any child participant has a stale heartbeat.
  bool get hasStaleChildren => staleParticipants.isNotEmpty;

  HeartbeatResult({
    required this.abortFlag,
    required this.ledgerExists,
    required this.heartbeatUpdated,
    required this.callFrameCount,
    required this.tempResourceCount,
    required this.heartbeatAgeMs,
    required this.isStale,
    required this.participants,
    this.participantHeartbeatAges = const {},
    this.staleParticipants = const [],
    this.dataBefore,
    this.dataAfter,
  });

  /// Create a result for when ledger doesn't exist.
  factory HeartbeatResult.noLedger() => HeartbeatResult(
    abortFlag: true,
    ledgerExists: false,
    heartbeatUpdated: false,
    callFrameCount: 0,
    tempResourceCount: 0,
    heartbeatAgeMs: 0,
    isStale: true,
    participants: [],
    participantHeartbeatAges: {},
    staleParticipants: [],
  );
}
