# Tom Distributed Ledger Tool

Command-line tool for running a Distributed Ledger HTTP Server.

## Overview

This tool starts an HTTP server that exposes the ledger API for remote clients.
Clients can connect using `RemoteLedgerClient` from the `tom_dist_ledger` package
to perform distributed operations across machines.

## Usage

### Starting the Server

```bash
# Start with defaults (port 19880, current directory)
dart run bin/ledger_server.dart

# Specify port
dart run bin/ledger_server.dart --port=9000
dart run bin/ledger_server.dart -p 9000

# Specify ledger path
dart run bin/ledger_server.dart --path=/path/to/ledger
dart run bin/ledger_server.dart -d /path/to/ledger

# Full example
dart run bin/ledger_server.dart --port=19880 --path=~/.tom/operation_ledger
```

### Server Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/status` | GET | Server status and health check |
| `/operations` | POST | Create new operation |
| `/operations/:id` | GET | Get operation state |
| `/operations/:id` | POST | Operation actions (startCall, endCall, heartbeat, etc.) |

### CORS Support

The server supports CORS for all origins (`*`), enabling web applications (like local dashboards) to query the ledger status and operations directly.

### Connecting a Client

The recommended way to connect is using `connect()`, which supports both
explicit server URLs and auto-discovery:

```dart
import 'package:tom_dist_ledger/tom_dist_ledger.dart';

// Auto-discover server on default port 19880
final client = await RemoteLedgerClient.connect(
  participantId: 'my_client',
);

if (client != null) {
  print('Found server at ${client.serverUrl}');
  final op = await client.createOperation();
  // ... use operation
  client.dispose();
}

// Or connect to a known server
final client = await RemoteLedgerClient.connect(
  serverUrl: 'http://192.168.1.100:19880',
  participantId: 'known_client',
);
```

### Auto-Discovery

When `serverUrl` is not provided, clients automatically discover running
ledger servers by scanning:

1. localhost / 127.0.0.1
2. Local machine's IP addresses
3. All IPs in the local subnet (e.g., 192.168.1.1-255)

### Direct Construction

For synchronous construction when you already have the server URL:

```dart
final client = RemoteLedgerClient(
  serverUrl: 'http://192.168.1.100:19880',
  participantId: 'known_client',
);
```

## Default Port

The default port is **19880**. This is used by both the server and client
auto-discovery.

## Stopping the Server

Press `Ctrl+C` to gracefully shut down the server.

