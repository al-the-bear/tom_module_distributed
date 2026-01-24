# ProcessMonitor CLI Guide

This guide covers the command-line interface tools for ProcessMonitor: `process_monitor` and `monitor_watcher`.

## Overview

ProcessMonitor provides two CLI tools:

| Tool | Description | Default Ports |
|------|-------------|---------------|
| `process_monitor` | Main ProcessMonitor daemon | Aliveness: 5681, Remote: 5679 |
| `monitor_watcher` | Watcher instance that monitors the main daemon | Aliveness: 5682, Remote: 5680 |

## Installation

### From Source

```bash
cd tom_process_monitor_tool
dart pub get
dart compile exe bin/process_monitor.dart -o process_monitor
dart compile exe bin/monitor_watcher.dart -o monitor_watcher
```

### Using Dart Run

```bash
dart run tom_process_monitor_tool:process_monitor
dart run tom_process_monitor_tool:monitor_watcher
```

## process_monitor

The main ProcessMonitor daemon that manages registered processes.

### Usage

```bash
process_monitor [options]
```

### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--help` | `-h` | Show help message |
| `--version` | | Show version information |
| `--directory` | `-d` | Base directory for files (default: `~/.tom/process_monitor/`) |
| `--foreground` | `-f` | Run in foreground mode |
| `--stop` | | Stop the running instance |
| `--status` | | Show status of the running instance |
| `--restart` | | Restart the running instance |

### Examples

**Start in background (default):**

```bash
process_monitor
```

Output:
```
Starting ProcessMonitor in background...
ProcessMonitor started with PID: 12345
```

**Start in foreground:**

```bash
process_monitor --foreground
```

Output:
```
Starting ProcessMonitor in foreground...
Press Ctrl+C to stop.
========================================
ProcessMonitor Started
Time: 2024-01-15T10:30:00.000Z
Instance: default
PID: 12345
========================================
```

**Check status:**

```bash
process_monitor --status
```

Output:
```
ProcessMonitor Status:
  Instance: default
  State: running
  PID: 12345
  Uptime: 3600s
  Managed Processes: 5
  Running Processes: 3
  Standalone Mode: false
```

**Stop the daemon:**

```bash
process_monitor --stop
```

Output:
```
ProcessMonitor stop signal sent.
```

**Use custom directory:**

```bash
process_monitor --directory=/opt/myapp/pm
```

## monitor_watcher

The watcher instance that monitors the main ProcessMonitor daemon and can restart it if it becomes unresponsive.

### Usage

```bash
monitor_watcher [options]
```

### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--help` | `-h` | Show help message |
| `--version` | | Show version information |
| `--directory` | `-d` | Base directory for files (default: `~/.tom/process_monitor/`) |
| `--foreground` | `-f` | Run in foreground mode |
| `--stop` | | Stop the running watcher |
| `--status` | | Show status of the running watcher |
| `--restart` | | Restart the running watcher |

### Examples

**Start the watcher:**

```bash
monitor_watcher
```

Output:
```
Starting Watcher in background...
Watcher started with PID: 12346
```

**Start in foreground:**

```bash
monitor_watcher --foreground
```

**Check watcher status:**

```bash
monitor_watcher --status
```

Output:
```
Watcher Status:
  Instance: watcher
  State: running
  PID: 12346
  Uptime: 1800s
  Managed Processes: 1
  Running Processes: 1
  Standalone Mode: false
```

## Deployment Scenarios

### Development (Foreground)

For development and debugging, run in foreground:

```bash
process_monitor --foreground
```

Logs are printed directly to the console. Press Ctrl+C to stop.

### Production (Background with Watcher)

For production deployments, run both the main daemon and watcher:

```bash
# Start the main ProcessMonitor
process_monitor

# Start the watcher to monitor it
monitor_watcher
```

### Standalone Mode (No Watcher)

If you don't need the watcher, configure standalone mode programmatically:

```dart
final client = ProcessMonitorClient();
await client.setStandaloneMode(true);
```

Then just run:

```bash
process_monitor
```

### Custom Directory

Use a custom directory for all ProcessMonitor files:

```bash
process_monitor --directory=/var/lib/processmonitor
monitor_watcher --directory=/var/lib/processmonitor
```

Both tools must use the same directory to communicate properly.

## Systemd Integration

Create a systemd service file for automatic startup:

**`/etc/systemd/system/processmonitor.service`:**

```ini
[Unit]
Description=ProcessMonitor Daemon
After=network.target

[Service]
Type=simple
User=myuser
WorkingDirectory=/opt/myapp
ExecStart=/usr/local/bin/process_monitor --foreground
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

**`/etc/systemd/system/processmonitor-watcher.service`:**

```ini
[Unit]
Description=ProcessMonitor Watcher
After=processmonitor.service
BindsTo=processmonitor.service

[Service]
Type=simple
User=myuser
WorkingDirectory=/opt/myapp
ExecStart=/usr/local/bin/monitor_watcher --foreground
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl enable processmonitor processmonitor-watcher
sudo systemctl start processmonitor processmonitor-watcher
```

## Docker Integration

**Dockerfile:**

```dockerfile
FROM dart:stable AS build
WORKDIR /app
COPY . .
RUN dart pub get
RUN dart compile exe bin/process_monitor.dart -o process_monitor

FROM debian:stable-slim
COPY --from=build /app/process_monitor /usr/local/bin/
ENTRYPOINT ["/usr/local/bin/process_monitor", "--foreground"]
```

**docker-compose.yml:**

```yaml
version: '3.8'
services:
  processmonitor:
    build: .
    volumes:
      - pm-data:/root/.tom/process_monitor
    ports:
      - "5679:5679"
      - "5681:5681"

volumes:
  pm-data:
```

## Troubleshooting

### Process not starting

**Symptom:** `process_monitor` exits immediately

**Solutions:**
1. Try running with `--foreground` to see error messages
2. Check if another instance is already running
3. Verify port availability (5679, 5681)

### Cannot connect to running instance

**Symptom:** `--status` or `--stop` shows "not running or unreachable"

**Solutions:**
1. Verify the instance is actually running: `ps aux | grep process_monitor`
2. Check if the remote API port (5679) is accessible
3. Verify you're using the correct `--directory` if using a custom path

### Permission errors

**Symptom:** "Permission denied" errors

**Solutions:**
1. Check directory permissions for `~/.tom/process_monitor/`
2. If using custom directory, ensure it's writable
3. Check lock file permissions

### Port already in use

**Symptom:** "Address already in use" error

**Solutions:**
1. Check for other instances: `lsof -i :5679` and `lsof -i :5681`
2. Kill any orphaned processes
3. Wait for the port to be released (may take up to 60 seconds)

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error (see error message) |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `VSCODE_WORKSPACE_FOLDER` | If set, uses this as the base for the default directory |
| `HOME` | User home directory for default path resolution |

## See Also

- [ProcessMonitor User Guide](processmonitor_user_guide.md) - Full API documentation
- [ProcessMonitor Specification](processmonitor_specification.md) - Technical specification
