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
├── registry.json          # Process registry
├── registry.lock          # Lock file for concurrent access
├── watcher_registry.json  # Watcher registry (if enabled)
├── watcher_registry.lock  # Watcher lock file
└── logs/                  # Process logs
    ├── pm.log             # ProcessMonitor logs
    ├── watcher.log        # Watcher logs
    └── {process-id}/      # Individual process logs
        ├── stdout.log
        └── stderr.log
```

### Port Configuration

Default ports:

| Instance | Aliveness Port | Remote API Port |
|----------|----------------|-----------------|
| Default  | 5681           | 5679            |
| Watcher  | 5682           | 5680            |

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
    baseUrl: 'http://localhost:5679',
  );
  
  // Get monitor status
  final status = await client.getMonitorStatus();
  print('Managed processes: ${status.managedProcessCount}');
  
  // List all processes
  final processes = await client.listProcesses();
  for (final process in processes) {
    print('${process.id}: ${process.state}');
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
    maxWaitMs: 30000,                // Wait up to 30 seconds
    intervalMs: 500,                 // Check every 500ms
  ),
)
```

## Watcher System

The watcher instance provides mutual monitoring:

1. **Default instance** monitors registered processes
2. **Watcher instance** monitors the default instance
3. Default instance also monitors the watcher

If either becomes unresponsive, the other can restart it.

### Configuring Watcher Information

```dart
await registryService.withLock((registry) {
  registry.watcherInfo = WatcherInfo(
    watcherPid: 12345,
    watcherInstanceId: 'watcher',
    watcherAlivenessPort: 5682,
  );
});
```

## Remote Access Configuration

Control what remote clients can do:

```dart
await client.setRemoteAccessPermissions(
  allowRemoteRegister: true,
  allowRemoteStart: true,
  allowRemoteStop: true,
  allowRemoteKill: false,            // Dangerous operation
  allowRemoteMonitorRestart: false,  // Dangerous operation
);

// Configure trusted hosts (bypass restrictions)
await client.setTrustedHosts(['192.168.1.100', '10.0.0.0/8']);

// Configure executable whitelist/blacklist
await client.setRemoteExecutableWhitelist([
  '/usr/bin/*',
  '/opt/myapp/*',
]);

await client.setRemoteExecutableBlacklist([
  '/usr/bin/rm',
  '/bin/rm',
]);
```

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
- `logs/pm.log` (default instance)
- `logs/watcher.log` (watcher instance)
- `logs/{process-id}/stdout.log` (process stdout)
- `logs/{process-id}/stderr.log` (process stderr)

## Best Practices

1. **Use aliveness checks** for long-running services
2. **Configure restart policies** appropriate to your service
3. **Run the watcher** for production deployments
4. **Use the remote API** for management UIs
5. **Secure remote access** with trusted hosts and whitelists
6. **Monitor logs** for issues and debugging

## Troubleshooting

### Process won't start

1. Check the process logs in `logs/{process-id}/stderr.log`
2. Verify the command and arguments are correct
3. Check if the process is disabled
4. Look for error messages in `logs/pm.log`

### ProcessMonitor not responding

1. Check if the aliveness endpoint is responding: `curl http://localhost:5681/alive`
2. Check the logs for errors
3. Try the watcher to restart: `monitor_watcher --restart`

### Remote API not accessible

1. Verify remote access is enabled in the registry
2. Check firewall settings
3. Verify the correct port is being used
4. Check if your IP is in the trusted hosts list
