# Integration Tests

This document describes how to run integration tests for the Distributed Ledger system.

## Prerequisites

1. **Build the ledger server** (optional, for faster startup):
   ```bash
   cd tom_dist_ledger_tool
   dart compile exe bin/ledger_server.dart -o bin/ledger_server
   ```

2. **Start the ledger server** in a separate terminal:
   ```bash
   dart run bin/ledger_server.dart --port=19890 --path=/tmp/ledger_test
   ```

## Running Tests

### Run All Integration Tests

```bash
cd tom_dist_ledger_tool
dart test test/integration/ -t integration
```

### Run Specific Test Groups

```bash
# Server startup tests only
dart test test/integration/ -t integration --name "Ledger Server Startup"

# Basic operations tests
dart test test/integration/ -t integration --name "RemoteLedgerClient Basic Operations"

# Kill and restart tests (longer timeout)
dart test test/integration/ -t integration --name "Server Kill and Restart"

# Concurrent client tests
dart test test/integration/ -t integration --name "Concurrent Client Operations"
```

## Test Configuration

| Setting | Value | Description |
|---------|-------|-------------|
| Default Port | 19890 | Test server port (different from production 19880) |
| Retry Delays | 2, 4, 8, 16, 32s | Standard retry backoff |
| Test Timeout | 2 minutes | For kill/restart tests |

## Test Scenarios

### Basic Operations
- Client connects and creates operation
- Client creates and ends call with result
- Client handles multiple sequential operations
- Client logs messages during operation

### Server Kill and Restart
- Operation fails when server is killed (after retry exhaustion)
- Operations succeed after server restart
- Client retries during brief server unavailability

### Concurrent Operations
- Multiple clients can operate concurrently

## Troubleshooting

### Tests fail immediately
Ensure the ledger server is running before starting tests.

### Tests hang
Check that the test port (19890) is not already in use:
```bash
lsof -i :19890
```

### Retry tests take too long
The kill/restart tests have a 2-minute timeout because they test the full retry sequence (up to 62 seconds of retries).
