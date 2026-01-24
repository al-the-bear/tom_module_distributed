import 'dart:io';

import 'package:path/path.dart' as path;

import '../exceptions/process_disabled_exception.dart';
import '../exceptions/process_monitor_exception.dart';
import '../exceptions/process_not_found_exception.dart';
import '../models/partner_discovery_config.dart';
import '../models/process_config.dart';
import '../models/process_entry.dart';
import '../models/process_state.dart';
import '../models/process_status.dart';
import '../models/remote_access_config.dart';
import '../services/process_control.dart';
import '../services/registry_service.dart';

/// Local client API for interacting with ProcessMonitor.
///
/// This client communicates via the file-based registry and does not
/// require direct connection to the ProcessMonitor daemon.
class ProcessMonitorClient {
  /// Directory containing registry and lock files.
  final String directory;

  /// ProcessMonitor instance ID.
  final String instanceId;

  late final RegistryService _registry;
  late final ProcessControl _processControl;

  /// Creates a local process monitor client.
  ProcessMonitorClient({
    String? directory,
    this.instanceId = 'default',
  }) : directory = directory ?? _resolveDefaultDirectory() {
    _registry = RegistryService(
      directory: this.directory,
      instanceId: instanceId,
    );
    _processControl = ProcessControl(
      logDirectory: this.directory,
    );
  }

  // --- Registration ---

  /// Register a new local process with the monitor.
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
  Future<void> restart(String processId) async {
    await stop(processId);
    await start(processId);
  }

  // --- Status ---

  /// Get status of a specific process.
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
  Future<Map<String, ProcessStatus>> getAllStatus() async {
    return _registry.withLockReadOnly((registry) async {
      return registry.processes.map(
        (key, value) => MapEntry(key, _toStatus(value)),
      );
    });
  }

  // --- Remote Access Configuration ---

  /// Enable or disable remote HTTP API access.
  Future<void> setRemoteAccess(bool enabled) async {
    await _registry.withLock((registry) async {
      registry.remoteAccess = registry.remoteAccess.copyWith(
        startRemoteAccess: enabled,
      );
    });
  }

  /// Get current remote access configuration.
  Future<RemoteAccessConfig> getRemoteAccessConfig() async {
    return _registry.withLockReadOnly((registry) async {
      return registry.remoteAccess;
    });
  }

  /// Set remote access permissions.
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
  Future<void> setTrustedHosts(List<String> hosts) async {
    await _registry.withLock((registry) async {
      registry.remoteAccess = registry.remoteAccess.copyWith(
        trustedHosts: hosts,
      );
    });
  }

  /// Get trusted hosts list.
  Future<List<String>> getTrustedHosts() async {
    return _registry.withLockReadOnly((registry) async {
      return registry.remoteAccess.trustedHosts;
    });
  }

  // --- Executable Filtering ---

  /// Get the current executable whitelist.
  Future<List<String>> getRemoteExecutableWhitelist() async {
    return _registry.withLockReadOnly((registry) async {
      return registry.remoteAccess.executableWhitelist;
    });
  }

  /// Set the executable whitelist (glob patterns).
  Future<void> setRemoteExecutableWhitelist(List<String> patterns) async {
    await _registry.withLock((registry) async {
      registry.remoteAccess = registry.remoteAccess.copyWith(
        executableWhitelist: patterns,
      );
    });
  }

  /// Get the current executable blacklist.
  Future<List<String>> getRemoteExecutableBlacklist() async {
    return _registry.withLockReadOnly((registry) async {
      return registry.remoteAccess.executableBlacklist;
    });
  }

  /// Set the executable blacklist (glob patterns).
  Future<void> setRemoteExecutableBlacklist(List<String> patterns) async {
    await _registry.withLock((registry) async {
      registry.remoteAccess = registry.remoteAccess.copyWith(
        executableBlacklist: patterns,
      );
    });
  }

  // --- Standalone / Partner Configuration ---

  /// Enable or disable standalone mode (no partner monitoring).
  Future<void> setStandaloneMode(bool enabled) async {
    await _registry.withLock((registry) async {
      registry.standaloneMode = enabled;
    });
  }

  /// Get current standalone mode setting.
  Future<bool> isStandaloneMode() async {
    return _registry.withLockReadOnly((registry) async {
      return registry.standaloneMode;
    });
  }

  /// Get partner discovery configuration.
  Future<PartnerDiscoveryConfig> getPartnerDiscoveryConfig() async {
    return _registry.withLockReadOnly((registry) async {
      return registry.partnerDiscovery;
    });
  }

  /// Set partner discovery configuration.
  Future<void> setPartnerDiscoveryConfig(PartnerDiscoveryConfig config) async {
    await _registry.withLock((registry) async {
      registry.partnerDiscovery = config;
    });
  }

  // --- Monitor Control ---

  /// Restart the ProcessMonitor itself.
  /// This sets a flag that the monitor will pick up.
  Future<void> restartMonitor() async {
    // Create a restart signal file
    final signalFile = File(path.join(directory, 'restart_$instanceId.signal'));
    await signalFile.writeAsString(DateTime.now().toIso8601String());
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

/// Resolves the default directory based on context.
String _resolveDefaultDirectory() {
  // In VS Code context: workspace root
  // Outside VS Code: user home directory
  final vsCodeWorkspace = Platform.environment['VSCODE_WORKSPACE_FOLDER'];
  if (vsCodeWorkspace != null) {
    return path.join(vsCodeWorkspace, '.tom', 'process_monitor');
  }
  return path.join(
    _resolveHomeDirectory(),
    '.tom',
    'process_monitor',
  );
}
