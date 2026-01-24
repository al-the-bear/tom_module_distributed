import 'process_state.dart';

/// Status information for a process.
class ProcessStatus {
  /// Unique process identifier.
  final String id;

  /// Human-readable process name.
  final String name;

  /// Current process state.
  final ProcessState state;

  /// Whether the process can be started.
  final bool enabled;

  /// Start on ProcessMonitor initialization.
  final bool autostart;

  /// Whether registered via remote API.
  final bool isRemote;

  /// Current process ID (if running).
  final int? pid;

  /// When process was last started.
  final DateTime? lastStartedAt;

  /// When process was last stopped.
  final DateTime? lastStoppedAt;

  /// Current restart attempt count.
  final int restartAttempts;

  /// Creates a process status.
  const ProcessStatus({
    required this.id,
    required this.name,
    required this.state,
    required this.enabled,
    required this.autostart,
    required this.isRemote,
    this.pid,
    this.lastStartedAt,
    this.lastStoppedAt,
    this.restartAttempts = 0,
  });

  /// Creates a ProcessStatus from JSON.
  factory ProcessStatus.fromJson(Map<String, dynamic> json) {
    return ProcessStatus(
      id: json['id'] as String,
      name: json['name'] as String,
      state: ProcessStateExtension.fromJson(json['state'] as String),
      enabled: json['enabled'] as bool,
      autostart: json['autostart'] as bool,
      isRemote: json['isRemote'] as bool,
      pid: json['pid'] as int?,
      lastStartedAt: json['lastStartedAt'] != null
          ? DateTime.parse(json['lastStartedAt'] as String)
          : null,
      lastStoppedAt: json['lastStoppedAt'] != null
          ? DateTime.parse(json['lastStoppedAt'] as String)
          : null,
      restartAttempts: json['restartAttempts'] as int? ?? 0,
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'state': state.toJson(),
      'enabled': enabled,
      'autostart': autostart,
      'isRemote': isRemote,
      if (pid != null) 'pid': pid,
      if (lastStartedAt != null)
        'lastStartedAt': lastStartedAt!.toIso8601String(),
      if (lastStoppedAt != null)
        'lastStoppedAt': lastStoppedAt!.toIso8601String(),
      'restartAttempts': restartAttempts,
    };
  }
}
