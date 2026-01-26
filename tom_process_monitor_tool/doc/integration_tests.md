# Integration Tests

This document describes how to run integration tests for the Process Monitor system.

## Prerequisites

1. **Ensure no other ProcessMonitor is running** on the test ports:
   ```bash
   lsof -i :19891
   lsof -i :19893
   ```

2. **Start process_monitor** in a separate terminal (optional - tests can start it):
   ```bash
   TOM_PM_API_PORT=19891 TOM_PM_ALIVENESS_PORT=19893 \
     dart run bin/process_monitor.dart --foreground --directory=/tmp/pm_test
   ```

## Running Tests

### Run All Integration Tests

```bash
cd tom_process_monitor_tool
dart test test/integration/ -t integration
```

### Run Specific Test Groups

```bash
# Startup tests only
dart test test/integration/ -t integration --name "Process Monitor Startup"

# Basic operations tests
dart test test/integration/ -t integration --name "RemoteProcessMonitorClient Basic Operations"

# Kill and restart tests (longer timeout)
dart test test/integration/ -t integration --name "Monitor Kill and Restart"

# State persistence tests
dart test test/integration/ -t integration --name "Process State Persistence"
```

## Test Configuration

| Setting | Value | Description |
|---------|-------|-------------|
| API Port | 19891 | Test HTTP API port (different from production 19881) |
| Aliveness Port | 19893 | Test aliveness port (different from production 19883) |
| Retry Delays | 2, 4, 8, 16, 32s | Standard retry backoff |
| Test Timeout | 2 minutes | For kill/restart tests |

## Test Scenarios

### Basic Operations
- Client gets monitor status
- Client gets all process status
- Client registers and deregisters a process
- Client starts and stops a process
- Client enables and disables a process

### Monitor Kill and Restart
- Operation fails when monitor is killed (after retry exhaustion)
- Operations succeed after monitor restart
- Client retries during brief monitor unavailability

### State Persistence
- Process registration persists across monitor restarts

### Watcher Kill Scenario
- Process monitor detects watcher absence (manual testing)

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TOM_PM_API_PORT` | 19881 | HTTP API port |
| `TOM_PM_ALIVENESS_PORT` | 19883 | Aliveness check port |

## Troubleshooting

### Tests fail with "Connection refused"
The tests start the monitor automatically. If tests fail, check:
- Port conflicts with other services
- Previous test runs that didn't clean up properly

### Process registration tests fail
Ensure you have permissions to run `/bin/echo` and `/bin/sleep`.

### Tests hang
Kill any orphaned process_monitor processes:
```bash
pkill -f "dart.*process_monitor"
```
