# ProcessMonitor User Guide

ProcessMonitor is a daemon-based process management system that monitors, manages, and automatically restarts processes. It provides both local file-based and remote HTTP APIs for process lifecycle management.

## Overview

ProcessMonitor consists of:

- **ProcessMonitor daemon**: The main process that manages registered processes
- **Watcher instance**: A secondary monitor that watches the main ProcessMonitor
- **Local API**: File-based communication via registry files
- **Remote API**: HTTP-based communication for remote management

## Quick Start

### Starting the ProcessMonitor

Start the default ProcessMonitor instance:

```bash
process_monitor
```

Start in foreground mode (for debugging):

```bash
process_monitor --foreground
```

### Starting the Watcher

The watcher monitors the main ProcessMonitor and can restart it if it becomes unresponsive:

```bash
monitor_watcher
```

### Checking Status

```bash
process_monitor --status
monitor_watcher --status
```

## Configuration

### Directory Structure

By default, ProcessMonitor stores its files in `~/.tom/process_monitor/`:

```
.tom/process_monitor/
├── processes_default.json       # Default instance registry
├── processes_default.lock       # Default instance lock file
├── processes_watcher.json       # Watcher instance registry
├── processes_watcher.lock       # Watcher instance lock file
├── default_logs/                # Default instance logs
│   ├── 20260124_103000_default.log
│   └── my-server/               # Process logs
│       └── 20260124_103000/
│           ├── stdout.log
│           └── stderr.log
└── watcher_logs/                # Watcher instance logs
    └── 20260124_103005_watcher.log
```

### Port Configuration

Default ports:

| Instance | Aliveness Port | Remote API Port |
|----------|----------------|-----------------|
| Default  | 19883           | 19881            |
| Watcher  | 19884           | 19882            |

### First-Time Startup

When ProcessMonitor starts for the first time:

1. **Creates directory structure**: `~/.tom/process_monitor/` and log subdirectories
2. **Creates registry file**: `processes_{instance-id}.json` with default settings
3. **Creates lock file**: `processes_{instance-id}.lock` for exclusive access
4. **Starts servers**: Aliveness server and Remote API server

The default registry is created with:
- Remote access enabled
- Default trusted hosts: `['localhost', '127.0.0.1', '::1', '0.0.0.0']`
- Empty whitelist and blacklist (remote registrations blocked until whitelist configured)
- Partner discovery disabled

### Lock Protocol

ProcessMonitor uses file-based locking to ensure only one instance per ID runs at a time:

**Acquiring a Lock:**
1. Try to write lock file with PID and timestamp
2. If file exists, check if owning PID is still alive
3. If PID is dead, lock is stale - remove and retry
4. If PID is alive, wait (with 5-second timeout)
5. After writing lock, wait 10ms and verify ownership (race condition protection)

**Lock File Format:**
```json
{
  "pid": 12345,
  "timestamp": "2026-01-24T10:30:00.000Z"
}
```

**Stale Lock Detection:**
- On startup, ProcessMonitor checks if the PID in the lock file is still running
- If the process is dead, the lock is considered stale and removed
- This handles cases where ProcessMonitor crashed without releasing its lock

**Cross-Platform PID Checking:**
- Uses platform-specific methods to check if a PID is alive
- Falls back to attempting to signal the process on POSIX systems

### Home Directory Configuration

ProcessMonitor determines the home directory using:

1. `HOME` environment variable (Linux, macOS)
2. `USERPROFILE` environment variable (Windows)
3. Current directory `.` (fallback)

## Using the Local API

The local API uses the `ProcessMonitorClient` class to interact with ProcessMonitor via the file-based registry.

### Registering a Process

```dart
import 'package:tom_process_monitor/tom_process_monitor.dart';

void main() async {
  final client = ProcessMonitorClient();
  
  final config = ProcessConfig(
    id: 'my-server',
    name: 'My Server',
    command: 'dart',
    args: ['run', 'bin/server.dart'],
    autostart: true,
    restartPolicy: RestartPolicy(
      maxAttempts: 5,
      backoffIntervalsMs: [1000, 2000, 5000],
    ),
    alivenessCheck: AlivenessCheck(
      enabled: true,
      url: 'http://localhost:8080/health',
      intervalMs: 3000,
      timeoutMs: 2000,
    ),
  );
  
  await client.register(config);
}
```

### Managing Processes

```dart
// Start a process
await client.start('my-server');

// Stop a process
await client.stop('my-server');

// Restart a process
await client.restart('my-server');

// Get process status
final status = await client.getStatus('my-server');
print('State: ${status.state}');
print('PID: ${status.pid}');

// Get all process statuses
final allStatus = await client.getAllStatus();
for (final entry in allStatus.entries) {
  print('${entry.key}: ${entry.value.state}');
}

// Enable/disable a process
await client.enable('my-server');
await client.disable('my-server');

// Remove a process
await client.deregister('my-server');
```

## Using the Remote API

The remote API uses HTTP to communicate with ProcessMonitor. This is useful for remote management or when you don't have file system access.

### Using RemoteProcessMonitorClient

```dart
import 'package:tom_process_monitor/tom_process_monitor.dart';

void main() async {
  final client = RemoteProcessMonitorClient(
    baseUrl: 'http://localhost:19881',
  );
  
  // Get monitor status
  final status = await client.getMonitorStatus();
  print('Managed processes: ${status.managedProcessCount}');
  
  // List all processes
  final processes = await client.getAllStatus();
  for (final entry in processes.entries) {
    print('${entry.key}: ${entry.value.state}');
  }
  
  // Register and start a process
  await client.register(ProcessConfig(
    id: 'remote-server',
    name: 'Remote Server',
    command: '/usr/bin/myserver',
  ));
  await client.start('remote-server');
  
  // Always dispose when done
  client.dispose();
}
```

### HTTP API Endpoints

#### Process Management

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/processes` | List all processes |
| `POST` | `/processes` | Register a new process |
| `GET` | `/processes/{id}` | Get process details |
| `DELETE` | `/processes/{id}` | Deregister a process |
| `POST` | `/processes/{id}/start` | Start a process |
| `POST` | `/processes/{id}/stop` | Stop a process |
| `POST` | `/processes/{id}/restart` | Restart a process |
| `POST` | `/processes/{id}/enable` | Enable a process |
| `POST` | `/processes/{id}/disable` | Disable a process |

#### Monitor Management

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/monitor/status` | Get monitor status |
| `POST` | `/monitor/restart` | Request monitor restart |

#### Configuration Management

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/config/remote-access` | Get remote access settings |
| `PUT` | `/config/remote-access` | Update remote access settings |
| `GET` | `/config/trusted-hosts` | Get trusted hosts list |
| `PUT` | `/config/trusted-hosts` | Update trusted hosts list |
| `GET` | `/config/executable-whitelist` | Get executable whitelist |
| `PUT` | `/config/executable-whitelist` | Update executable whitelist |
| `GET` | `/config/executable-blacklist` | Get executable blacklist |
| `PUT` | `/config/executable-blacklist` | Update executable blacklist |
| `GET` | `/config/standalone-mode` | Get standalone mode status |
| `PUT` | `/config/standalone-mode` | Set standalone mode |
| `GET` | `/config/partner-discovery` | Get partner discovery config |
| `PUT` | `/config/partner-discovery` | Set partner discovery config |

## Aliveness Endpoints (Port 19883/19884)

ProcessMonitor provides aliveness endpoints on a **separate HTTP server** from the Remote API:

| Instance | Port | Endpoints |
|----------|------|-----------|
| Default | 19883 | `/alive`, `/status` |
| Watcher | 19884 | `/alive`, `/status` |

### Endpoints

| Endpoint | Description | Response |
|----------|-------------|----------|
| `GET /alive` | Simple health check | `OK` (text/plain) |
| `GET /status` | Full monitor status | JSON with PID, uptime, partner status |

### Example Usage

```bash
# Check if ProcessMonitor is alive
curl http://localhost:19883/alive
# Returns: OK

# Get detailed status
curl http://localhost:19883/status
# Returns: {"instanceId":"default","pid":12345,"uptime":3600,...}
```

## Process States

| State | Description |
|-------|-------------|
| `stopped` | Process is not running |
| `starting` | Process is being started |
| `running` | Process is running normally |
| `stopping` | Process is being stopped |
| `crashed` | Process has crashed |
| `retrying` | Waiting for restart after crash |
| `failed` | Failed after exhausting restart attempts |
| `disabled` | Process is disabled |

## Restart Policies

Configure automatic restart behavior:

```dart
RestartPolicy(
  maxAttempts: 5,                    // Max restart attempts
  backoffIntervalsMs: [1000, 2000, 5000],  // Delays between attempts
  resetAfterMs: 300000,              // Reset counter after 5 min stable
  retryIndefinitely: false,          // Keep trying forever
  indefiniteIntervalMs: 21600000,    // 6 hour retry in indefinite mode
)
```

## Aliveness Checks

Configure HTTP health checks:

```dart
AlivenessCheck(
  enabled: true,
  url: 'http://localhost:8080/health',
  intervalMs: 3000,                  // Check every 3 seconds
  timeoutMs: 2000,                   // 2 second timeout
  consecutiveFailuresRequired: 2,    // Failures before marking dead
  startupCheck: StartupCheck(
    enabled: true,
    initialDelayMs: 2000,            // Wait before first check
    checkIntervalMs: 1000,           // Check every 1 second
    maxAttempts: 30,                 // Max attempts before failing
    failAction: 'restart',           // 'restart', 'disable', or 'fail'
  ),
)
```

## Watcher System

The ProcessMonitor supports mutual monitoring between two instances: a **default** instance and a **watcher** instance. They monitor each other and can restart each other if one becomes unresponsive.

### Architecture

```
+------------------------+      +------------------------+
|   DEFAULT INSTANCE     |      |   WATCHER INSTANCE     |
|   instanceId: default  |      |   instanceId: watcher  |
|   alivenessPort: 19883  |      |   alivenessPort: 19884  |
|   remotePort: 19881     |      |   remotePort: 19882     |
+------------------------+      +------------------------+
         |                               |
         |  Monitors watcher via         |  Monitors default via
         |  PID + HTTP aliveness         |  PID + HTTP aliveness
         |                               |
         +-------------------------------+
                 Mutual Monitoring
```

### How It Works

1. **Default instance** manages user processes and monitors the watcher
2. **Watcher instance** monitors the default instance (and can manage its own processes)
3. Each checks the other's aliveness endpoint every 3 seconds
4. After 2 consecutive failures, the monitoring instance restarts the failed instance
5. Both instances run independently as detached processes

### Starting the Watcher System

**Option 1: Start watcher first (recommended)**

```bash
# Start watcher - it will automatically start the default instance
monitor_watcher
```

**Option 2: Start default first**

```bash
# Start default instance
process_monitor

# Start watcher (connects to existing default)
monitor_watcher
```

### Configuration

Both instances need to know about each other:

```dart
// In default instance registry
{
  "partnerDiscovery": {
    "partnerInstanceId": "watcher",
    "partnerAlivenessPort": 19884,
    "partnerStatusUrl": "http://localhost:19884/status",
    "discoveryOnStartup": true,
    "startPartnerIfMissing": false
  }
}
```

### Watcher Registration

When the default instance starts with a watcher, it registers the watcher as a managed process:

```dart
// Default instance registers watcher
await client.register(ProcessConfig(
  id: 'watcher',
  name: 'ProcessMonitor Watcher',
  command: '/path/to/process_monitor',
  args: ['--instance-id', 'watcher'],
  autostart: true,
  alivenessCheck: AlivenessCheck(
    enabled: true,
    url: 'http://localhost:19884/alive',
    intervalMs: 3000,
    consecutiveFailuresRequired: 2,
  ),
));
```

### Standalone Mode

If you don't need mutual monitoring, run in standalone mode:

```dart
await client.setStandaloneMode(true);
```

Or start with the `--standalone` flag:

```bash
process_monitor --standalone
```

### Restart Behavior

| Scenario | Action |
|----------|--------|
| Default crashes | Watcher detects (2 failures) and restarts default |
| Watcher crashes | Default detects (2 failures) and restarts watcher |
| Both crash | System restart needed (e.g., systemd, launchd) |
| Self-restart | Instance stops servers, spawns new process, exits |

## Remote Access Configuration

Control what remote clients can do:

```dart
await client.setRemoteAccessPermissions(
  allowRegister: true,
  allowDeregister: true,
  allowStart: true,
  allowStop: true,
  allowDisable: true,
  allowAutostart: true,
  allowMonitorRestart: false,        // Dangerous operation
);
```

### Trusted Hosts

Configure trusted hosts that bypass permission restrictions. Supports exact IPs, wildcards, and hostname patterns:

```dart
await client.setTrustedHosts([
  // Exact IPs
  '192.168.1.100',
  '127.0.0.1',
  'localhost',
  '0.0.0.0',
  '::1',
  
  // Wildcard patterns (IP)
  '192.168.1.*',      // Match 192.168.1.0-255
  '10.0.*.*',         // Match 10.0.0.0 - 10.0.255.255
  
  // Hostname patterns
  '*.mydomain.com',   // Match any subdomain
  'server-*.local',   // Match server-1.local, server-2.local, etc.
]);
```

**Default trusted hosts:** `['localhost', '127.0.0.1', '::1', '0.0.0.0']`

### Executable Whitelist (Required for Remote Registration)

For security, remote process registration requires the command to match the executable whitelist. **An empty whitelist prevents all remote registrations.**

```dart
// Configure executable whitelist (glob patterns)
await client.setRemoteExecutableWhitelist([
  '/usr/bin/*',         // Allow any executable in /usr/bin
  '/opt/myapp/*',       // Allow executables in /opt/myapp
  '/opt/workers/**',    // Allow all executables recursively
]);
```

### Executable Blacklist

Block specific executables even if they match the whitelist:

```dart
await client.setRemoteExecutableBlacklist([
  '/usr/bin/rm',        // Block rm
  '/bin/rm',
  '/usr/bin/sudo',
  '**/*.sh',            // Block all shell scripts
]);
```

**Security Note:** The whitelist is checked first (must match at least one pattern), then the blacklist is checked (must not match any pattern).

## Auto-Discovery for Remote Clients

The `RemoteProcessMonitorClient` supports auto-discovery to find ProcessMonitor instances on the local network:

```dart
// Auto-discover ProcessMonitor (scans localhost then local subnet)
final client = await RemoteProcessMonitorClient.discover();

// Or with custom timeout
final client = await RemoteProcessMonitorClient.discover(
  timeout: Duration(seconds: 10),
);

// Use explicit URL (skips discovery)
final client = RemoteProcessMonitorClient(baseUrl: 'http://192.168.1.100:19881');
```

### Discovery Process

1. Try `0.0.0.0:19881` (any local interface)
2. Try `127.0.0.1:19881` (localhost)
3. Try `localhost:19881`
4. Get own IP address and scan local subnet (e.g., 192.168.1.1-255)

The first responding instance is used.

## Aliveness Server Helper

For managed processes that need to expose aliveness endpoints, use the `AlivenessServerHelper`:

```dart
import 'package:tom_process_monitor/tom_process_monitor.dart';

void main() async {
  // Create aliveness server with callbacks
  final aliveness = AlivenessServerHelper(
    port: 8080,
    callback: AlivenessCallback(
      onHealthCheck: () async {
        // Return true if healthy, false otherwise
        return database.isConnected && cache.isAvailable;
      },
      onStatusRequest: () async {
        // Return custom status data
        return {
          'version': '1.0.0',
          'connections': activeConnections.length,
          'uptime': DateTime.now().difference(startTime).inSeconds,
        };
      },
    ),
  );
  
  // Start the server
  await aliveness.start();
  
  // Your application code...
  
  // Stop when done
  await aliveness.stop();
}
```

### Endpoints Provided

| Endpoint | Description |
|----------|-------------|
| `GET /health` | Returns 200 if healthy, 503 if unhealthy |
| `GET /status` | Returns custom status JSON |

## Standalone Mode

In standalone mode, the watcher is not required:

```dart
await client.setStandaloneMode(true);
```

Check current mode:

```dart
final isStandalone = await client.isStandaloneMode();
```

## Error Handling

```dart
try {
  await client.start('my-process');
} on ProcessNotFoundException {
  print('Process not found');
} on ProcessDisabledException {
  print('Process is disabled');
} on ProcessMonitorException catch (e) {
  print('Error: ${e.message}');
}
```

## Logging

ProcessMonitor logs to:
- Console (when running in foreground)
- `default_logs/YYYYMMDD_HHMMSS_default.log` (default instance)
- `watcher_logs/YYYYMMDD_HHMMSS_watcher.log` (watcher instance)
- `default_logs/{process-id}/YYYYMMDD_HHMMSS/stdout.log` (process stdout)
- `default_logs/{process-id}/YYYYMMDD_HHMMSS/stderr.log` (process stderr)

## Best Practices

1. **Use aliveness checks** for long-running services
2. **Configure restart policies** appropriate to your service
3. **Run the watcher** for production deployments
4. **Use the remote API** for management UIs
5. **Secure remote access** with trusted hosts and whitelists
6. **Monitor logs** for issues and debugging

## Troubleshooting

### Process won't start

1. Check the process logs in `default_logs/{process-id}/YYYYMMDD_HHMMSS/stderr.log`
2. Verify the command and arguments are correct
3. Check if the process is disabled
4. Look for error messages in `default_logs/YYYYMMDD_HHMMSS_default.log`

### ProcessMonitor not responding

1. Check if the aliveness endpoint is responding: `curl http://localhost:19883/alive`
2. Check the logs for errors
3. Try the watcher to restart: `monitor_watcher --restart`

### Remote API not accessible

1. Verify remote access is enabled in the registry
2. Check firewall settings
3. Verify the correct port is being used
4. Check if your IP is in the trusted hosts list
