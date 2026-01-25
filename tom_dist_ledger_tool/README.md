# Tom Distributed Ledger Tool

Command-line tool for running a Distributed Ledger HTTP Server.

## Overview

This tool starts an HTTP server that exposes the ledger API for remote clients.
Clients can connect using `RemoteLedgerClient` from the `tom_dist_ledger` package
to perform distributed operations across machines.

## Usage

### Starting the Server

```bash
# Start with defaults (port 8765, current directory)
dart run bin/ledger_server.dart

# Specify port
dart run bin/ledger_server.dart --port=9000
dart run bin/ledger_server.dart -p 9000

# Specify ledger path
dart run bin/ledger_server.dart --path=/path/to/ledger
dart run bin/ledger_server.dart -d /path/to/ledger

# Full example
dart run bin/ledger_server.dart --port=8765 --path=/workspace/_ai/ledger
```

### Server Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/status` | GET | Server status and health check |
| `/operations` | POST | Create new operation |
| `/operations/:id` | GET | Get operation state |
| `/operations/:id` | POST | Operation actions (startCall, endCall, heartbeat, etc.) |

### Client Auto-Discovery

Clients can automatically discover the server using the `/status` endpoint:

```dart
import 'package:tom_dist_ledger/tom_dist_ledger.dart';

// Auto-discover server on default port 8765
final client = await RemoteLedgerClient.discover(
  participantId: 'my_client',
);

if (client != null) {
  print('Found server at ${client.serverUrl}');
  final op = await client.createOperation();
  // ... use operation
  client.dispose();
}
```

Discovery scans:
1. localhost / 127.0.0.1
2. 0.0.0.0
3. All subnet IPs (xxx.xxx.xxx.1-255)

### Direct Connection

If you know the server address:

```dart
final client = RemoteLedgerClient(
  serverUrl: 'http://192.168.1.100:8765',
  participantId: 'known_client',
);
```

## Default Port

The default port is **8765**. This is used by both the server and client
auto-discovery.

## Stopping the Server

Press `Ctrl+C` to gracefully shut down the server.

