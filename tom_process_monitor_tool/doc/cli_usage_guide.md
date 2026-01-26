# ProcessMonitor CLI Guide

This guide covers the command-line interface tool for ProcessMonitor: `process_monitor`.

## Overview

ProcessMonitor provides the main daemon CLI tool:

| Tool | Description | Default Ports |
|------|-------------|---------------|
| `process_monitor` | Main ProcessMonitor daemon | Aliveness: 19883, Remote: 19881 |

## Installation

### From Source

```bash
cd tom_process_monitor_tool
dart pub get
dart compile exe bin/process_monitor.dart -o process_monitor
```

### Using Dart Run

```bash
dart run tom_process_monitor_tool:process_monitor
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
```
