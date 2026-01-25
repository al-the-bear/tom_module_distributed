import 'dart:io';

import 'package:path/path.dart' as path;

import '../exceptions/process_disabled_exception.dart';
import '../exceptions/process_monitor_exception.dart';
import '../exceptions/process_not_found_exception.dart';
import '../models/monitor_status.dart';
import '../models/partner_discovery_config.dart';
import '../models/process_config.dart';
import '../models/process_entry.dart';
import '../models/process_state.dart';
import '../models/process_status.dart';
import '../models/remote_access_config.dart';
import '../services/process_control.dart';
import '../services/registry_service.dart';
import 'process_monitor_base.dart';

/// Local client API for interacting with ProcessMonitor.
///
/// This client communicates via the file-based registry and does not
/// require direct connection to the ProcessMonitor daemon.
class LocalProcessMonitorClient implements ProcessMonitorClient {
  /// Directory containing registry and lock files.
  final String directory;

  /// ProcessMonitor instance ID.
  final String instanceId;

  late final RegistryService _registry;
  late final ProcessControl _processControl;

  /// Creates a local process monitor client.
  LocalProcessMonitorClient({String? directory, this.instanceId = 'default'})
    : directory = directory ?? _resolveDefaultDirectory() {
    _registry = RegistryService(
      directory: this.directory,
      instanceId: instanceId,
    );
    _processControl = ProcessControl(logDirectory: this.directory);
  }

  // --- Registration ---

  /// Register a new local process with the monitor.
  @override
  Future<void> register(ProcessConfig config) async {
    await _registry.withLock((registry) async {
      if (registry.processes.containsKey(config.id)) {
        throw ProcessMonitorException('Process ${config.id} already exists');
      }

      registry.processes[config.id] = ProcessEntry(
        id: config.id,
        name: config.name,
        command: config.command,
        args: config.args,
        workingDirectory: config.workingDirectory,
        environment: config.environment,
        autostart: config.autostart,
        enabled: true,
        isRemote: false,
        restartPolicy: config.restartPolicy,
        alivenessCheck: config.alivenessCheck,
        registeredAt: DateTime.now(),
      );
    });
  }

  /// Remove a process from the registry.
  /// Stops the process if running.
  @override
  Future<void> deregister(String processId) async {
    await _registry.withLock((registry) async {
      final process = registry.processes[processId];
      if (process == null) {
        throw ProcessNotFoundException(processId);
      }

      // Stop if running
      if (process.pid != null && process.state == ProcessState.running) {
        await _processControl.stopProcessGracefully(process.pid!);
      }

      registry.processes.remove(processId);
    });
  }

  // --- Enable/Disable ---

  /// Enable a process (allows it to be started).
  @override
  Future<void> enable(String processId) async {
    await _registry.withLock((registry) async {
      final process = registry.processes[processId];
      if (process == null) {
        throw ProcessNotFoundException(processId);
      }

      process.enabled = true;
      if (process.state == ProcessState.disabled) {
        process.state = ProcessState.stopped;
      }
    });
  }

  /// Disable a process (stops it and prevents restart).
  @override
  Future<void> disable(String processId) async {
    await _registry.withLock((registry) async {
      final process = registry.processes[processId];
      if (process == null) {
        throw ProcessNotFoundException(processId);
      }

      // Stop if running
      if (process.pid != null && process.state == ProcessState.running) {
        await _processControl.stopProcessGracefully(process.pid!);
        process.pid = null;
        process.lastStoppedAt = DateTime.now();
      }

      process.enabled = false;
      process.state = ProcessState.disabled;
    });
  }

  // --- Autostart ---

  /// Set whether the process starts automatically.
  @override
  Future<void> setAutostart(String processId, bool autostart) async {
    await _registry.withLock((registry) async {
      final process = registry.processes[processId];
      if (process == null) {
        throw ProcessNotFoundException(processId);
      }

      process.autostart = autostart;
    });
  }

  // --- Process Control ---

  /// Start a process (if enabled).
  @override
  Future<void> start(String processId) async {
    await _registry.withLock((registry) async {
      final process = registry.processes[processId];
      if (process == null) {
        throw ProcessNotFoundException(processId);
      }

      if (!process.enabled) {
        throw ProcessDisabledException(processId);
      }

      if (process.state == ProcessState.running && process.pid != null) {
        // Already running
        return;
      }

      process.state = ProcessState.starting;
    });
  }

  /// Stop a process (does not disable it).
  @override
  Future<void> stop(String processId) async {
    await _registry.withLock((registry) async {
      final process = registry.processes[processId];
      if (process == null) {
        throw ProcessNotFoundException(processId);
      }

      if (process.pid != null) {
        process.state = ProcessState.stopping;
        await _processControl.stopProcessGracefully(process.pid!);
        process.pid = null;
        process.lastStoppedAt = DateTime.now();
      }

      process.state = ProcessState.stopped;
    });
  }

  /// Restart a process (stop then start).
  @override
  Future<void> restart(String processId) async {
    await stop(processId);
    await start(processId);
  }

  // --- Status ---

  /// Get status of a specific process.
  @override
  Future<ProcessStatus> getStatus(String processId) async {
    return _registry.withLockReadOnly((registry) async {
      final process = registry.processes[processId];
      if (process == null) {
        throw ProcessNotFoundException(processId);
      }

      return _toStatus(process);
    });
  }

  /// Get status of all registered processes.
  @override
  Future<Map<String, ProcessStatus>> getAllStatus() async {
    return _registry.withLockReadOnly((registry) async {
      return registry.processes.map(
        (key, value) => MapEntry(key, _toStatus(value)),
      );
    });
  }

  // --- Remote Access Configuration ---

  /// Enable or disable remote HTTP API access.
  @override
  Future<void> setRemoteAccess(bool enabled) async {
    await _registry.withLock((registry) async {
      registry.remoteAccess = registry.remoteAccess.copyWith(
        startRemoteAccess: enabled,
      );
    });
  }

  /// Get current remote access configuration.
  @override
  Future<RemoteAccessConfig> getRemoteAccessConfig() async {
    return _registry.withLockReadOnly((registry) async {
      return registry.remoteAccess;
    });
  }

  /// Set remote access permissions.
  @override
  Future<void> setRemoteAccessPermissions({
    bool? allowRegister,
    bool? allowDeregister,
    bool? allowStart,
    bool? allowStop,
    bool? allowDisable,
    bool? allowAutostart,
    bool? allowMonitorRestart,
  }) async {
    await _registry.withLock((registry) async {
      registry.remoteAccess = registry.remoteAccess.copyWith(
        allowRemoteRegister: allowRegister,
        allowRemoteDeregister: allowDeregister,
        allowRemoteStart: allowStart,
        allowRemoteStop: allowStop,
        allowRemoteDisable: allowDisable,
        allowRemoteAutostart: allowAutostart,
        allowRemoteMonitorRestart: allowMonitorRestart,
      );
    });
  }

  /// Set trusted hosts list.
  @override
  Future<void> setTrustedHosts(List<String> hosts) async {
    await _registry.withLock((registry) async {
      registry.remoteAccess = registry.remoteAccess.copyWith(
        trustedHosts: hosts,
      );
    });
  }

  /// Get trusted hosts list.
  @override
  Future<List<String>> getTrustedHosts() async {
    return _registry.withLockReadOnly((registry) async {
      return registry.remoteAccess.trustedHosts;
    });
  }

  // --- Executable Filtering ---

  /// Get the current executable whitelist.
  @override
  Future<List<String>> getRemoteExecutableWhitelist() async {
    return _registry.withLockReadOnly((registry) async {
      return registry.remoteAccess.executableWhitelist;
    });
  }

  /// Set the executable whitelist (glob patterns).
  @override
  Future<void> setRemoteExecutableWhitelist(List<String> patterns) async {
    await _registry.withLock((registry) async {
      registry.remoteAccess = registry.remoteAccess.copyWith(
        executableWhitelist: patterns,
      );
    });
  }

  /// Get the current executable blacklist.
  @override
  Future<List<String>> getRemoteExecutableBlacklist() async {
    return _registry.withLockReadOnly((registry) async {
      return registry.remoteAccess.executableBlacklist;
    });
  }

  /// Set the executable blacklist (glob patterns).
  @override
  Future<void> setRemoteExecutableBlacklist(List<String> patterns) async {
    await _registry.withLock((registry) async {
      registry.remoteAccess = registry.remoteAccess.copyWith(
        executableBlacklist: patterns,
      );
    });
  }

  // --- Standalone / Partner Configuration ---

  /// Enable or disable standalone mode (no partner monitoring).
  @override
  Future<void> setStandaloneMode(bool enabled) async {
    await _registry.withLock((registry) async {
      registry.standaloneMode = enabled;
    });
  }

  /// Get current standalone mode setting.
  @override
  Future<bool> isStandaloneMode() async {
    return _registry.withLockReadOnly((registry) async {
      return registry.standaloneMode;
    });
  }

  /// Get partner discovery configuration.
  @override
  Future<PartnerDiscoveryConfig> getPartnerDiscoveryConfig() async {
    return _registry.withLockReadOnly((registry) async {
      return registry.partnerDiscovery;
    });
  }

  /// Set partner discovery configuration.
  @override
  Future<void> setPartnerDiscoveryConfig(PartnerDiscoveryConfig config) async {
    await _registry.withLock((registry) async {
      registry.partnerDiscovery = config;
    });
  }

  // --- Monitor Control ---

  /// Restart the ProcessMonitor itself.
  /// This sets a flag that the monitor will pick up.
  @override
  Future<void> restartMonitor() async {
    // Create a restart signal file
    final signalFile = File(path.join(directory, 'restart_$instanceId.signal'));
    await signalFile.writeAsString(DateTime.now().toIso8601String());
  }

  /// Get the status of the ProcessMonitor itself.
  @override
  Future<MonitorStatus> getMonitorStatus() async {
    return _registry.withLockReadOnly((registry) async {
      final processes = registry.processes;
      final runningCount =
          processes.values.where((p) => p.state == ProcessState.running).length;

      // Read monitor PID from pid file if exists
      final pidFile = File(path.join(directory, 'monitor_$instanceId.pid'));
      int? monitorPid;
      DateTime? startedAt;

      if (await pidFile.exists()) {
        try {
          monitorPid = int.tryParse(await pidFile.readAsString());
          startedAt = (await pidFile.stat()).modified;
        } catch (_) {
          // Ignore errors reading PID file
        }
      }

      return MonitorStatus(
        instanceId: instanceId,
        pid: monitorPid ?? 0,
        startedAt: startedAt ?? DateTime.now(),
        uptime:
            startedAt != null
                ? DateTime.now().difference(startedAt).inSeconds
                : 0,
        state: 'running',
        standaloneMode: registry.standaloneMode,
        partnerInstanceId: null, // Would need partner registry lookup
        partnerStatus: null,
        partnerPid: null,
        managedProcessCount: processes.length,
        runningProcessCount: runningCount,
      );
    });
  }

  /// Dispose of resources held by this client.
  ///
  /// For local clients, this is a no-op as there are no resources to release.
  @override
  void dispose() {
    // No-op for local client
  }

  ProcessStatus _toStatus(ProcessEntry entry) {
    return ProcessStatus(
      id: entry.id,
      name: entry.name,
      state: entry.state,
      enabled: entry.enabled,
      autostart: entry.autostart,
      isRemote: entry.isRemote,
      pid: entry.pid,
      lastStartedAt: entry.lastStartedAt,
      lastStoppedAt: entry.lastStoppedAt,
      restartAttempts: entry.restartAttempts,
    );
  }
}

/// Resolves the user home directory cross-platform.
String _resolveHomeDirectory() {
  // Try HOME first (Linux, macOS)
  final home = Platform.environment['HOME'];
  if (home != null) return home;

  // Try USERPROFILE (Windows)
  final userProfile = Platform.environment['USERPROFILE'];
  if (userProfile != null) return userProfile;

  // Fallback to current directory
  return '.';
}

/// Resolves the default directory.
/// Uses the user's home directory (~/.tom/process_monitor/).
/// Override with the --directory command-line option.
String _resolveDefaultDirectory() {
  return path.join(_resolveHomeDirectory(), '.tom', 'process_monitor');
}
