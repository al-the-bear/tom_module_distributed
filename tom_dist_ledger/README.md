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
- **Backup trails** for debugging and recovery

## Package Structure

The package is organized into three parts:

### Ledger API (`ledger_api`)

High-level API for operation management:

- `Ledger` - Global manager for all operations
- `Operation` - Per-participant handle with caching
- Heartbeat with error/success callbacks
- Call execution tracking (`startCallExecution`/`endCallExecution`)

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

```dart
import 'package:tom_dist_ledger/tom_dist_ledger.dart';

// Create a ledger at a workspace path
final ledger = Ledger(
  basePath: '/workspace/_ai/operation_ledger',
);

// Start an operation (initiator)
final operation = await ledger.startOperation(
  operationId: 'op_${DateTime.now().millisecondsSinceEpoch}',
  initiatorPid: pid,
  participantId: 'cli',
  getElapsedFormatted: () => '000.000',
);

// Start heartbeat
operation.startHeartbeat(
  onError: (op, error) => print('Heartbeat error: $error'),
  onSuccess: (op, result) => print('Heartbeat OK'),
);

// Track call execution
await operation.startCallExecution(callId: 'invoke-1');

// ... do work ...

await operation.endCallExecution(callId: 'invoke-1');

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
  port: 19876,
);

print('Server running on port ${server.port}');

// Stop when done
await server.stop();
```

### Connecting a Client

The recommended way to create a client is using `connect()`, which supports
both explicit server URLs and auto-discovery:

```dart
// Auto-discover a server on the network
final client = await RemoteLedgerClient.connect(
  participantId: 'my_client',
);

// Or connect to a specific server
final client = await RemoteLedgerClient.connect(
  serverUrl: 'http://localhost:19876',
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
  serverUrl: 'http://localhost:19876',
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
  port: 19876,
  timeout: Duration(seconds: 1),      // Connection timeout per host
  scanSubnet: true,                   // Enable subnet scanning
  logger: (msg) => print(msg),        // Optional progress logging
);
```

Or use `ServerDiscovery` directly to find all available servers:

```dart
final servers = await ServerDiscovery.discoverAll(
  DiscoveryOptions(
    port: 19876,
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
