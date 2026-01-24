import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'models/monitor_status.dart';
import 'models/partner_discovery_config.dart';
import 'models/process_entry.dart';
import 'models/process_state.dart';
import 'models/registry.dart';
import 'models/restart_policy.dart';
import 'services/aliveness_checker.dart';
import 'services/aliveness_server.dart';
import 'services/log_manager.dart';
import 'services/process_control.dart';
import 'services/registry_service.dart';
import 'http/remote_api_server.dart';

/// ProcessMonitor daemon that manages process lifecycles.
class ProcessMonitor {
  /// Directory containing registry and lock files.
  final String directory;

  /// ProcessMonitor instance ID.
  final String instanceId;

  /// PID of the watcher process (if started by watcher).
  final int? watcherPid;

  late final RegistryService _registryService;
  late final ProcessControl _processControl;
  late final LogManager _logManager;
  late final AlivenessChecker _alivenessChecker;

  AlivenessServer? _alivenessServer;
  RemoteApiServer? _remoteApiServer;

  bool _running = false;
  DateTime? _startedAt;
  Timer? _monitorTimer;
  bool _restartRequested = false;

  // Partner discovery state
  String? _partnerStatus;
  int? _partnerPid;
  String? _partnerInstanceId;

  /// Creates a ProcessMonitor.
  ProcessMonitor({
    String? directory,
    this.instanceId = 'default',
    this.watcherPid,
  }) : directory = directory ?? _resolveDefaultDirectory() {
    _registryService = RegistryService(
      directory: this.directory,
      instanceId: instanceId,
    );
    _processControl = ProcessControl(
      logDirectory: this.directory,
      logger: _log,
    );
    _logManager = LogManager(
      baseDirectory: this.directory,
      instanceId: instanceId,
    );
    _alivenessChecker = AlivenessChecker();
  }

  /// Whether the monitor is running.
  bool get isRunning => _running;

  /// Starts the ProcessMonitor.
  Future<void> start() async {
    if (_running) return;

    _running = true;
    _startedAt = DateTime.now();

    // 1. Initialize logging
    await _logManager.initialize();
    _log('========================================');
    _log('ProcessMonitor Started');
    _log('Time: ${DateTime.now().toIso8601String()}');
    _log('Instance: $instanceId');
    _log('PID: $pid');
    _log('========================================');

    // 2. Initialize registry
    await _registryService.initialize();
    final registry = await _registryService.load();

    // 3. Record watcher info if started by watcher
    if (watcherPid != null) {
      registry.watcherInfo = WatcherInfo(
        watcherPid: watcherPid!,
        watcherInstanceId: 'watcher',
        watcherAlivenessPort: 5682,
      );
      await _registryService.save(registry);
    }

    // 4. Partner discovery (if not in standalone mode)
    if (!registry.standaloneMode) {
      await _discoverPartner(registry);
    }

    // 5. Detect crashed processes (were running but stale PIDs)
    await _detectCrashedProcesses(registry);

    // 6. Log configuration summary
    _logConfigSummary(registry);

    // 7. Start aliveness server
    if (registry.alivenessServer.enabled) {
      _alivenessServer = AlivenessServer(
        port: registry.alivenessServer.port,
        getStatus: _getStatus,
      );
      await _alivenessServer!.start();
      _log('Aliveness server started on port ${registry.alivenessServer.port}');
    }

    // 8. Start remote API server if enabled
    if (registry.remoteAccess.startRemoteAccess) {
      await _startRemoteServer(registry.remoteAccess.remotePort);
    }

    // 9. Start autostart processes
    await _startAutostartProcesses(registry);

    // 10. Begin monitoring loop
    _startMonitoringLoop(registry.monitorIntervalMs);

    _log('ProcessMonitor initialization complete');
  }

  /// Stops the ProcessMonitor.
  Future<void> stop() async {
    if (!_running) return;

    _log('ProcessMonitor stopping...');
    _running = false;
    _monitorTimer?.cancel();

    // Stop all managed processes
    final registry = await _registryService.load();
    for (final process in registry.processes.values) {
      if (process.pid != null && process.state == ProcessState.running) {
        _log('Stopping ${process.id}...');
        await _processControl.stopProcessGracefully(process.pid!);
        process.pid = null;
        process.state = ProcessState.stopped;
        process.lastStoppedAt = DateTime.now();
      }
    }
    await _registryService.save(registry);

    // Stop servers
    await _remoteApiServer?.stop();
    await _alivenessServer?.stop();

    // Close log
    _log('ProcessMonitor stopped');
    await _logManager.close();

    _alivenessChecker.dispose();
  }

  /// Restarts the ProcessMonitor.
  Future<void> restartSelf() async {
    _log('Self-restart requested, stopping HTTP servers...');

    // 1. Stop HTTP servers to release ports
    await _alivenessServer?.stop();
    await _remoteApiServer?.stop();

    // 2. Wait for ports to fully release
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // 3. Spawn new instance in detached mode
    final executable = Platform.resolvedExecutable;
    final args = Platform.executableArguments;

    _log('Spawning new instance: $executable ${args.join(' ')}');

    await Process.start(
      executable,
      args,
      mode: ProcessStartMode.detached,
    );

    // 4. Give new instance time to start
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // 5. Exit current process
    _log('Exiting current instance');
    exit(0);
  }

  Future<void> _startRemoteServer(int port) async {
    _remoteApiServer = RemoteApiServer(
      port: port,
      registryService: _registryService,
      processControl: _processControl,
      getStatus: _getStatus,
      onRestartRequested: () async {
        _restartRequested = true;
      },
      logger: _log,
    );
    await _remoteApiServer!.start();
    _log('Remote API server started on port $port');
  }

  Future<void> _detectCrashedProcesses(ProcessRegistry registry) async {
    for (final process in registry.processes.values) {
      if (process.state == ProcessState.running && process.pid != null) {
        if (!await _processControl.isProcessAlive(process.pid!)) {
          _log('Detected crashed process: ${process.id} (PID ${process.pid} no longer alive)');
          process.state = ProcessState.crashed;
          process.pid = null;
          process.lastStoppedAt = DateTime.now();
        }
      }
    }
    await _registryService.save(registry);
  }

  void _logConfigSummary(ProcessRegistry registry) {
    _log('');
    _log('Registered Processes (${registry.processes.length}):');
    _log('');

    var index = 1;
    for (final process in registry.processes.values) {
      final args = process.args.isEmpty ? '' : ' ${process.args.join(' ')}';
      final stateNote = process.autostart && process.enabled
          ? 'starting'
          : 'manual start required';

      _log('[$index] ${process.name}');
      _log('    ID:         ${process.id}');
      _log('    Command:    ${process.command}$args');
      _log('    Autostart:  ${process.autostart}');
      _log('    Enabled:    ${process.enabled}');
      _log('    State:      ${process.state.name} -> $stateNote');
      _log('');
      index++;
    }

    _log('========================================');
    _log('Starting autostart processes...');
    _log('========================================');
  }

  Future<void> _startAutostartProcesses(ProcessRegistry registry) async {
    for (final process in registry.processes.values) {
      if (process.enabled && process.autostart) {
        await _startProcess(process);
      }
    }
    await _registryService.save(registry);
  }

  void _startMonitoringLoop(int intervalMs) {
    _monitorTimer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      (_) => _monitoringTick(),
    );
  }

  Future<void> _monitoringTick() async {
    if (!_running) return;

    // Check for restart signal
    if (_restartRequested) {
      _restartRequested = false;
      await restartSelf();
      return;
    }

    // Check for restart signal file
    final signalFile = File(path.join(directory, 'restart_$instanceId.signal'));
    if (await signalFile.exists()) {
      await signalFile.delete();
      await restartSelf();
      return;
    }

    await _registryService.withLock((registry) async {
      // Check remote access setting changes
      if (registry.remoteAccess.startRemoteAccess &&
          _remoteApiServer?.isRunning != true) {
        await _startRemoteServer(registry.remoteAccess.remotePort);
      } else if (!registry.remoteAccess.startRemoteAccess &&
          _remoteApiServer?.isRunning == true) {
        await _remoteApiServer?.stop();
        _remoteApiServer = null;
        _log('Remote API server stopped');
      }

      // Update partner status periodically (if not standalone)
      if (!registry.standaloneMode) {
        await _updatePartnerStatus(registry.partnerDiscovery);
      }

      // Monitor each process
      for (final process in registry.processes.values) {
        await _monitorProcess(process, registry);
      }
    });
  }

  /// Updates the partner status during monitoring.
  Future<void> _updatePartnerStatus(PartnerDiscoveryConfig config) async {
    if (config.partnerStatusUrl == null) return;

    final statusData = await _alivenessChecker.fetchStatus(
      config.partnerStatusUrl!,
      timeout: const Duration(seconds: 2),
    );

    if (statusData != null) {
      _partnerStatus = statusData['state'] as String? ?? 'running';
      _partnerPid = statusData['pid'] as int?;
    } else {
      _partnerStatus = 'stopped';
      _partnerPid = null;
    }
  }

  Future<void> _monitorProcess(
    ProcessEntry process,
    ProcessRegistry registry,
  ) async {
    final policy = process.restartPolicy ?? RestartPolicy.defaultPolicy;

    switch (process.state) {
      case ProcessState.running:
        // Check if still alive
        if (process.pid != null) {
          if (!await _processControl.isProcessAlive(process.pid!)) {
            await _handleProcessCrash(process);
            return;
          }

          // Check HTTP aliveness if configured
          if (process.alivenessCheck?.enabled == true) {
            final alive = await _alivenessChecker.checkAlive(
              process.alivenessCheck!.url,
              timeout: Duration(milliseconds: process.alivenessCheck!.timeoutMs),
            );

            if (!alive) {
              process.consecutiveFailures++;
              if (process.consecutiveFailures >=
                  process.alivenessCheck!.consecutiveFailuresRequired) {
                _log(
                  'Process ${process.id} failed aliveness check '
                  '${process.consecutiveFailures} times',
                );
                await _handleProcessCrash(process);
                return;
              }
            } else {
              process.consecutiveFailures = 0;
            }
          }

          // Check for restart counter reset
          if (process.restartAttempts > 0 && process.lastStartedAt != null) {
            final stableTime = DateTime.now().difference(process.lastStartedAt!);
            if (stableTime.inMilliseconds > policy.resetAfterMs) {
              process.restartAttempts = 0;
              _log('Reset restart counter for ${process.id} after stable running');
            }
          }
        }

      case ProcessState.starting:
        // Start the process
        await _startProcess(process);

      case ProcessState.crashed:
        if (process.enabled) {
          await _attemptRestart(process, policy);
        }

      case ProcessState.retrying:
        if (process.enabled) {
          await _attemptIndefiniteRetry(process, policy);
        }

      case ProcessState.stopped:
      case ProcessState.stopping:
      case ProcessState.disabled:
      case ProcessState.failed:
        // Nothing to do
        break;
    }
  }

  Future<void> _handleProcessCrash(ProcessEntry process) async {
    _log('Process ${process.id} crashed');
    process.state = ProcessState.crashed;
    process.pid = null;
    process.lastStoppedAt = DateTime.now();
  }

  Future<void> _startProcess(ProcessEntry process) async {
    try {
      // Clean up old logs
      await _logManager.cleanupProcessLogs(process.id);

      // Start the process
      final processPid = await _processControl.startProcess(process);

      process.pid = processPid;
      process.lastStartedAt = DateTime.now();
      process.consecutiveFailures = 0;

      // Verify startup if configured
      if (process.alivenessCheck?.startupCheck?.enabled == true) {
        await _verifyStartup(process);
      } else {
        process.state = ProcessState.running;
      }

      _log('Process ${process.id} started with PID $processPid');
    } catch (e) {
      _log('Failed to start ${process.id}: $e');
      process.state = ProcessState.crashed;
    }
  }

  Future<void> _verifyStartup(ProcessEntry process) async {
    final check = process.alivenessCheck!.startupCheck!;

    await Future<void>.delayed(Duration(milliseconds: check.initialDelayMs));

    for (var attempt = 0; attempt < check.maxAttempts; attempt++) {
      if (await _alivenessChecker.checkAlive(
        process.alivenessCheck!.url,
        timeout: Duration(milliseconds: process.alivenessCheck!.timeoutMs),
      )) {
        process.state = ProcessState.running;
        _log('Process ${process.id} started successfully after ${attempt + 1} checks');

        // Fetch PID from statusUrl if configured
        await _fetchProcessPid(process);

        return;
      }
      await Future<void>.delayed(Duration(milliseconds: check.checkIntervalMs));
    }

    // Startup failed
    _log(
      'Process ${process.id} failed startup health check after '
      '${check.maxAttempts} attempts',
    );

    if (process.pid != null) {
      await _processControl.stopProcess(process.pid!, force: true);
      process.pid = null;
    }

    switch (check.failAction) {
      case 'restart':
        process.state = ProcessState.crashed;
      case 'disable':
        process.enabled = false;
        process.state = ProcessState.disabled;
      case 'fail':
        process.state = ProcessState.failed;
    }
  }

  Future<void> _attemptRestart(ProcessEntry process, RestartPolicy policy) async {
    // Check if max attempts exceeded
    if (process.restartAttempts >= policy.maxAttempts) {
      if (policy.retryIndefinitely) {
        process.state = ProcessState.retrying;
        _log('Process ${process.id} entering indefinite retry mode');
      } else {
        process.state = ProcessState.failed;
        _log('Process ${process.id} failed: max restart attempts exceeded');
      }
      return;
    }

    // Calculate backoff delay
    final backoffIndex = process.restartAttempts.clamp(
      0,
      policy.backoffIntervalsMs.length - 1,
    );
    final backoffMs = policy.backoffIntervalsMs[backoffIndex];

    final timeSinceCrash = DateTime.now().difference(
      process.lastStoppedAt ?? DateTime.now(),
    );

    if (timeSinceCrash.inMilliseconds < backoffMs) {
      // Still in backoff period
      return;
    }

    // Attempt restart
    process.restartAttempts++;
    _log('Restarting ${process.id} (attempt ${process.restartAttempts})');

    await _startProcess(process);
  }

  Future<void> _attemptIndefiniteRetry(
    ProcessEntry process,
    RestartPolicy policy,
  ) async {
    final timeSinceCrash = DateTime.now().difference(
      process.lastStoppedAt ?? DateTime.now(),
    );

    if (timeSinceCrash.inMilliseconds < policy.indefiniteIntervalMs) {
      // Still waiting for next retry
      return;
    }

    _log('Indefinite retry for ${process.id}');
    process.lastStoppedAt = DateTime.now(); // Reset timer

    await _startProcess(process);
  }

  Future<MonitorStatus> _getStatus() async {
    final registry = await _registryService.load();
    final processes = registry.processes;

    final runningCount = processes.values
        .where((p) => p.state == ProcessState.running)
        .length;

    return MonitorStatus(
      instanceId: instanceId,
      pid: pid,
      startedAt: _startedAt ?? DateTime.now(),
      uptime: _startedAt != null
          ? DateTime.now().difference(_startedAt!).inSeconds
          : 0,
      state: _running ? 'running' : 'stopping',
      standaloneMode: registry.standaloneMode,
      partnerInstanceId: _partnerInstanceId,
      partnerStatus: _partnerStatus,
      partnerPid: _partnerPid,
      managedProcessCount: processes.length,
      runningProcessCount: runningCount,
    );
  }

  /// Discovers and optionally starts the partner instance.
  Future<void> _discoverPartner(ProcessRegistry registry) async {
    final config = registry.partnerDiscovery;
    _partnerInstanceId = config.partnerInstanceId;

    if (!config.discoveryOnStartup) {
      _log('Partner discovery disabled');
      return;
    }

    _log('Discovering partner instance: ${config.partnerInstanceId}');

    // Try to contact partner via aliveness endpoint
    if (config.partnerStatusUrl != null) {
      final statusData = await _alivenessChecker.fetchStatus(
        config.partnerStatusUrl!,
        timeout: const Duration(seconds: 2),
      );

      if (statusData != null) {
        _partnerStatus = statusData['state'] as String? ?? 'running';
        _partnerPid = statusData['pid'] as int?;
        _log(
          'Partner found: ${config.partnerInstanceId} '
          '(PID: $_partnerPid, status: $_partnerStatus)',
        );
        return;
      }
    }

    // Partner not found
    _partnerStatus = 'stopped';
    _partnerPid = null;
    _log('Partner not found: ${config.partnerInstanceId}');

    if (config.startPartnerIfMissing) {
      _log('Starting partner instance...');
      // Start the watcher/default partner
      await _startPartnerInstance(config);
    }
  }

  /// Starts the partner ProcessMonitor instance.
  Future<void> _startPartnerInstance(PartnerDiscoveryConfig config) async {
    final executable = Platform.resolvedExecutable;
    final partnerInstanceId = config.partnerInstanceId ?? 'watcher';

    // Start partner as detached process
    final args = [
      ...Platform.executableArguments,
      '--instance=$partnerInstanceId',
    ];

    _log('Starting partner: $executable ${args.join(' ')}');

    try {
      await Process.start(
        executable,
        args,
        mode: ProcessStartMode.detached,
      );

      // Wait for partner to start
      await Future<void>.delayed(const Duration(seconds: 2));

      // Re-check partner status
      if (config.partnerStatusUrl != null) {
        final statusData = await _alivenessChecker.fetchStatus(
          config.partnerStatusUrl!,
          timeout: const Duration(seconds: 2),
        );

        if (statusData != null) {
          _partnerStatus = statusData['state'] as String? ?? 'running';
          _partnerPid = statusData['pid'] as int?;
          _log('Partner started successfully (PID: $_partnerPid)');
        }
      }
    } catch (e) {
      _log('Failed to start partner: $e');
    }
  }

  /// Fetches PID from statusUrl after process startup.
  Future<void> _fetchProcessPid(ProcessEntry process) async {
    if (process.alivenessCheck?.statusUrl == null) return;

    final fetchedPid = await _alivenessChecker.fetchPid(
      process.alivenessCheck!.statusUrl!,
      timeout: Duration(milliseconds: process.alivenessCheck!.timeoutMs),
    );

    if (fetchedPid != null) {
      _log('Discovered PID $fetchedPid for ${process.id} via statusUrl');
      process.pid = fetchedPid;
    }
  }

  void _log(String message) {
    _logManager.info(message);
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
