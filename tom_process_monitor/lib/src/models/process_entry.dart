import 'aliveness_check.dart';
import 'process_state.dart';
import 'restart_policy.dart';

/// Complete process entry stored in the registry.
class ProcessEntry {
  /// Unique process identifier.
  String id;

  /// Human-readable process name.
  String name;

  /// Executable path or command.
  String command;

  /// Command-line arguments.
  List<String> args;

  /// Working directory for the process.
  String? workingDirectory;

  /// Environment variables.
  Map<String, String>? environment;

  /// Start on ProcessMonitor initialization.
  bool autostart;

  /// Whether the process can be started.
  bool enabled;

  /// Whether registered via remote API.
  bool isRemote;

  /// Restart behavior configuration.
  RestartPolicy? restartPolicy;

  /// Optional HTTP aliveness check configuration.
  AlivenessCheck? alivenessCheck;

  /// When process was registered.
  DateTime registeredAt;

  /// When process was last started.
  DateTime? lastStartedAt;

  /// When process was last stopped.
  DateTime? lastStoppedAt;

  /// Current process ID (if running).
  int? pid;

  /// Current process state.
  ProcessState state;

  /// Current restart attempt count.
  int restartAttempts;

  /// Consecutive aliveness check failures.
  int consecutiveFailures;

  /// Creates a process entry.
  ProcessEntry({
    required this.id,
    required this.name,
    required this.command,
    this.args = const [],
    this.workingDirectory,
    this.environment,
    this.autostart = true,
    this.enabled = true,
    this.isRemote = false,
    this.restartPolicy,
    this.alivenessCheck,
    required this.registeredAt,
    this.lastStartedAt,
    this.lastStoppedAt,
    this.pid,
    this.state = ProcessState.stopped,
    this.restartAttempts = 0,
    this.consecutiveFailures = 0,
  });

  /// Creates a ProcessEntry from JSON.
  factory ProcessEntry.fromJson(Map<String, dynamic> json) {
    return ProcessEntry(
      id: json['id'] as String,
      name: json['name'] as String,
      command: json['command'] as String,
      args:
          (json['args'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          const [],
      workingDirectory: json['workingDirectory'] as String?,
      environment: (json['environment'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v as String),
      ),
      autostart: json['autostart'] as bool? ?? true,
      enabled: json['enabled'] as bool? ?? true,
      isRemote: json['isRemote'] as bool? ?? false,
      restartPolicy: json['restartPolicy'] != null
          ? RestartPolicy.fromJson(
              json['restartPolicy'] as Map<String, dynamic>,
            )
          : null,
      alivenessCheck: json['alivenessCheck'] != null
          ? AlivenessCheck.fromJson(
              json['alivenessCheck'] as Map<String, dynamic>,
            )
          : null,
      registeredAt: json['registeredAt'] != null
          ? DateTime.parse(json['registeredAt'] as String)
          : DateTime.now(),
      lastStartedAt: json['lastStartedAt'] != null
          ? DateTime.parse(json['lastStartedAt'] as String)
          : null,
      lastStoppedAt: json['lastStoppedAt'] != null
          ? DateTime.parse(json['lastStoppedAt'] as String)
          : null,
      pid: json['pid'] as int?,
      state: ProcessStateExtension.fromJson(
        json['state'] as String? ?? 'stopped',
      ),
      restartAttempts: json['restartAttempts'] as int? ?? 0,
      consecutiveFailures: json['consecutiveFailures'] as int? ?? 0,
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'command': command,
      'args': args,
      if (workingDirectory != null) 'workingDirectory': workingDirectory,
      if (environment != null) 'environment': environment,
      'autostart': autostart,
      'enabled': enabled,
      'isRemote': isRemote,
      if (restartPolicy != null) 'restartPolicy': restartPolicy!.toJson(),
      if (alivenessCheck != null) 'alivenessCheck': alivenessCheck!.toJson(),
      'registeredAt': registeredAt.toIso8601String(),
      if (lastStartedAt != null)
        'lastStartedAt': lastStartedAt!.toIso8601String(),
      if (lastStoppedAt != null)
        'lastStoppedAt': lastStoppedAt!.toIso8601String(),
      if (pid != null) 'pid': pid,
      'state': state.toJson(),
      'restartAttempts': restartAttempts,
      'consecutiveFailures': consecutiveFailures,
    };
  }

  /// Creates a copy with modified values.
  ProcessEntry copyWith({
    String? id,
    String? name,
    String? command,
    List<String>? args,
    String? workingDirectory,
    Map<String, String>? environment,
    bool? autostart,
    bool? enabled,
    bool? isRemote,
    RestartPolicy? restartPolicy,
    AlivenessCheck? alivenessCheck,
    DateTime? registeredAt,
    DateTime? lastStartedAt,
    DateTime? lastStoppedAt,
    int? pid,
    ProcessState? state,
    int? restartAttempts,
    int? consecutiveFailures,
  }) {
    return ProcessEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      command: command ?? this.command,
      args: args ?? this.args,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      environment: environment ?? this.environment,
      autostart: autostart ?? this.autostart,
      enabled: enabled ?? this.enabled,
      isRemote: isRemote ?? this.isRemote,
      restartPolicy: restartPolicy ?? this.restartPolicy,
      alivenessCheck: alivenessCheck ?? this.alivenessCheck,
      registeredAt: registeredAt ?? this.registeredAt,
      lastStartedAt: lastStartedAt ?? this.lastStartedAt,
      lastStoppedAt: lastStoppedAt ?? this.lastStoppedAt,
      pid: pid ?? this.pid,
      state: state ?? this.state,
      restartAttempts: restartAttempts ?? this.restartAttempts,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
    );
  }
}
