/// Status information for the ProcessMonitor instance.
class MonitorStatus {
  /// ProcessMonitor instance ID.
  final String instanceId;

  /// Process ID of this instance.
  final int pid;

  /// When this instance started.
  final DateTime startedAt;

  /// Seconds since startup.
  final int uptime;

  /// Current state ("running", "stopping").
  final String state;

  /// Whether running in standalone mode (no partner).
  final bool standaloneMode;

  /// Partner instance ID (null if standalone).
  final String? partnerInstanceId;

  /// Partner status ("running", "stopped", "unknown").
  final String? partnerStatus;

  /// Partner's PID (null if unknown or standalone).
  final int? partnerPid;

  /// Total number of managed processes.
  final int managedProcessCount;

  /// Number of currently running processes.
  final int runningProcessCount;

  /// Creates a monitor status.
  const MonitorStatus({
    required this.instanceId,
    required this.pid,
    required this.startedAt,
    required this.uptime,
    required this.state,
    required this.standaloneMode,
    this.partnerInstanceId,
    this.partnerStatus,
    this.partnerPid,
    required this.managedProcessCount,
    required this.runningProcessCount,
  });

  /// Creates a MonitorStatus from JSON.
  factory MonitorStatus.fromJson(Map<String, dynamic> json) {
    return MonitorStatus(
      instanceId: json['instanceId'] as String,
      pid: json['pid'] as int,
      startedAt: DateTime.parse(json['startedAt'] as String),
      uptime: json['uptime'] as int,
      state: json['state'] as String,
      standaloneMode: json['standaloneMode'] as bool? ?? false,
      partnerInstanceId: json['partnerInstanceId'] as String?,
      partnerStatus: json['partnerStatus'] as String?,
      partnerPid: json['partnerPid'] as int?,
      managedProcessCount: json['managedProcessCount'] as int,
      runningProcessCount: json['runningProcessCount'] as int,
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      'instanceId': instanceId,
      'pid': pid,
      'startedAt': startedAt.toIso8601String(),
      'uptime': uptime,
      'state': state,
      'standaloneMode': standaloneMode,
      if (partnerInstanceId != null) 'partnerInstanceId': partnerInstanceId,
      if (partnerStatus != null) 'partnerStatus': partnerStatus,
      if (partnerPid != null) 'partnerPid': partnerPid,
      'managedProcessCount': managedProcessCount,
      'runningProcessCount': runningProcessCount,
    };
  }
}
