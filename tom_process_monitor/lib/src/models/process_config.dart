import 'aliveness_check.dart';
import 'restart_policy.dart';

/// Configuration for registering a process.
class ProcessConfig {
  /// Unique identifier for the process.
  final String id;

  /// Human-readable name.
  final String name;

  /// Executable command.
  final String command;

  /// Command-line arguments.
  final List<String> args;

  /// Working directory (optional).
  final String? workingDirectory;

  /// Environment variables (optional).
  final Map<String, String>? environment;

  /// Start automatically when ProcessMonitor initializes.
  final bool autostart;

  /// Restart policy configuration.
  final RestartPolicy? restartPolicy;

  /// Optional HTTP aliveness check configuration.
  final AlivenessCheck? alivenessCheck;

  /// Creates a process configuration.
  const ProcessConfig({
    required this.id,
    required this.name,
    required this.command,
    this.args = const [],
    this.workingDirectory,
    this.environment,
    this.autostart = true,
    this.restartPolicy,
    this.alivenessCheck,
  });

  /// Creates a ProcessConfig from JSON.
  factory ProcessConfig.fromJson(Map<String, dynamic> json) {
    return ProcessConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      command: json['command'] as String,
      args: (json['args'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      workingDirectory: json['workingDirectory'] as String?,
      environment: (json['environment'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v as String)),
      autostart: json['autostart'] as bool? ?? true,
      restartPolicy: json['restartPolicy'] != null
          ? RestartPolicy.fromJson(json['restartPolicy'] as Map<String, dynamic>)
          : null,
      alivenessCheck: json['alivenessCheck'] != null
          ? AlivenessCheck.fromJson(json['alivenessCheck'] as Map<String, dynamic>)
          : null,
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
      if (restartPolicy != null) 'restartPolicy': restartPolicy!.toJson(),
      if (alivenessCheck != null) 'alivenessCheck': alivenessCheck!.toJson(),
    };
  }

  /// Creates a copy with modified values.
  ProcessConfig copyWith({
    String? id,
    String? name,
    String? command,
    List<String>? args,
    String? workingDirectory,
    Map<String, String>? environment,
    bool? autostart,
    RestartPolicy? restartPolicy,
    AlivenessCheck? alivenessCheck,
  }) {
    return ProcessConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      command: command ?? this.command,
      args: args ?? this.args,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      environment: environment ?? this.environment,
      autostart: autostart ?? this.autostart,
      restartPolicy: restartPolicy ?? this.restartPolicy,
      alivenessCheck: alivenessCheck ?? this.alivenessCheck,
    );
  }
}
