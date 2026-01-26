# Integration Tests

This document describes how to run integration tests for the TypeScript distributed system clients.

## Prerequisites

1. **Install dependencies**:
   ```bash
   cd tom_distributed_typescript
   npm install
   ```

2. **Start the backend servers** in separate terminals:
   
   **Ledger Server:**
   ```bash
   cd tom_dist_ledger_tool
   dart run bin/ledger_server.dart --port=19880
   ```
   
   **Process Monitor:**
   ```bash
   cd tom_process_monitor_tool
   dart run bin/process_monitor.dart --foreground
   ```

## Running Tests

### Run All Tests

```bash
cd tom_distributed_typescript
npm test
```

### Run Integration Tests Only

```bash
npm run test:integration
```

### Run with Verbose Output

```bash
npm test -- --verbose
```

### Run Specific Test Suites

```bash
# LedgerClient tests only
npm test -- --testNamePattern="LedgerClient"

# ProcessMonitorClient tests only
npm test -- --testNamePattern="ProcessMonitorClient"

# Retry behavior tests only
npm test -- --testNamePattern="Client Retry Behavior"
```

## Test Configuration

| Setting | Value | Description |
|---------|-------|-------------|
| Ledger URL | http://localhost:19880 | Default ledger server |
| Monitor URL | http://localhost:19881 | Default process monitor |
| Retry Delays | 2, 4, 8, 16, 32s | Standard retry backoff |
| Test Timeout | 120 seconds | For retry behavior tests |

## Test Scenarios

### LedgerClient
- Get non-existent key (returns null)
- Put and get a value
- Delete a value
- List keys with prefix
- Handle version conflicts

### ProcessMonitorClient
- Get process list
- Start a process
- Handle non-existent process gracefully

### Client Retry Behavior
- LedgerClient fails after retries when server unavailable
- ProcessMonitorClient fails after retries when monitor unavailable

## npm Scripts

| Script | Description |
|--------|-------------|
| `npm test` | Run all tests |
| `npm run test:integration` | Run integration tests with extended timeout |
| `npm run build` | Compile TypeScript |

## Troubleshooting

### "Cannot find module" errors
Run `npm install` to install dependencies.

### Tests skip with warnings
The servers aren't running. Start them as described in Prerequisites.

### Retry tests are slow
The retry behavior tests take ~60+ seconds because they test the full retry sequence.

### TypeScript compilation errors
Run `npm run build` to check for type errors:
```bash
npm run build
```

## Jest Configuration

The Jest configuration is in `jest.config.js`:
- Preset: ts-jest
- Test environment: node
- Test files: `test/**/*.test.ts`
