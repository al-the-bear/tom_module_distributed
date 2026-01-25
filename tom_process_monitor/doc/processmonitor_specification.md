# ProcessMonitor Specification

This document specifies the ProcessMonitor component, which provides automated process lifecycle management with file-based configuration, local and remote client APIs for process control, and mutual monitoring capabilities.

---

## Overview

The ProcessMonitor is a daemon-like component that:

1. Maintains a file-based registry of managed processes
2. Automatically starts registered processes on initialization (if autostart is enabled)
3. Monitors running processes and restarts them if they crash
4. Provides a local client API for process registration and control
5. Provides an HTTP/REST remote API for remote process management
6. Uses file locking to ensure safe concurrent access
7. Supports multiple instances (default + watcher) for mutual monitoring
8. Supports optional HTTP aliveness checks for managed processes

```
+------------------------------------------------------------------+
|                        PROCESSMONITOR                             |
|                                                                   |
|  Instance ID: "default" or "watcher"                              |
|  Configuration: .tom/process_monitor/processes_{id}.json          |
|  Lock file:     .tom/process_monitor/processes_{id}.lock          |
|  Logs:          .tom/process_monitor/{id}_logs/                   |
|                                                                   |
|  +-------------------------------------------------------------+  |
|  |                    PROCESS REGISTRY                         |  |
|  |                                                             |  |
|  |  Process A: local,  autostart=true,  enabled=true          |  |
|  |  Process B: remote, autostart=false, enabled=true          |  |
|  |  Process C: local,  autostart=true,  enabled=false         |  |
|  +-------------------------------------------------------------+  |
|                                                                   |
|  +-------------------------------------------------------------+  |
|  |                     LOCAL CLIENT API                        |  |
|  |                                                             |  |
|  |  register() | deregister() | enable() | disable()          |  |
|  |  setAutostart() | start() | stop() | restart()             |  |
|  |  setRemoteAccess() | get/setWhitelist() | get/setBlacklist()|  |
|  +-------------------------------------------------------------+  |
|                                                                   |
|  +-------------------------------------------------------------+  |
|  |                    REMOTE HTTP API                          |  |
|  |  Port: 19881 (configurable)                                  |  |
|  |                                                             |  |
|  |  POST /processes | DELETE /processes/{id}                   |  |
|  |  POST /processes/{id}/start | POST /processes/{id}/stop    |  |
|  |  GET /processes | GET /processes/{id}                       |  |
|  +-------------------------------------------------------------+  |
|                                                                   |
|  +-------------------------------------------------------------+  |
|  |                   ALIVENESS SERVER                          |  |
|  |  Port: 19883 (default) or 19884 (watcher)                     |  |
|  |                                                             |  |
|  |  GET /alive -> "OK"                                         |  |
|  +-------------------------------------------------------------+  |
+------------------------------------------------------------------+
```

---

## File Structure

### Default Directory

All ProcessMonitor files are stored in:

```
.tom/process_monitor/
```

**Directory Resolution:**

By default, ProcessMonitor uses `~/.tom/process_monitor/` in the user's home directory.
Use the `--directory` command-line option to specify a custom location.

### Files

Files are named with the ProcessMonitor instance ID (default: `default`).

| File | Purpose |
|------|---------|
| `processes_{id}.json` | Process registry containing all registered processes and configuration |
| `processes_{id}.lock` | Lock file for safe concurrent access to the registry |

### ProcessMonitor Instance Logs

The ProcessMonitor itself logs to timestamped files:

```
.tom/process_monitor/{instance_id}_logs/{timestamp}_{instance_id}.log
```

**Example:**

```
.tom/process_monitor/
    default_logs/
        20260124_103000_default.log
        20260124_092000_default.log
        20260124_080000_default.log
    watcher_logs/
        20260124_103005_watcher.log
        20260124_092005_watcher.log
```

**Log Rotation:**

- A new log file is created each time ProcessMonitor starts
- Timestamp format: `YYYYMMDD_HHMMSS`
- On startup, old log files are cleaned up
- Only the **last 10 log files** are retained
- Oldest files are deleted first

### Process Log Directory

Managed process stdout/stderr output is captured and stored in a consolidated log location:

```
.tom/process_monitor/{instance_id}_logs/{process_id}/{start_timestamp}/
```

**Example:**

```
.tom/process_monitor/
    default_logs/
        tom-bridge/
            20260124_103000/
                stdout.log
                stderr.log
            20260124_092000/
                stdout.log
                stderr.log
        my-api/
            20260124_110000/
                stdout.log
                stderr.log
```

**Log Rotation:**

- A new log folder is created each time a process starts
- When a process starts, old log folders are cleaned up
- Only the **last 10 log folders** are retained per process
- Oldest folders are deleted first

**Examples:**

- Default instance registry: `processes_default.json`, `processes_default.lock`
- Watcher instance registry: `processes_watcher.json`, `processes_watcher.lock`
- Default instance log: `default_logs/20260124_103000_default.log`
- Watcher instance log: `watcher_logs/20260124_103005_watcher.log`
- Process logs: `default_logs/tom-bridge/20260124_103000/stdout.log`

---

## Process Registry Schema

The registry file (`processes_{id}.json`) contains the complete configuration of all managed processes and global settings.

### Registry Structure

```json
{
  "version": 1,
  "lastModified": "2026-01-24T10:30:00.000Z",
  "instanceId": "default",
  "monitorIntervalMs": 5000,
  "standaloneMode": false,
  "partnerDiscovery": {
    "partnerInstanceId": "watcher",
    "partnerAlivenessPort": 19884,
    "partnerStatusUrl": "http://localhost:19884/status",
    "discoveryOnStartup": true,
    "startPartnerIfMissing": false
  },
  "remoteAccess": {
    "startRemoteAccess": true,
    "remotePort": 19881,
    "trustedHosts": ["localhost", "127.0.0.1", "::1"],
    "allowRemoteRegister": true,
    "allowRemoteDeregister": true,
    "allowRemoteStart": true,
    "allowRemoteStop": true,
    "allowRemoteDisable": true,
    "allowRemoteAutostart": true,
    "allowRemoteMonitorRestart": false,
    "executableWhitelist": [
      "/opt/tom/bin/*",
      "/usr/local/bin/my-*"
    ],
    "executableBlacklist": [
      "/bin/rm",
      "/bin/sudo",
      "**/*.sh"
    ]
  },
  "alivenessServer": {
    "enabled": true,
    "port": 19883
  },
  "watcherInfo": {
    "watcherPid": 54321,
    "watcherInstanceId": "watcher",
    "watcherAlivenessPort": 19884
  },
  "processes": {
    "process-id-1": {
      "id": "process-id-1",
      "name": "My Service",
      "command": "/usr/bin/my-service",
      "args": ["--port", "8080"],
      "workingDirectory": "/opt/my-service",
      "environment": {
        "NODE_ENV": "production"
      },
      "autostart": true,
      "enabled": true,
      "isRemote": false,
      "restartPolicy": {
        "maxAttempts": 5,
        "backoffIntervalsMs": [1000, 2000, 5000, 10000, 30000],
        "resetAfterMs": 300000,
        "retryIndefinitely": true,
        "indefiniteIntervalMs": 21600000
      },
      "alivenessCheck": {
        "enabled": true,
        "url": "http://localhost:8080/health",
        "intervalMs": 3000,
        "timeoutMs": 2000,
        "consecutiveFailuresRequired": 2
      },
      "registeredAt": "2026-01-24T10:00:00.000Z",
      "lastStartedAt": "2026-01-24T10:30:00.000Z",
      "lastStoppedAt": null,
      "pid": 12345,
      "state": "running",
      "restartAttempts": 0
    }
  }
}
```

### Global Configuration Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `version` | int | 1 | Schema version |
| `lastModified` | ISO8601 | - | Last modification timestamp |
| `instanceId` | string | "default" | ProcessMonitor instance ID |
| `monitorIntervalMs` | int | 5000 | Monitoring loop interval in milliseconds |
| `standaloneMode` | bool | false | Disable partner (watcher) discovery and monitoring |
| `partnerDiscovery` | object | - | Partner instance discovery configuration |
| `remoteAccess` | object | - | Remote HTTP API configuration |
| `alivenessServer` | object | - | Aliveness HTTP server configuration |
| `watcherInfo` | object | null | Information about the watcher process (if applicable) |

### Partner Discovery Configuration

Used to discover and monitor the partner ProcessMonitor instance (default ↔ watcher).
Partner discovery is disabled when `standaloneMode: true` in the global configuration.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `partnerInstanceId` | string | (auto) | Partner instance ID ("watcher" for default, "default" for watcher) |
| `partnerAlivenessPort` | int | (auto) | Partner aliveness port (19884 for default→watcher, 19883 for watcher→default) |
| `partnerStatusUrl` | string | (auto) | URL to fetch partner status (e.g., `http://localhost:19884/status`) |
| `discoveryOnStartup` | bool | true | Attempt to discover partner on startup |
| `startPartnerIfMissing` | bool | false | Start partner if not found on startup |

### Remote Access Configuration

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `startRemoteAccess` | bool | false | Enable HTTP remote API |
| `remotePort` | int | 19881 | HTTP server port for remote API |
| `trustedHosts` | string[] | ["localhost", "127.0.0.1", "::1", "0.0.0.0"] | Hosts that bypass all permission checks. Supports patterns. |
| `allowRemoteRegister` | bool | true | Allow remote process registration |
| `allowRemoteDeregister` | bool | true | Allow remote process deregistration |
| `allowRemoteStart` | bool | true | Allow remote process start |
| `allowRemoteStop` | bool | true | Allow remote process stop |
| `allowRemoteDisable` | bool | true | Allow remote enable/disable |
| `allowRemoteAutostart` | bool | true | Allow remote autostart changes |
| `allowRemoteMonitorRestart` | bool | false | Allow remote ProcessMonitor restart |
| `executableWhitelist` | string[] | [] | Glob patterns for allowed executables. **Required for remote registration.** |
| `executableBlacklist` | string[] | [] | Glob patterns for blocked executables |

#### Trusted Hosts Patterns

The `trustedHosts` field supports:
- **Exact match**: `192.168.1.100`, `localhost`, `::1`
- **IP wildcards**: `192.168.1.*` (matches 192.168.1.0-255), `10.0.*.*` (matches 10.0.0.0-10.0.255.255)
- **Hostname wildcards**: `*.mydomain.com`, `server-*.local`

#### Executable Whitelist Requirement

**Security:** Remote process registration requires the command to match the executable whitelist. An empty whitelist **blocks all remote registrations** from non-trusted hosts.

Whitelist patterns use glob syntax:
- `/usr/bin/*` - any executable in /usr/bin
- `/opt/myapp/**` - recursive match in /opt/myapp
- `**/*.sh` - any shell script

### Aliveness Server Configuration

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | bool | true | Enable aliveness HTTP server |
| `port` | int | 19883/19884 | Aliveness server port (19883 for default, 19884 for watcher) |

### Watcher Info

| Field | Type | Description |
|-------|------|-------------|
| `watcherPid` | int | PID of the watcher process |
| `watcherInstanceId` | string | Instance ID of the watcher ("watcher") |
| `watcherAlivenessPort` | int | Aliveness port of the watcher |

### Process Entry Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique process identifier |
| `name` | string | Yes | Human-readable process name |
| `command` | string | Yes | Executable path or command |
| `args` | string[] | No | Command-line arguments |
| `workingDirectory` | string | No | Working directory for the process |
| `environment` | Map | No | Environment variables |
| `autostart` | bool | Yes | Start on ProcessMonitor initialization |
| `enabled` | bool | Yes | Whether the process can be started |
| `isRemote` | bool | Yes | Whether registered via remote API |
| `restartPolicy` | object | No | Restart behavior configuration |
| `alivenessCheck` | object | No | Optional HTTP aliveness check configuration |
| `registeredAt` | ISO8601 | Yes | When process was registered |
| `lastStartedAt` | ISO8601 | No | When process was last started |
| `lastStoppedAt` | ISO8601 | No | When process was last stopped |
| `pid` | int | No | Current process ID (if running) |
| `state` | enum | Yes | Current process state |
| `restartAttempts` | int | Yes | Current restart attempt count |

### Aliveness Check Configuration (Per Process)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | bool | false | Enable HTTP aliveness check |
| `url` | string | - | URL to check (e.g., `http://localhost:8080/health`) |
| `statusUrl` | string | null | URL to fetch process status/PID (e.g., `http://localhost:8080/status`) |
| `intervalMs` | int | 3000 | Check interval in milliseconds (during normal operation) |
| `timeoutMs` | int | 2000 | Request timeout in milliseconds |
| `consecutiveFailuresRequired` | int | 2 | Number of consecutive failures before declaring dead |
| `startupCheck` | object | null | Optional startup health verification |

**PID Discovery via statusUrl:**

If `statusUrl` is configured, after starting a process ProcessMonitor will:
1. Wait for the startup health check to pass (if configured)
2. Send `GET` request to `statusUrl`
3. Parse response JSON for `pid` field
4. Update the process entry with discovered PID
5. If request fails, no retry - use PID from process start if available

### Startup Health Check Configuration

When a process with aliveness checking starts, optionally verify it becomes healthy:

```json
{
  "alivenessCheck": {
    "enabled": true,
    "url": "http://localhost:8080/health",
    "intervalMs": 3000,
    "timeoutMs": 2000,
    "consecutiveFailuresRequired": 2,
    "startupCheck": {
      "enabled": true,
      "initialDelayMs": 2000,
      "checkIntervalMs": 1000,
      "maxAttempts": 30,
      "failAction": "restart"
    }
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | bool | false | Enable startup health verification |
| `initialDelayMs` | int | 2000 | Wait before first check (allow process to initialize) |
| `checkIntervalMs` | int | 1000 | Interval between startup checks |
| `maxAttempts` | int | 30 | Maximum check attempts before declaring failure |
| `failAction` | enum | "restart" | Action on failure: "restart", "disable", or "fail" |

**Startup Check Behavior:**

1. Process is started, state set to `starting`
2. Wait `initialDelayMs` (e.g., 2 seconds)
3. Every `checkIntervalMs` (e.g., 1 second), check aliveness URL
4. If check succeeds: state transitions to `running`
5. If `maxAttempts` reached without success:
   - `restart`: Kill process, increment restart counter, try again
   - `disable`: Kill process, set `enabled: false`, state to `disabled`
   - `fail`: Kill process, state to `failed`

```dart
Future<void> _verifyStartup(ProcessEntry process) async {
  final check = process.alivenessCheck?.startupCheck;
  if (check == null || !check.enabled) {
    // No startup check, immediately mark as running
    process.state = ProcessState.running;
    return;
  }
  
  await Future.delayed(Duration(milliseconds: check.initialDelayMs));
  
  for (int attempt = 0; attempt < check.maxAttempts; attempt++) {
    if (await _checkAliveness(process)) {
      process.state = ProcessState.running;
      _log('Process ${process.id} started successfully after ${attempt + 1} checks');
      return;
    }
    await Future.delayed(Duration(milliseconds: check.checkIntervalMs));
  }
  
  // Startup failed
  _log('Process ${process.id} failed startup health check after ${check.maxAttempts} attempts');
  await _killProcess(process);
  
  switch (check.failAction) {
    case 'restart':
      process.state = ProcessState.crashed;
      // Will be restarted by normal restart logic
      break;
    case 'disable':
      process.enabled = false;
      process.state = ProcessState.disabled;
      break;
    case 'fail':
      process.state = ProcessState.failed;
      break;
  }
}
```

### Process States

| State | Description |
|-------|-------------|
| `stopped` | Process is not running (normal state) |
| `starting` | Process is being started |
| `running` | Process is running normally |
| `stopping` | Process is being stopped |
| `crashed` | Process exited unexpectedly |
| `disabled` | Process is disabled and will not start |
| `failed` | Process failed to start after max restart attempts |
| `retrying` | Process in indefinite retry mode (after max attempts) |

### Restart Policy

```json
{
  "maxAttempts": 5,
  "backoffIntervalsMs": [1000, 2000, 5000, 10000, 30000],
  "resetAfterMs": 300000,
  "retryIndefinitely": true,
  "indefiniteIntervalMs": 21600000
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `maxAttempts` | int | 5 | Maximum restart attempts before marking as failed |
| `backoffIntervalsMs` | int[] | [1000, 2000, 5000] | Backoff delays between restart attempts |
| `resetAfterMs` | int | 300000 | Reset attempt counter after this duration of stable running |
| `retryIndefinitely` | bool | false | Continue retrying after maxAttempts at a longer interval |
| `indefiniteIntervalMs` | int | 21600000 | Retry interval in indefinite mode (default: 6 hours) |

---

## Executable Filtering

Remote process registration is filtered using whitelist and blacklist patterns.

### Filter Logic

```
1. If whitelist is non-empty:
   - Executable must match at least one whitelist pattern
   - If no match, reject

2. If blacklist is non-empty:
   - If executable matches any blacklist pattern, reject

3. If both checks pass, allow registration
```

### Glob Pattern Examples

| Pattern | Matches |
|---------|---------|
| `/opt/tom/bin/*` | All files in `/opt/tom/bin/` |
| `/usr/local/bin/my-*` | Files starting with `my-` in `/usr/local/bin/` |
| `**/*.sh` | All shell scripts in any directory |
| `/bin/rm` | Exact match for `/bin/rm` |
| `/opt/**/node` | `node` executable in any subdirectory of `/opt/` |

---

## Lock File Protocol

The lock file ensures safe concurrent access to the registry file.

### Lock File Location

```
.tom/process_monitor/processes_{id}.lock
```

### Lock File Format

```json
{
  "lockedBy": "process-monitor-instance-abc123",
  "lockedAt": "2026-01-24T10:30:00.000Z",
  "pid": 12345,
  "operation": "write"
}
```

### Lock Acquisition Protocol

1. **Attempt Lock**: Create lock file with exclusive access
2. **Check Staleness**: If lock exists, check if holder is still alive (via PID)
3. **Timeout**: Wait up to `lockTimeoutMs` (default: 5000ms) for lock
4. **Force Release**: If lock is stale (holder dead), remove and retry

### Lock Operations

| Operation | Lock Type | Description |
|-----------|-----------|-------------|
| Read registry | Shared | Multiple readers allowed |
| Write registry | Exclusive | Single writer, no readers |
| Start/stop process | Exclusive | Modifies registry state |

### Dart Implementation Pattern

```dart
class RegistryLock {
  final String lockPath;
  final Duration timeout;
  
  Future<T> withLock<T>(Future<T> Function() operation) async {
    await _acquireLock();
    try {
      return await operation();
    } finally {
      await _releaseLock();
    }
  }
  
  Future<void> _acquireLock() async {
    final deadline = DateTime.now().add(timeout);
    
    while (DateTime.now().isBefore(deadline)) {
      try {
        final lockFile = File(lockPath);
        
        // Check for stale lock
        if (await lockFile.exists()) {
          final content = jsonDecode(await lockFile.readAsString());
          final holderPid = content['pid'] as int;
          
          if (!await _isProcessAlive(holderPid)) {
            await lockFile.delete();
          } else {
            await Future.delayed(Duration(milliseconds: 50));
            continue;
          }
        }
        
        // Create lock file atomically
        await lockFile.writeAsString(jsonEncode({
          'lockedBy': _instanceId,
          'lockedAt': DateTime.now().toIso8601String(),
          'pid': pid,
          'operation': 'write',
        }));
        
        return;
      } catch (e) {
        await Future.delayed(Duration(milliseconds: 50));
      }
    }
    
    throw LockTimeoutException('Failed to acquire lock within $timeout');
  }
}
```

---

## ProcessMonitor Lifecycle

### Initialization Sequence

```
ProcessMonitor.start(instanceId: "default")
    |
    +---> 1. ACQUIRE LOCK
    |         |
    |         +---> Create lock file (processes_{id}.lock)
    |         +---> Record PID and instance ID
    |
    +---> 2. CREATE LOG FILE WITH ROTATION
    |         |
    |         +---> Create {id}_logs/{timestamp}_{id}.log
    |         +---> Delete oldest log files if more than 10 exist
    |
    +---> 3. LOAD REGISTRY
    |         |
    |         +---> Read processes_{id}.json
    |         +---> Validate schema
    |         +---> Log configuration summary
    |
    +---> 4. DETECT RESTART
    |         |
    |         +---> Check for processes with state="running" but stale PIDs
    |         +---> These indicate ProcessMonitor crashed and restarted
    |         +---> Mark as "crashed" for restart processing
    |
    +---> 5. RESET RUNTIME STATE
    |         |
    |         +---> Clear stale PIDs
    |         +---> Update process states
    |
    +---> 6. START ALIVENESS SERVER
    |         |
    |         +---> If alivenessServer.enabled:
    |               Start HTTP server on configured port
    |               Respond to GET /alive with "OK"
    |
    +---> 7. START REMOTE API SERVER (if enabled)
    |         |
    |         +---> If remoteAccess.startRemoteAccess:
    |               Start HTTP server on remotePort (default 19881)
    |
    +---> 8. START AUTOSTART PROCESSES
    |         |
    |         +---> For each process where:
    |               - enabled == true
    |               - autostart == true
    |               Start the process
    |
    +---> 9. BEGIN MONITORING LOOP
              |
              +---> Every monitorIntervalMs (default 5000ms):
                    - Check process health (PID + optional aliveness)
                    - Restart crashed processes
                    - Update registry
```

### Configuration Dump on Startup

On startup, the ProcessMonitor writes a human-readable configuration summary to the log file:

```
========================================
ProcessMonitor Started
Time: 2026-01-24T10:30:00.000Z
Instance: process-monitor-abc123
PID: 12345
========================================

Registered Processes (3):

[1] my-service
    ID:         my-service-001
    Command:    /usr/bin/my-service --port 8080
    Autostart:  true
    Enabled:    true
    State:      stopped -> starting

[2] database
    ID:         postgres-main
    Command:    /usr/bin/postgres -D /var/lib/postgres
    Autostart:  true
    Enabled:    true
    State:      stopped -> starting

[3] worker
    ID:         worker-001
    Command:    /opt/worker/bin/worker
    Autostart:  false
    Enabled:    true
    State:      stopped (manual start required)

========================================
Starting autostart processes...
========================================
```

### Monitoring Loop

```dart
Future<void> _monitoringLoop() async {
  while (_running) {
    await _withLock(() async {
      final registry = await _loadRegistry();
      
      // Check remote access setting changes
      if (registry.remoteAccess.startRemoteAccess && !_remoteServerRunning) {
        await _startRemoteServer(registry.remoteAccess.remotePort);
      } else if (!registry.remoteAccess.startRemoteAccess && _remoteServerRunning) {
        await _stopRemoteServer();
      }
      
      for (final process in registry.processes.values) {
        if (process.state == ProcessState.running) {
          // Check PID
          if (!await _isProcessAlive(process.pid)) {
            await _handleProcessCrash(process);
            continue;
          }
          
          // Check HTTP aliveness (if configured)
          if (process.alivenessCheck?.enabled == true) {
            if (!await _checkAliveness(process)) {
              await _handleProcessCrash(process);
            }
          }
        }
        
        if (process.state == ProcessState.crashed && process.enabled) {
          await _attemptRestart(process);
        }
        
        if (process.state == ProcessState.retrying && process.enabled) {
          await _attemptIndefiniteRetry(process);
        }
      }
      
      await _saveRegistry(registry);
    });
    
    await Future.delayed(Duration(milliseconds: _monitorIntervalMs));
  }
}

Future<bool> _checkAliveness(ProcessEntry process) async {
  final check = process.alivenessCheck!;
  try {
    final response = await http.get(
      Uri.parse(check.url),
    ).timeout(Duration(milliseconds: check.timeoutMs));
    
    return response.statusCode == 200 && response.body.trim() == 'OK';
  } catch (e) {
    _log('Aliveness check failed for ${process.id}: $e');
    return false;
  }
}
```

### Shutdown Sequence

```
ProcessMonitor.stop()
    |
    +---> 1. STOP MONITORING
    |         |
    |         +---> Set _running = false
    |         +---> Wait for current loop iteration
    |
    +---> 2. STOP ALL MANAGED PROCESSES
    |         |
    |         +---> For each running process:
    |               - Send SIGTERM
    |               - Wait for graceful shutdown (10s)
    |               - Force SIGKILL if needed
    |         +---> Update states to "stopped"
    |
    +---> 3. STOP SERVERS
    |         |
    |         +---> Stop remote API server (if running)
    |         +---> Stop aliveness server
    |
    +---> 4. LOG SHUTDOWN
    |         |
    |         +---> Log shutdown message with timestamp
    |
    +---> 5. RELEASE LOCK
              |
              +---> Delete lock file
```

**Note**: Stopping the ProcessMonitor STOPS all managed processes. When the ProcessMonitor restarts, it will detect processes marked as "running" with stale PIDs and treat them as crashed (triggering restart if enabled).

---

## Local Client API

The local client API allows applications on the same machine to interact with the ProcessMonitor via the file-based registry.

### ProcessMonitorClient Class

```dart
/// Local client API for interacting with ProcessMonitor.
/// 
/// This client communicates via the file-based registry and does not
/// require direct connection to the ProcessMonitor daemon.
class ProcessMonitorClient {
  /// Directory containing registry and lock files.
  final String directory;
  
  /// ProcessMonitor instance ID.
  final String instanceId;
  
  /// Default: .tom/process_monitor, instanceId: "default"
  ProcessMonitorClient({
    String? directory,
    String instanceId = 'default',
  })  : directory = directory ?? _resolveDefaultDirectory(),
        instanceId = instanceId;
  
  // --- Registration ---
  
  /// Register a new local process with the monitor.
  Future<void> register(ProcessConfig config);
  
  /// Remove a process from the registry.
  /// Stops the process if running.
  Future<void> deregister(String processId);
  
  // --- Enable/Disable ---
  
  /// Enable a process (allows it to be started).
  Future<void> enable(String processId);
  
  /// Disable a process (stops it and prevents restart).
  Future<void> disable(String processId);
  
  // --- Autostart ---
  
  /// Set whether the process starts automatically.
  Future<void> setAutostart(String processId, bool autostart);
  
  // --- Process Control ---
  
  /// Start a process (if enabled).
  Future<void> start(String processId);
  
  /// Stop a process (does not disable it).
  /// Process will restart on next ProcessMonitor startup if autostart=true.
  Future<void> stop(String processId);
  
  /// Restart a process (stop then start).
  Future<void> restart(String processId);
  
  // --- Status ---
  
  /// Get status of a specific process.
  Future<ProcessStatus> getStatus(String processId);
  
  /// Get status of all registered processes.
  Future<Map<String, ProcessStatus>> getAllStatus();
  
  // --- Remote Access Configuration ---
  
  /// Enable or disable remote HTTP API access.
  Future<void> setRemoteAccess(bool enabled);
  
  /// Get current remote access configuration.
  Future<RemoteAccessConfig> getRemoteAccessConfig();
  
  /// Set remote access permissions.
  Future<void> setRemoteAccessPermissions({
    bool? allowRegister,
    bool? allowDeregister,
    bool? allowStart,
    bool? allowStop,
    bool? allowDisable,
    bool? allowAutostart,
    bool? allowMonitorRestart,
  });
  
  /// Set trusted hosts list.
  Future<void> setTrustedHosts(List<String> hosts);
  
  /// Get trusted hosts list.
  Future<List<String>> getTrustedHosts();
  
  // --- Executable Filtering ---
  
  /// Get the current executable whitelist.
  Future<List<String>> getRemoteExecutableWhitelist();
  
  /// Set the executable whitelist (glob patterns).
  Future<void> setRemoteExecutableWhitelist(List<String> patterns);
  
  /// Get the current executable blacklist.
  Future<List<String>> getRemoteExecutableBlacklist();
  
  /// Set the executable blacklist (glob patterns).
  Future<void> setRemoteExecutableBlacklist(List<String> patterns);
  
  // --- Standalone / Partner Configuration ---
  
  /// Enable or disable standalone mode (no partner monitoring).
  Future<void> setStandaloneMode(bool enabled);
  
  /// Get current standalone mode setting.
  Future<bool> isStandaloneMode();
  
  /// Get partner discovery configuration.
  Future<PartnerDiscoveryConfig> getPartnerDiscoveryConfig();
  
  /// Set partner discovery configuration.
  Future<void> setPartnerDiscoveryConfig(PartnerDiscoveryConfig config);
  
  // --- Monitor Control ---
  
  /// Restart the ProcessMonitor itself.
  /// Triggers: stop HTTP servers → spawn new instance → exit.
  Future<void> restartMonitor();
}

/// Resolves the default directory.
/// Uses the user's home directory (~/.tom/process_monitor/).
String _resolveDefaultDirectory() {
  final home = Platform.environment['HOME'] 
      ?? Platform.environment['USERPROFILE'] 
      ?? '.';
  return path.join(home, '.tom', 'process_monitor');
}
```

### ProcessConfig Class

```dart
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
  /// Default: true
  final bool autostart;
  
  /// Restart policy configuration.
  final RestartPolicy? restartPolicy;
  
  /// Optional HTTP aliveness check configuration.
  final AlivenessCheck? alivenessCheck;
  
  ProcessConfig({
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
}

/// Restart policy configuration.
class RestartPolicy {
  final int maxAttempts;
  final List<int> backoffIntervalsMs;
  final int resetAfterMs;
  final bool retryIndefinitely;
  final int indefiniteIntervalMs;
  
  RestartPolicy({
    this.maxAttempts = 5,
    this.backoffIntervalsMs = const [1000, 2000, 5000],
    this.resetAfterMs = 300000,
    this.retryIndefinitely = false,
    this.indefiniteIntervalMs = 21600000, // 6 hours
  });
}

/// HTTP aliveness check configuration.
class AlivenessCheck {
  final bool enabled;
  final String url;
  final String? statusUrl;
  final int intervalMs;
  final int timeoutMs;
  final int consecutiveFailuresRequired;
  final StartupCheck? startupCheck;
  
  AlivenessCheck({
    required this.enabled,
    required this.url,
    this.statusUrl,
    this.intervalMs = 3000,
    this.timeoutMs = 2000,
    this.consecutiveFailuresRequired = 2,
    this.startupCheck,
  });
}

/// Startup health check configuration.
class StartupCheck {
  final bool enabled;
  final int initialDelayMs;
  final int checkIntervalMs;
  final int maxAttempts;
  final String failAction;
  
  StartupCheck({
    this.enabled = true,
    this.initialDelayMs = 2000,
    this.checkIntervalMs = 1000,
    this.maxAttempts = 30,
    this.failAction = 'restart',
  });
}
```

### ProcessState Enum

```dart
/// Process lifecycle states.
enum ProcessState {
  /// Process is not running and hasn't been started.
  stopped,
  
  /// Process is in the process of starting.
  starting,
  
  /// Process is running normally.
  running,
  
  /// Process has crashed and may be restarted.
  crashed,
  
  /// Process is waiting for retry after crash.
  retrying,
  
  /// Process failed after exhausting restart attempts.
  failed,
  
  /// Process is disabled and cannot be started.
  disabled,
}
```

### ProcessStatus Class

```dart
/// Status information for a process.
class ProcessStatus {
  final String id;
  final String name;
  final ProcessState state;
  final bool enabled;
  final bool autostart;
  final bool isRemote;
  final int? pid;
  final DateTime? lastStartedAt;
  final DateTime? lastStoppedAt;
  final int restartAttempts;
}
```

### MonitorStatus Class

```dart
/// Status information for the ProcessMonitor instance.
class MonitorStatus {
  final String instanceId;
  final int pid;
  final DateTime startedAt;
  final int uptime;
  final String state;
  final bool standaloneMode;
  final String? partnerInstanceId;
  final String? partnerStatus;
  final int? partnerPid;
  final int managedProcessCount;
  final int runningProcessCount;
}
```

### PartnerDiscoveryConfig Class

```dart
/// Configuration for partner instance discovery.
/// Partner discovery is disabled when standaloneMode=true in global config.
class PartnerDiscoveryConfig {
  /// Partner instance ID (e.g., "watcher" for default instance).
  final String? partnerInstanceId;
  
  /// Partner aliveness port.
  final int? partnerAlivenessPort;
  
  /// URL to fetch partner status.
  final String? partnerStatusUrl;
  
  /// Attempt to discover partner on startup.
  final bool discoveryOnStartup;
  
  /// Start partner if not found on startup.
  final bool startPartnerIfMissing;
  
  PartnerDiscoveryConfig({
    this.partnerInstanceId,
    this.partnerAlivenessPort,
    this.partnerStatusUrl,
    this.discoveryOnStartup = true,
    this.startPartnerIfMissing = false,
  });
}
```

---

## Remote HTTP API

The remote HTTP API provides RESTful access to process management for remote processes only.

### Configuration

The remote API is enabled when `remoteAccess.startRemoteAccess` is `true` in the configuration.

| Setting | Default | Description |
|---------|---------|-------------|
| Port | 19881 | HTTP server port |
| Bind Address | 0.0.0.0 | Listen on all interfaces |

### Security Model

**Trusted Hosts:**

Requests from `trustedHosts` (default: localhost, 127.0.0.1, ::1) **bypass all permission checks**. This allows local tools and scripts full access while restricting remote clients.

| Source | Permission Checks | Notes |
|--------|------------------|-------|
| Trusted host | Bypassed | Full access to all operations |
| Remote host | Enforced | Subject to `allowRemote*` settings |

**Host Detection:**

The client's IP address is determined from the HTTP request:
- `X-Forwarded-For` header (if behind reverse proxy)
- `X-Real-IP` header (if behind reverse proxy)
- Socket remote address (direct connection)

**Critical Constraint**: Remote API can ONLY manage processes with `isRemote: true`.

- Local processes (`isRemote: false`) are visible via GET but cannot be modified
- All write operations check `isRemote` flag before proceeding
- Executable whitelist/blacklist filters apply to registration
- Trusted hosts can also manage local processes

### Endpoints

#### List All Processes

```
GET /processes
```

Returns all processes (both local and remote) for inspection.

**Response:**

```json
{
  "processes": [
    {
      "id": "tom-bridge",
      "name": "Tom Bridge",
      "state": "running",
      "enabled": true,
      "autostart": true,
      "isRemote": false,
      "pid": 12345,
      "lastStartedAt": "2026-01-24T10:30:00.000Z"
    },
    {
      "id": "remote-worker",
      "name": "Remote Worker",
      "state": "stopped",
      "enabled": true,
      "autostart": false,
      "isRemote": true,
      "pid": null,
      "lastStartedAt": null
    }
  ]
}
```

#### Get Process Details

```
GET /processes/{id}
```

**Response:** Same as single entry in list response.

#### Register Process (Remote Only)

```
POST /processes
Content-Type: application/json

{
  "id": "new-worker",
  "name": "New Worker",
  "command": "/opt/workers/worker",
  "args": ["--port", "9000"],
  "workingDirectory": "/opt/workers",
  "autostart": true,
  "restartPolicy": {
    "maxAttempts": 5,
    "retryIndefinitely": true
  },
  "alivenessCheck": {
    "enabled": true,
    "url": "http://localhost:9000/health"
  }
}
```

**Behavior:**

1. Check `allowRemoteRegister` permission
2. Validate executable against whitelist/blacklist
3. Create process entry with `isRemote: true`

**Response:**

```json
{
  "success": true,
  "processId": "new-worker"
}
```

**Error Responses:**

- `403 Forbidden` - Remote registration not allowed
- `403 Forbidden` - Executable not permitted by whitelist/blacklist
- `409 Conflict` - Process ID already exists

#### Deregister Process (Remote Only)

```
DELETE /processes/{id}
```

**Behavior:**

1. Check `allowRemoteDeregister` permission
2. Verify process is `isRemote: true`
3. Stop if running, remove from registry

**Response:**

```json
{
  "success": true
}
```

**Error Responses:**

- `403 Forbidden` - Remote deregistration not allowed
- `403 Forbidden` - Cannot modify local process
- `404 Not Found` - Process not found

#### Start Process (Remote Only)

```
POST /processes/{id}/start
```

**Behavior:**

1. Check `allowRemoteStart` permission
2. Verify process is `isRemote: true`
3. Set state to `starting`

**Response:**

```json
{
  "success": true,
  "state": "starting"
}
```

#### Stop Process (Remote Only)

```
POST /processes/{id}/stop
```

**Behavior:**

1. Check `allowRemoteStop` permission
2. Verify process is `isRemote: true`
3. Stop process, set state to `stopped`

**Response:**

```json
{
  "success": true,
  "state": "stopped"
}
```

#### Restart Process (Remote Only)

```
POST /processes/{id}/restart
```

**Behavior:** Stop then start.

#### Enable/Disable Process (Remote Only)

```
POST /processes/{id}/enable
POST /processes/{id}/disable
```

**Behavior:**

1. Check `allowRemoteDisable` permission
2. Verify process is `isRemote: true`
3. Update `enabled` flag

#### Set Autostart (Remote Only)

```
PUT /processes/{id}/autostart
Content-Type: application/json

{
  "autostart": true
}
```

**Behavior:**

1. Check `allowRemoteAutostart` permission
2. Verify process is `isRemote: true`
3. Update `autostart` flag

#### Restart ProcessMonitor

```
POST /monitor/restart
```

**Behavior:**

1. Check `allowRemoteMonitorRestart` permission (or trusted host)
2. Respond with success immediately
3. Trigger self-restart sequence (stop HTTP servers, spawn, exit)

**Response:**

```json
{
  "success": true,
  "message": "ProcessMonitor restart initiated"
}
```

**Error Responses:**

- `403 Forbidden` - Monitor restart not allowed

**Example (curl):**

```bash
# Restart ProcessMonitor from localhost (trusted by default)
curl -X POST http://localhost:19881/monitor/restart

# Response
{"success": true, "message": "ProcessMonitor restart initiated"}
```

#### Get Monitor Status

```
GET /monitor/status
```

Returns ProcessMonitor instance status (similar to aliveness `/status` endpoint).

**Response:**

```json
{
  "instanceId": "default",
  "pid": 12345,
  "startedAt": "2026-01-24T10:30:00.000Z",
  "uptime": 3600,
  "state": "running",
  "standaloneMode": false,
  "partnerInstanceId": "watcher",
  "partnerStatus": "running",
  "partnerPid": 54321,
  "managedProcessCount": 5,
  "runningProcessCount": 3
}
```

#### Get/Set Configuration (Trusted Hosts Only)

These endpoints allow trusted hosts to read and modify configuration.

```
GET /config/remote-access
PUT /config/remote-access
Content-Type: application/json

{
  "allowRemoteRegister": true,
  "allowRemoteDeregister": true,
  "allowRemoteStart": true,
  "allowRemoteStop": true,
  "allowRemoteDisable": true,
  "allowRemoteAutostart": true,
  "allowRemoteMonitorRestart": false
}
```

```
GET /config/trusted-hosts
PUT /config/trusted-hosts
Content-Type: application/json

{
  "trustedHosts": ["localhost", "127.0.0.1", "::1", "192.168.1.100"]
}
```

```
GET /config/executable-whitelist
PUT /config/executable-whitelist
Content-Type: application/json

{
  "patterns": ["/opt/tom/bin/*", "/opt/workers/**"]
}
```

```
GET /config/executable-blacklist
PUT /config/executable-blacklist
Content-Type: application/json

{
  "patterns": ["/bin/rm", "/bin/sudo", "**/*.sh"]
}
```

```
GET /config/standalone-mode
PUT /config/standalone-mode
Content-Type: application/json

{
  "enabled": false
}
```

```
GET /config/partner-discovery
PUT /config/partner-discovery
Content-Type: application/json

{
  "partnerInstanceId": "watcher",
  "partnerAlivenessPort": 19884,
  "partnerStatusUrl": "http://localhost:19884/status",
  "discoveryOnStartup": true,
  "startPartnerIfMissing": false
}
```

**All PUT /config/* endpoints:**

- Require trusted host
- Return `403 Forbidden` if not trusted
- Return `200 OK` with updated configuration on success

---

## Remote Client API

The remote client provides a Dart API for interacting with the HTTP remote API.

### RemoteProcessMonitorClient Class

```dart
/// Remote client API for interacting with ProcessMonitor via HTTP.
class RemoteProcessMonitorClient {
  /// Base URL of the ProcessMonitor HTTP API.
  final String baseUrl;
  
  /// Default: http://localhost:19881
  RemoteProcessMonitorClient({String? baseUrl})
      : baseUrl = baseUrl ?? 'http://localhost:19881';
  
  /// Auto-discover a ProcessMonitor instance.
  ///
  /// Discovery order:
  /// 1. Try localhost:19881
  /// 2. Try 127.0.0.1:19881
  /// 3. Try 0.0.0.0:19881
  /// 4. Scan local subnet (if network interfaces accessible)
  ///
  /// Throws [DiscoveryFailedException] if no instance found.
  static Future<RemoteProcessMonitorClient> discover({
    int port = 19881,
    Duration timeout = const Duration(seconds: 5),
  });
  
  /// Scan a subnet for ProcessMonitor instances.
  /// [subnet] in format "192.168.1" (first 3 octets).
  /// Returns list of responding URLs.
  static Future<List<String>> scanSubnet(
    String subnet, {
    int port = 19881,
    Duration timeout = const Duration(milliseconds: 500),
  });
  
  // --- Registration ---
  
  /// Register a new remote process.
  /// The process will be marked as isRemote=true.
  Future<void> register(ProcessConfig config);
  
  /// Remove a remote process from the registry.
  Future<void> deregister(String processId);
  
  // --- Enable/Disable ---
  
  /// Enable a remote process.
  Future<void> enable(String processId);
  
  /// Disable a remote process.
  Future<void> disable(String processId);
  
  // --- Autostart ---
  
  /// Set autostart for a remote process.
  Future<void> setAutostart(String processId, bool autostart);
  
  // --- Process Control ---
  
  /// Start a remote process.
  Future<void> start(String processId);
  
  /// Stop a remote process.
  Future<void> stop(String processId);
  
  /// Restart a remote process.
  Future<void> restart(String processId);
  
  // --- Status ---
  
  /// Get status of a specific process (local or remote).
  Future<ProcessStatus> getStatus(String processId);
  
  /// Get status of all processes (local and remote).
  /// Local processes are read-only and cannot be modified.
  Future<Map<String, ProcessStatus>> getAllStatus();
  
  /// Get ProcessMonitor instance status (from aliveness port /status endpoint).
  /// Returns instance info including PID, uptime, partner status.
  Future<MonitorStatus> getMonitorStatus();
  
  // --- Remote Access Configuration (trusted hosts only) ---
  
  /// Set remote access permissions.
  /// Requires trusted host.
  Future<void> setRemoteAccessPermissions({
    bool? allowRegister,
    bool? allowDeregister,
    bool? allowStart,
    bool? allowStop,
    bool? allowDisable,
    bool? allowAutostart,
    bool? allowMonitorRestart,
  });
  
  /// Set trusted hosts list.
  /// Requires trusted host.
  Future<void> setTrustedHosts(List<String> hosts);
  
  /// Get trusted hosts list.
  Future<List<String>> getTrustedHosts();
  
  // --- Executable Filtering (trusted hosts only) ---
  
  /// Get the current executable whitelist.
  Future<List<String>> getRemoteExecutableWhitelist();
  
  /// Set the executable whitelist (glob patterns).
  /// Requires trusted host.
  Future<void> setRemoteExecutableWhitelist(List<String> patterns);
  
  /// Get the current executable blacklist.
  Future<List<String>> getRemoteExecutableBlacklist();
  
  /// Set the executable blacklist (glob patterns).
  /// Requires trusted host.
  Future<void> setRemoteExecutableBlacklist(List<String> patterns);
  
  // --- Standalone / Partner Configuration (trusted hosts only) ---
  
  /// Enable or disable standalone mode (no partner monitoring).
  /// Requires trusted host.
  Future<void> setStandaloneMode(bool enabled);
  
  /// Get current standalone mode setting.
  Future<bool> isStandaloneMode();
  
  /// Get partner discovery configuration.
  Future<PartnerDiscoveryConfig> getPartnerDiscoveryConfig();
  
  /// Set partner discovery configuration.
  /// Requires trusted host.
  Future<void> setPartnerDiscoveryConfig(PartnerDiscoveryConfig config);
  
  // --- Monitor Control ---
  
  /// Restart the ProcessMonitor itself.
  /// Requires `allowRemoteMonitorRestart` permission (or trusted host).
  /// The monitor will stop HTTP servers, spawn a new instance, and exit.
  /// This method returns immediately after the restart is initiated.
  Future<void> restartMonitor();
}
```

### Usage Example

```dart
final remote = RemoteProcessMonitorClient(
  baseUrl: 'http://192.168.1.100:19881',
);

// Register a remote process
await remote.register(ProcessConfig(
  id: 'remote-api',
  name: 'Remote API Server',
  command: '/opt/api/server',
  args: ['--port', '8080'],
  autostart: true,
));

// Start it
await remote.start('remote-api');

// Get all processes (includes local for inspection)
final all = await remote.getAllStatus();
for (final process in all.values) {
  print('${process.id}: ${process.state} (remote: ${process.isRemote})');
}

// Can only modify remote processes
await remote.stop('remote-api');      // OK - remote process
// await remote.stop('tom-bridge');   // ERROR - local process
```

---

## API Operations

### Register Process

```dart
await client.register(ProcessConfig(
  id: 'my-service',
  name: 'My Service',
  command: '/usr/bin/my-service',
  args: ['--port', '8080'],
  autostart: true,
));
```

**Behavior:**

1. Acquire exclusive lock
2. Load registry
3. Validate process ID is unique
4. Add process entry with:
   - `enabled: true`
   - `autostart: <specified>`
   - `state: stopped`
   - `isRemote: false` (local registration)
5. Save registry
6. Release lock

### Deregister Process

```dart
await client.deregister('my-service');
```

**Behavior:**

1. Acquire exclusive lock
2. Load registry
3. If process is running, stop it
4. Remove process from registry
5. Save registry
6. Release lock

### Disable Process

```dart
await client.disable('my-service');
```

**Behavior:**

1. Acquire exclusive lock
2. Load registry
3. If process is running, stop it
4. Set `enabled: false`
5. Set `state: disabled`
6. Save registry
7. Release lock

**Key Point**: A disabled process will NOT restart, even if `autostart: true`. The `enabled` flag takes precedence.

### Enable Process

```dart
await client.enable('my-service');
```

**Behavior:**

1. Acquire exclusive lock
2. Load registry
3. Set `enabled: true`
4. Set `state: stopped`
5. Save registry
6. Release lock

**Note**: Enabling does not automatically start the process. Call `start()` or wait for ProcessMonitor restart if `autostart: true`.

### Set Autostart

```dart
await client.setAutostart('my-service', true);
await client.setAutostart('my-service', false);
```

**Behavior:**

1. Acquire exclusive lock
2. Load registry
3. Set `autostart: <value>`
4. Save registry
5. Release lock

### Start Process

```dart
await client.start('my-service');
```

**Behavior:**

1. Acquire exclusive lock
2. Load registry
3. Validate process exists and is enabled
4. If already running, return success
5. Set `state: starting`
6. Save registry
7. Release lock

The ProcessMonitor picks up the state change on next heartbeat and starts the process.

### Stop Process

```dart
await client.stop('my-service');
```

**Behavior:**

1. Acquire exclusive lock
2. Load registry
3. If process is running:
   - Send termination signal (SIGTERM)
   - Wait for graceful shutdown (timeout: 10s)
   - Force kill if needed (SIGKILL)
4. Set `state: stopped`
5. Clear `pid`
6. Set `lastStoppedAt`
7. Save registry
8. Release lock

**Key Point**: Stop does NOT set `enabled: false`. If the ProcessMonitor restarts and `autostart: true`, the process will start again. Use `disable()` to prevent restart.

### Restart Process

```dart
await client.restart('my-service');
```

**Behavior:**

Equivalent to:

```dart
await client.stop('my-service');
await client.start('my-service');
```

---

## State Transitions

```
                    register()
                        |
                        v
    +----------+   enable()   +----------+
    | disabled | <----------> | stopped  |
    +----------+   disable()  +----------+
         ^                         |
         |                         | start()
         |                         v
         |                    +----------+
         |                    | starting |
         |                    +----------+
         |                         |
         |                         | (process launched)
         |                         v
         |    disable()       +----------+
         +--------------------|  running |
         |                    +----------+
         |                         |
         |            +------------+------------+
         |            |                         |
         |            | stop()                  | (process dies)
         |            v                         v
         |       +----------+              +----------+
         |       | stopping |              | crashed  |
         |       +----------+              +----------+
         |            |                         |
         |            | (process stopped)       | (restart attempt)
         |            v                         v
         |       +----------+              +----------+
         +-------|  stopped |              | starting |
                 +----------+              +----------+
                      ^                         |
                      |   (max attempts)        |
                      |       exceeded          |
                      |            +------------+
                      |            v
                      |       +----------+
                      +-------|  failed  |
                              +----------+
```

---

## Restart Behavior

### Crash Detection

The ProcessMonitor detects crashes by checking if the process PID is still alive during each heartbeat cycle.

```dart
Future<bool> _isProcessAlive(int pid) async {
  try {
    // Send signal 0 to check if process exists
    Process.killPid(pid, ProcessSignal.sigcont);
    return true;
  } catch (e) {
    return false;
  }
}
```

### Restart Logic

```dart
Future<void> _attemptRestart(ProcessEntry process) async {
  final policy = process.restartPolicy ?? _defaultRestartPolicy;
  
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

Future<void> _attemptIndefiniteRetry(ProcessEntry process) async {
  final policy = process.restartPolicy ?? _defaultRestartPolicy;
  
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
```

### Restart Counter Reset

The restart counter resets after the process has been running stably for `resetAfterMs`:

```dart
if (process.state == ProcessState.running &&
    process.restartAttempts > 0 &&
    process.lastStartedAt != null) {
  final stableTime = DateTime.now().difference(process.lastStartedAt!);
  if (stableTime.inMilliseconds > policy.resetAfterMs) {
    process.restartAttempts = 0;
    _log('Reset restart counter for ${process.id} after stable running');
  }
}
```

---

## Logging

### Log File Management

- Location: `.tom/process_monitor/{id}_logs/{timestamp}_{id}.log`
- Timestamp format: `YYYYMMDD_HHMMSS`
- New log file created on each ProcessMonitor startup
- Log rotation: keep last 10 files, delete oldest on startup
- Contains human-readable entries with timestamps

### Log Format

```
[2026-01-24T10:30:00.000Z] [INFO] ProcessMonitor started (PID: 12345)
[2026-01-24T10:30:00.001Z] [INFO] Configuration loaded: 3 processes
[2026-01-24T10:30:00.002Z] [INFO] Starting autostart process: my-service
[2026-01-24T10:30:00.050Z] [INFO] Process my-service started (PID: 12346)
[2026-01-24T10:35:00.000Z] [WARN] Process my-service crashed
[2026-01-24T10:35:01.000Z] [INFO] Restarting my-service (attempt 1)
[2026-01-24T10:35:01.050Z] [INFO] Process my-service started (PID: 12350)
```

### Log Levels

| Level | Usage |
|-------|-------|
| INFO | Normal operations (start, stop, register) |
| WARN | Process crashes, failed operations |
| ERROR | Lock failures, file I/O errors |

---

## Error Handling

### Lock Timeout

```dart
try {
  await client.start('my-service');
} on LockTimeoutException catch (e) {
  // Another process holds the lock
  print('Failed to acquire lock: $e');
}
```

### Process Not Found

```dart
try {
  await client.start('non-existent');
} on ProcessNotFoundException catch (e) {
  print('Process not found: $e');
}
```

### Process Disabled

```dart
try {
  await client.start('disabled-service');
} on ProcessDisabledException catch (e) {
  print('Cannot start disabled process: $e');
}
```

---

## Mutual Monitoring (Default + Watcher)

The ProcessMonitor supports running two instances that monitor each other: a **default** instance and a **watcher** instance.

### Architecture

```
+------------------------------------------------------------------+
|                     MUTUAL MONITORING SETUP                       |
+------------------------------------------------------------------+

     +------------------------+      +------------------------+
     |   DEFAULT INSTANCE     |      |   WATCHER INSTANCE     |
     |   instanceId: default  |      |   instanceId: watcher  |
     |   alivenessPort: 19883  |      |   alivenessPort: 19884  |
     +------------------------+      +------------------------+
              |                               |
              |  Monitors watcher via         |  Monitors default via
              |  PID + HTTP aliveness         |  PID + HTTP aliveness
              |                               |
              +-------------------------------+
                      Mutual Monitoring

     +--------------------------------------------------+
     |   MANAGED PROCESSES                              |
     |   (All started as detached processes)            |
     +--------------------------------------------------+
```

---

## Detached Process Management

**All managed processes are started in detached mode** to ensure they survive ProcessMonitor crashes and restarts.

### Why Detached Mode

1. **Resilience**: If ProcessMonitor crashes, managed processes continue running
2. **Independence**: Processes are not tied to ProcessMonitor's process group
3. **Restart Safety**: ProcessMonitor can restart without affecting running processes
4. **Mutual Monitoring**: Default and watcher instances can monitor each other

### Process Control Capabilities (No Superuser Rights Required)

On Unix/Linux, process control permissions are based on **user ownership (UID)**, not parent-child relationship. A process can control any other process owned by the same user, even if that process was started by someone else or is completely detached.

| Operation | Method | Works on Detached? | Requires Root? |
|-----------|--------|-------------------|----------------|
| Check if alive | `kill(pid, 0)` | Yes | No (same user) |
| Send SIGTERM | `kill(pid, SIGTERM)` | Yes | No (same user) |
| Send SIGKILL | `kill(pid, SIGKILL)` | Yes | No (same user) |
| Read /proc/{pid} | Filesystem access | Yes | No (same user) |

**Key Insight:** The parent-child relationship is irrelevant for process control. If ProcessMonitor runs as user `tom`, it can check, signal, and kill ANY process owned by user `tom`, regardless of who started it.

### Dart Implementation

```dart
/// Check if a process exists (works for any process owned by same user).
/// This works for detached processes and processes we didn't start.
Future<bool> isProcessAlive(int pid) async {
  if (Platform.isWindows) {
    return _isProcessAliveWindows(pid);
  }
  
  try {
    // Signal 0 checks existence without sending actual signal
    // Works for ANY process owned by the same user
    return Process.killPid(pid, ProcessSignal.sigcont);
  } catch (e) {
    return false;
  }
}

/// Kill a process (works for any process owned by same user).
Future<bool> killProcess(int pid, {bool force = false}) async {
  if (Platform.isWindows) {
    return _killProcessWindows(pid, force: force);
  }
  
  try {
    final signal = force ? ProcessSignal.sigkill : ProcessSignal.sigterm;
    return Process.killPid(pid, signal);
  } catch (e) {
    return false;
  }
}

/// Start a process in detached mode.
/// The process will survive if this process terminates.
Future<int> startDetached({
  required String command,
  required List<String> args,
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  final process = await Process.start(
    command,
    args,
    workingDirectory: workingDirectory,
    environment: environment,
    mode: ProcessStartMode.detached,  // Key: detached mode
  );
  
  // In detached mode, we get the PID but no stdin/stdout/stderr
  return process.pid;
}
```

### Platform-Specific Notes

**Linux:**

```dart
// Alternative: Use /proc filesystem to check process
Future<bool> isProcessAliveLinux(int pid) async {
  return await Directory('/proc/$pid').exists();
}

// Get process info from /proc
Future<String?> getProcessState(int pid) async {
  final statFile = File('/proc/$pid/stat');
  if (!await statFile.exists()) return null;
  
  final content = await statFile.readAsString();
  // Parse: pid (comm) state ...
  // State: R=running, S=sleeping, D=disk sleep, Z=zombie, T=stopped
  final match = RegExp(r'\d+ \([^)]+\) (\w)').firstMatch(content);
  return match?.group(1);
}
```

**macOS:**

```dart
// macOS doesn't have /proc, use kill(pid, 0) or ps command
Future<bool> isProcessAliveMacOS(int pid) async {
  // kill(pid, 0) works the same as Linux
  try {
    return Process.killPid(pid, ProcessSignal.sigcont);
  } catch (e) {
    return false;
  }
}
```

**Windows:**

```dart
Future<bool> _isProcessAliveWindows(int pid) async {
  final result = await Process.run('tasklist', ['/FI', 'PID eq $pid', '/NH']);
  return result.stdout.toString().contains('$pid');
}

Future<bool> _killProcessWindows(int pid, {bool force = false}) async {
  final args = force ? ['/F', '/PID', '$pid'] : ['/PID', '$pid'];
  final result = await Process.run('taskkill', args);
  return result.exitCode == 0;
}
```

### Platform Behavior for Detached Processes

| Platform | Detached Behavior |
|----------|------------------|
| Linux | Uses `setsid()` to create new session, process group leader |
| macOS | Similar to Linux, new session created |
| Windows | Uses `DETACHED_PROCESS` creation flag |

### Stdout/Stderr Capture for Detached Processes

Since detached processes don't provide stdout/stderr streams to the parent, output is captured via shell redirection to the consolidated log directory:

```dart
Future<int> startDetachedWithLogging({
  required String command,
  required List<String> args,
  required String logDir,
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  // Create log directory
  await Directory(logDir).create(recursive: true);
  
  final stdoutPath = path.join(logDir, 'stdout.log');
  final stderrPath = path.join(logDir, 'stderr.log');
  
  if (Platform.isWindows) {
    // Windows: use cmd /c with redirection
    final cmdLine = '${_escapeWindows(command)} ${args.join(' ')} '
        '> "$stdoutPath" 2> "$stderrPath"';
    final result = await Process.run('cmd', ['/c', 'start', '/b', cmdLine]);
    // Parse PID from wmic or other method
  } else {
    // Unix: use nohup with shell redirection
    final escapedCmd = _escapeUnix(command, args);
    final result = await Process.run('sh', [
      '-c',
      'nohup $escapedCmd > "$stdoutPath" 2> "$stderrPath" & echo \$!'
    ]);
    return int.parse(result.stdout.toString().trim());
  }
}
```

### PID vs HTTP Aliveness Monitoring

Both monitoring methods work with detached processes:

| Method | Detects | Limitation |
|--------|---------|------------|
| PID check (`kill(pid, 0)`) | Process exists | Doesn't detect hung/unresponsive processes |
| HTTP aliveness | Process is responsive | Requires process to implement health endpoint |

**Recommendation:** Use BOTH when possible:
1. **PID check**: Fast, always works, detects crashed processes immediately
2. **HTTP aliveness**: Detects hung, deadlocked, or otherwise unhealthy processes

For processes without HTTP endpoints, PID checking alone is sufficient for basic monitoring.

### Instance IDs

| Instance | ID | Aliveness Port | Remote Port | Purpose |
|----------|-----|---------------|-------------|---------|
| Default | `default` | 19883 | 19881 | Primary process manager |
| Watcher | `watcher` | 19884 | 19882 | Monitors default, restarts if needed |

### Watcher Startup Flow

```
Watcher.start(instanceId: "watcher")
    |
    +---> 1. Start normally with watcher configuration
    |
    +---> 2. Register "default" ProcessMonitor as managed process
    |         |
    |         +---> command: <path-to-processmonitor>
    |         +---> args: ["--instance-id", "default", "--watcher-pid", <watcher-pid>]
    |         +---> autostart: true
    |         +---> alivenessCheck:
    |               url: http://localhost:19883/alive
    |
    +---> 3. Start "default" ProcessMonitor
    |
    +---> 4. Begin monitoring loop
              |
              +---> Monitor default via PID + aliveness check
              +---> Restart default if it dies
```

### Default Startup with Watcher

When the default ProcessMonitor is started by the watcher:

```
Default.start(instanceId: "default", watcherPid: 54321)
    |
    +---> 1. Start normally
    |
    +---> 2. Record watcher info in configuration
    |         |
    |         +---> watcherInfo.watcherPid = 54321
    |         +---> watcherInfo.watcherInstanceId = "watcher"
    |         +---> watcherInfo.watcherAlivenessPort = 19884
    |
    +---> 3. Register watcher as managed process
    |         |
    |         +---> Mark as running (already started)
    |         +---> Set PID from command line argument
    |         +---> alivenessCheck:
    |               url: http://localhost:19884/alive
    |
    +---> 4. Continue normal startup
    |
    +---> 5. Monitoring loop includes watcher
              |
              +---> If watcher dies, restart it
```

### Mutual Restart Behavior

| Scenario | Action |
|----------|--------|
| Default crashes | Watcher detects via aliveness check (2 failures), restarts default |
| Watcher crashes | Default detects via aliveness check (2 failures), restarts watcher |
| Both crash | System restart needed (neither can restart the other) |
| Watcher started first | Watcher starts default with `--watcher-pid` argument |
| Default started first | Default can optionally start watcher |
| Self-restart requested | Stop HTTP servers, spawn new instance, exit |

### Self-Restart Mechanism

A ProcessMonitor can restart itself (e.g., after an update or configuration change) using the **spawn-then-exit** pattern. The critical requirement is to **stop all HTTP servers before spawning** to ensure the new instance can bind to the same ports.

**Restart Sequence:**

```
restartSelf()
    |
    +---> 1. Stop aliveness HTTP server (port 19883/19884)
    |
    +---> 2. Stop remote API HTTP server (port 19881/19882)
    |
    +---> 3. Wait for ports to fully release (100ms)
    |
    +---> 4. Spawn new instance in detached mode
    |         |
    |         +---> Same executable path
    |         +---> Same command line arguments
    |         +---> ProcessStartMode.detached
    |
    +---> 5. Wait briefly for new instance to start (500ms)
    |
    +---> 6. Exit current process with code 0
```

**Implementation:**

```dart
/// Restart this ProcessMonitor instance.
/// IMPORTANT: Stops HTTP servers first to release ports.
Future<void> restartSelf() async {
  log('Self-restart requested, stopping HTTP servers...');
  
  // 1. Stop HTTP servers to release ports
  await _alivenessServer?.stop();
  await _remoteApiServer?.stop();
  
  // 2. Wait for ports to fully release
  await Future.delayed(Duration(milliseconds: 100));
  
  // 3. Spawn new instance in detached mode
  final executable = Platform.resolvedExecutable;
  final args = Platform.executableArguments;
  
  log('Spawning new instance: $executable ${args.join(' ')}');
  
  await Process.start(
    executable,
    args,
    mode: ProcessStartMode.detached,
  );
  
  // 4. Give new instance time to start
  await Future.delayed(Duration(milliseconds: 500));
  
  // 5. Exit current process
  log('Exiting current instance');
  exit(0);
}
```

**Exit Codes:**

| Exit Code | Meaning |
|-----------|---------|
| 0 | Normal exit (or self-restart) |
| 75 | Request restart by partner (convention) |
| 1 | Error exit |

**Partner-Initiated Restart:**

A process can also request its partner to restart it by exiting with a special code:

```dart
/// Request partner to restart us.
/// Use when self-restart is not possible (e.g., corrupted state).
void requestPartnerRestart() {
  log('Requesting partner restart, exiting with code 75');
  exit(75);  // Convention: 75 = please restart me
}
```

**Aliveness Tolerance During Restart:**

Since a self-restart takes ~600ms (stop servers + spawn + start):
- Aliveness check interval: 3000ms
- Consecutive failures required: 2
- Maximum outage before restart: ~6000ms

This tolerance ensures a single missed aliveness check during restart does not trigger an unnecessary restart by the partner.

### Command Line Arguments

```bash
# Start default instance (standalone)
processmonitor --instance-id default

# Start watcher instance (will start default)
processmonitor --instance-id watcher

# Start default instance (started by watcher)
processmonitor --instance-id default --watcher-pid 54321
```

---

## Aliveness Protocol

The aliveness protocol provides a simple HTTP endpoint for health checking.

### Aliveness Server

Each ProcessMonitor instance runs an aliveness HTTP server.

| Instance | Default Port | Endpoints |
|----------|-------------|----------|
| Default | 19883 | `GET /alive`, `GET /status` |
| Watcher | 19884 | `GET /alive`, `GET /status` |

### Alive Endpoint

**Request:**

```
GET /alive HTTP/1.1
Host: localhost:19883
```

**Success Response:**

```
HTTP/1.1 200 OK
Content-Type: text/plain
Content-Length: 2

OK
```

**Interpretation:**

| Response | Meaning |
|----------|---------|
| HTTP 200 + body "OK" | Process is alive and healthy |
| HTTP non-200 | Process is unhealthy |
| Connection refused | Process is dead |
| Timeout | Process is unresponsive (treated as dead) |

### Status Endpoint

The `/status` endpoint provides detailed information about the ProcessMonitor instance, including its PID. This enables discovery without command-line arguments.

**Request:**

```
GET /status HTTP/1.1
Host: localhost:19883
```

**Response:**

```json
{
  "instanceId": "default",
  "pid": 12345,
  "startedAt": "2026-01-24T10:30:00.000Z",
  "uptime": 3600,
  "state": "running",
  "partnerInstanceId": "watcher",
  "partnerStatus": "running",
  "partnerPid": 54321,
  "managedProcessCount": 5,
  "runningProcessCount": 3
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `instanceId` | string | This instance's ID (e.g., "default", "watcher") |
| `pid` | int | This instance's process ID |
| `startedAt` | ISO8601 | When this instance started |
| `uptime` | int | Seconds since startup |
| `state` | string | Current state ("running", "stopping") |
| `partnerInstanceId` | string? | Partner instance ID (null if standalone) |
| `partnerStatus` | string? | Partner status ("running", "stopped", "unknown") |
| `partnerPid` | int? | Partner's PID (null if unknown or standalone) |
| `managedProcessCount` | int | Total number of managed processes |
| `runningProcessCount` | int | Number of currently running processes |

**Usage for Partner Discovery:**

On startup, each instance can discover its partner:

```dart
Future<PartnerInfo?> discoverPartner(int partnerPort) async {
  try {
    final response = await http.get(
      Uri.parse('http://localhost:$partnerPort/status'),
    ).timeout(Duration(seconds: 2));
    
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return PartnerInfo(
        instanceId: json['instanceId'],
        pid: json['pid'],
        startedAt: DateTime.parse(json['startedAt']),
      );
    }
  } catch (e) {
    // Partner not running or not responding
  }
  return null;
}
```

### Aliveness Check for Managed Processes

Any managed process can optionally have an aliveness check configured:

```json
{
  "id": "my-api",
  "alivenessCheck": {
    "enabled": true,
    "url": "http://localhost:8080/health",
    "intervalMs": 3000,
    "timeoutMs": 2000,
    "consecutiveFailuresRequired": 2
  }
}
```

**Behavior:**

1. On each aliveness check interval, if `alivenessCheck.enabled`:
   - Send HTTP GET to the configured URL
   - Track consecutive failures (single failure is tolerated for restarts)
   - Only after `consecutiveFailuresRequired` failures (default: 2), treat as unhealthy
2. Aliveness check is IN ADDITION TO PID monitoring
3. Process must satisfy both checks to be considered healthy

### Implementation

```dart
class AlivenessServer {
  final int port;
  HttpServer? _server;
  
  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen((request) async {
      if (request.uri.path == '/alive' && request.method == 'GET') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.text
          ..write('OK');
        await request.response.close();
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not Found');
        await request.response.close();
      }
    });
  }
  
  Future<void> stop() async {
    await _server?.close();
  }
}

Future<bool> checkAliveness(String url, Duration timeout) async {
  try {
    final response = await http.get(Uri.parse(url)).timeout(timeout);
    return response.statusCode == 200 && response.body.trim() == 'OK';
  } catch (e) {
    return false;
  }
}
```

### AlivenessServerHelper

For managed processes that need to expose aliveness endpoints:

```dart
/// Helper class for managed processes to expose aliveness endpoints.
class AlivenessServerHelper {
  final int port;
  final AlivenessCallback callback;
  
  AlivenessServerHelper({
    required this.port,
    this.callback = const AlivenessCallback(),
  });
  
  /// Start the aliveness server.
  Future<void> start();
  
  /// Stop the aliveness server.
  Future<void> stop();
  
  /// Add a custom route handler.
  void addRoute(String path, Future<void> Function(HttpRequest) handler);
}

/// Callback interface for aliveness server events.
class AlivenessCallback {
  /// Called when a health check is requested.
  /// Return true if healthy, false otherwise.
  final Future<bool> Function()? onHealthCheck;
  
  /// Called when status is requested.
  /// Return custom status data.
  final Future<Map<String, dynamic>> Function()? onStatusRequest;
  
  const AlivenessCallback({
    this.onHealthCheck,
    this.onStatusRequest,
  });
}
```

**Endpoints Provided:**

| Endpoint | Description |
|----------|-------------|
| `GET /health` | Returns 200 if healthy (via callback), 503 if unhealthy. JSON body with `healthy` and `timestamp`. |
| `GET /status` | Returns custom status JSON from callback, plus `timestamp` and `pid`. |

**Usage Example:**

```dart
final aliveness = AlivenessServerHelper(
  port: 8080,
  callback: AlivenessCallback(
    onHealthCheck: () async => database.isConnected,
    onStatusRequest: () async => {'version': '1.0.0', 'connections': 42},
  ),
);
await aliveness.start();
```

---

## Configuration Example

### Complete Registry File

```json
{
  "version": 1,
  "lastModified": "2026-01-24T10:30:00.000Z",
  "instanceId": "default",
  "monitorIntervalMs": 5000,
  "remoteAccess": {
    "startRemoteAccess": true,
    "remotePort": 19881,
    "trustedHosts": ["localhost", "127.0.0.1", "::1"],
    "allowRemoteRegister": true,
    "allowRemoteDeregister": true,
    "allowRemoteStart": true,
    "allowRemoteStop": true,
    "allowRemoteDisable": true,
    "allowRemoteAutostart": true,
    "allowRemoteMonitorRestart": false,
    "executableWhitelist": [
      "/opt/tom/bin/*",
      "/opt/workers/**"
    ],
    "executableBlacklist": [
      "/bin/rm",
      "/bin/sudo",
      "**/*.sh"
    ]
  },
  "alivenessServer": {
    "enabled": true,
    "port": 19883
  },
  "watcherInfo": {
    "watcherPid": 54321,
    "watcherInstanceId": "watcher",
    "watcherAlivenessPort": 19884
  },
  "processes": {
    "watcher": {
      "id": "watcher",
      "name": "ProcessMonitor Watcher",
      "command": "/opt/tom/bin/processmonitor",
      "args": ["--instance-id", "watcher"],
      "autostart": true,
      "enabled": true,
      "isRemote": false,
      "alivenessCheck": {
        "enabled": true,
        "url": "http://localhost:19884/alive",
        "intervalMs": 3000,
        "timeoutMs": 2000,
        "consecutiveFailuresRequired": 2
      },
      "pid": 54321,
      "state": "running",
      "restartAttempts": 0
    },
    "tom-bridge": {
      "id": "tom-bridge",
      "name": "Tom Bridge",
      "command": "/opt/tom/bin/tom-bridge",
      "args": ["--port", "9000"],
      "workingDirectory": "/opt/tom",
      "environment": {
        "TOM_LOG_LEVEL": "info"
      },
      "autostart": true,
      "enabled": true,
      "isRemote": false,
      "restartPolicy": {
        "maxAttempts": 10,
        "backoffIntervalsMs": [1000, 2000, 5000, 10000, 30000],
        "resetAfterMs": 300000,
        "retryIndefinitely": true,
        "indefiniteIntervalMs": 21600000
      },
      "alivenessCheck": {
        "enabled": true,
        "url": "http://localhost:9000/health",
        "intervalMs": 3000,
        "timeoutMs": 2000,
        "consecutiveFailuresRequired": 2
      },
      "registeredAt": "2026-01-20T08:00:00.000Z",
      "lastStartedAt": "2026-01-24T10:30:00.000Z",
      "lastStoppedAt": null,
      "pid": 12345,
      "state": "running",
      "restartAttempts": 0
    },
    "remote-worker": {
      "id": "remote-worker",
      "name": "Remote Worker",
      "command": "/opt/workers/worker",
      "args": ["--port", "9001"],
      "autostart": false,
      "enabled": true,
      "isRemote": true,
      "restartPolicy": {
        "maxAttempts": 5,
        "retryIndefinitely": false
      },
      "registeredAt": "2026-01-24T11:00:00.000Z",
      "lastStartedAt": null,
      "lastStoppedAt": null,
      "pid": null,
      "state": "stopped",
      "restartAttempts": 0
    }
  }
}
```

---

## Usage Examples

### Basic Local Usage

```dart
// Create local client (default instance)
final client = ProcessMonitorClient();

// Or specify instance ID
final watcherClient = ProcessMonitorClient(instanceId: 'watcher');

// Register a new local process
await client.register(ProcessConfig(
  id: 'my-api',
  name: 'My API Server',
  command: '/usr/bin/node',
  args: ['server.js'],
  workingDirectory: '/opt/my-api',
  autostart: true,
  alivenessCheck: AlivenessCheck(
    enabled: true,
    url: 'http://localhost:8080/health',
  ),
));

// Check status
final status = await client.getStatus('my-api');
print('State: ${status.state}');

// Enable remote access
await client.setRemoteAccess(true);

// Configure executable filtering
await client.setRemoteExecutableWhitelist(['/opt/tom/bin/*']);
await client.setRemoteExecutableBlacklist(['/bin/rm', '**/*.sh']);

// Stop temporarily (will restart on monitor restart if autostart=true)
await client.stop('my-api');

// Disable permanently (won't restart)
await client.disable('my-api');

// Re-enable and start
await client.enable('my-api');
await client.start('my-api');

// Remove from registry
await client.deregister('my-api');
```

### Remote Client Usage

```dart
// Create remote client
final remote = RemoteProcessMonitorClient(
  baseUrl: 'http://192.168.1.100:19881',
);

// Register a remote process
await remote.register(ProcessConfig(
  id: 'remote-api',
  name: 'Remote API Server',
  command: '/opt/api/server',
  args: ['--port', '8080'],
  autostart: true,
));

// Start it
await remote.start('remote-api');

// Get all processes (includes local for inspection)
final all = await remote.getAllStatus();
for (final process in all.values) {
  final modifiable = process.isRemote ? '[modifiable]' : '[read-only]';
  print('${process.id}: ${process.state} $modifiable');
}
```

### System Startup with Mutual Monitoring

```dart
// Start watcher first (it will start and monitor the default instance)
void main() async {
  final isWatcher = Platform.arguments.contains('--watcher');
  final instanceId = isWatcher ? 'watcher' : 'default';
  
  final monitor = ProcessMonitor(
    directory: '.tom/process_monitor',
    instanceId: instanceId,
    monitorInterval: Duration(seconds: 5),
  );
  
  // Parse watcher PID if provided
  final watcherPidIndex = Platform.arguments.indexOf('--watcher-pid');
  if (watcherPidIndex >= 0) {
    final watcherPid = int.parse(Platform.arguments[watcherPidIndex + 1]);
    monitor.setWatcherInfo(watcherPid, 'watcher', 19884);
  }
  
  await monitor.start();
  
  // If this is the watcher, register and start the default instance
  if (isWatcher) {
    final client = ProcessMonitorClient(instanceId: 'watcher');
    await client.register(ProcessConfig(
      id: 'default-monitor',
      name: 'ProcessMonitor Default',
      command: Platform.executable,
      args: ['processmonitor', '--instance-id', 'default', '--watcher-pid', '${pid}'],
      autostart: true,
      alivenessCheck: AlivenessCheck(
        enabled: true,
        url: 'http://localhost:19883/alive',
      ),
    ));
  }
  
  // Handle shutdown signals
  ProcessSignal.sigterm.watch().listen((_) async {
    await monitor.stop();
    exit(0);
  });
}
```

---

## Implementation Notes

### Concurrency

- All registry operations use the lock file
- ProcessMonitor heartbeat loop acquires lock for each iteration
- Client API operations are atomic (lock -> read -> modify -> write -> unlock)

### Process Independence

- Managed processes run independently of each other
- Stopping ProcessMonitor STOPS all managed processes
- On ProcessMonitor restart, processes marked as "running" with stale PIDs are treated as crashed

### Platform Considerations

| Platform | Signal Support | Notes |
|----------|---------------|-------|
| Linux | Full | SIGTERM, SIGKILL |
| macOS | Full | SIGTERM, SIGKILL |
| Windows | Limited | Use taskkill for termination |

---

## Future Enhancements

1. **Dependency Graph**: Start order based on dependencies
2. **Resource Limits**: CPU/memory limits for managed processes
3. **Metrics**: Process uptime, restart count, resource usage
4. **Notifications**: Webhooks or callbacks for state changes
5. **Authentication**: Token-based auth for remote API
6. **TLS**: HTTPS support for remote API
7. **Cluster Mode**: Distribute process management across multiple hosts
