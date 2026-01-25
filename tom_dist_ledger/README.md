# Tom Distributed Ledger

A file-based Distributed Processing Ledger (DPL) for coordinating multi-process
operations in the Tom ecosystem.

## Overview

Tom Distributed Ledger provides a shared state machine for distributed operations
across multiple processes (CLI, VS Code Extension, AI Scripts). It enables:

- **Operation tracking** across process boundaries
- **Heartbeat monitoring** with automatic stale detection
- **Abort propagation** from any participant
- **Temporary resource registration** with guaranteed cleanup
- **Signal-based cleanup** via SIGINT/SIGTERM handlers
- **Backup trails** for debugging and recovery

## Package Structure

The package is organized into three parts:

### Ledger API (`ledger_api`)

High-level API for operation management:

- `Ledger` - Abstract base class for all ledger implementations
- `LocalLedger` - Local file-based ledger implementation  
- `RemoteLedgerClient` - HTTP client for remote ledger servers
- `Operation` - Abstract base class with unified API for both local and remote
- `LocalOperation` / `RemoteOperation` - Concrete implementations (rarely used directly)
- `CleanupHandler` - Signal-based cleanup for SIGINT/SIGTERM
- `Ledger.connect()` - Unified factory method for both local and remote access
- Heartbeat with error/success callbacks
- Call execution tracking (`startCall`/`endCall`, `spawnCall`/`sync`)

### Local Ledger (`local_ledger`)

File-based storage implementation:

- `FileLedger` - Low-level file operations with locking
- `LedgerData`, `StackFrame`, `TempResource` - Data structures
- Atomic read-modify-write with automatic backup

### Simulator (`simulator`)

Testing and simulation utilities:

- `AsyncDPLSimulator` - Main simulation orchestrator
- `AsyncSimParticipant` - Base class for simulated participants
- Pre-built participants: CLI, Bridge, VSCode Extension, Copilot Chat

## Usage

### Using Ledger.connect() (Recommended)

The easiest way to work with ledgers is through the unified `Ledger.connect()` factory:

```dart
import 'package:tom_dist_ledger/tom_dist_ledger.dart';

// Connect to a local ledger
final ledger = await Ledger.connect(
  basePath: '/workspace/_ai/operation_ledger',
  participantId: 'cli',
);

// Or connect to a remote server (with auto-discovery)
final ledger = await Ledger.connect(
  participantId: 'cli',
);

// Or connect to a specific server
final ledger = await Ledger.connect(
  serverUrl: 'http://localhost:19880',
  participantId: 'cli',
);

if (ledger != null) {
  final op = await ledger.createOperation();
  // ... do work ...
  await ledger.dispose();
}
```

### Using LocalLedger Directly

For local file-based operations:

```dart
import 'package:tom_dist_ledger/tom_dist_ledger.dart';

// Create a local ledger at a workspace path
final ledger = LocalLedger(
  basePath: '/workspace/_ai/operation_ledger',
  participantId: 'cli',
);

// Start an operation (initiator)
final operation = await ledger.createOperation();

// Start heartbeat
operation.startHeartbeat(
  onError: (op, error) => print('Heartbeat error: $error'),
  onSuccess: (op, result) => print('Heartbeat OK'),
);

// Track call execution
await operation.createCallFrame(callId: 'invoke-1');

// ... do work ...

await operation.deleteCallFrame(callId: 'invoke-1');

// Complete the operation
await operation.complete();
```

## Default Ledger Path

The default ledger path is `_ai/operation_ledger` relative to the workspace root.
When configuring the simulation or ledger, provide an absolute path:

```dart
final config = SimulationConfig(
  ledgerPath: '/path/to/workspace/_ai/operation_ledger',
);
```

## Documentation

See [doc/distributed_operation_ledger_proposal.md](doc/distributed_operation_ledger_proposal.md)
for the full protocol specification.

## Remote Ledger Server

For distributed deployments where processes run on different machines, use the
HTTP-based ledger server:

### Starting a Server

```dart
import 'package:tom_dist_ledger/tom_dist_ledger.dart';

// Start server on a specific port
final server = await LedgerServer.start(
  basePath: '/path/to/ledger',
  port: 19880,
);

print('Server running on port ${server.port}');

// Stop when done
await server.stop();
```

### Connecting a Client

Use `Ledger.connect()` for the simplest connection (recommended):

```dart
// Auto-discover a server on the network
final ledger = await Ledger.connect(
  participantId: 'my_client',
);

// Or connect to a specific server
final ledger = await Ledger.connect(
  serverUrl: 'http://localhost:19880',
  participantId: 'my_client',
);

if (ledger != null) {
  final op = await ledger.createOperation();
  // ... do work ...
  await ledger.dispose();
}
```

Or use `RemoteLedgerClient.connect()` directly for more control:

```dart
// Auto-discover a server on the network
final client = await RemoteLedgerClient.connect(
  participantId: 'my_client',
);

// Or connect to a specific server
final client = await RemoteLedgerClient.connect(
  serverUrl: 'http://localhost:19880',
  participantId: 'my_client',
);

if (client != null) {
  final op = await client.createOperation();
  final call = await op.startCall<String>();
  await call.end('result');
  await op.complete();
  client.dispose();
}
```

For synchronous construction when you already have the server URL:

```dart
final client = RemoteLedgerClient(
  serverUrl: 'http://localhost:19880',
  participantId: 'my_client',
);
```

### Auto-Discovery

When `serverUrl` is not provided to `connect()`, clients automatically
discover running ledger servers on the local network.

Discovery scans in this order:
1. `localhost` / `127.0.0.1`
2. Local machine's IP addresses
3. All IPs in the local subnet (e.g., 192.168.1.1-255)

Configure discovery options:

```dart
final client = await RemoteLedgerClient.connect(
  participantId: 'client',
  port: 19880,
  timeout: Duration(seconds: 1),      // Connection timeout per host
  scanSubnet: true,                   // Enable subnet scanning
  logger: (msg) => print(msg),        // Optional progress logging
);
```

Or use `ServerDiscovery` directly to find all available servers:

```dart
final servers = await ServerDiscovery.discoverAll(
  DiscoveryOptions(
    port: 19880,
    timeout: Duration(milliseconds: 500),
    scanSubnet: true,
  ),
);

for (final server in servers) {
  print('Found: ${server.serverUrl} - ${server.service}');
}
```

## Running the Simulator

```dart
import 'package:tom_dist_ledger/tom_dist_ledger.dart';

void main() async {
  final config = SimulationConfig(
    ledgerPath: '/tmp/test_ledger',
    callDelayMs: 1000,
    externalCallResponseMs: 3000,
  );
  
  final simulator = AsyncDPLSimulator(config: config);
  
  await simulator.runNormalFlow();
  // or: await simulator.runAbortFlow();
  
  simulator.dispose();
}
```
