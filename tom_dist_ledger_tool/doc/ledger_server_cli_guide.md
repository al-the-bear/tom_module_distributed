# Ledger Server CLI Guide

Guide to running the Distributed Ledger HTTP Server using the command-line tool.

---

## Table of Contents

1. [Overview](#overview)
2. [Installation](#installation)
3. [Starting the Server](#starting-the-server)
4. [Command-Line Options](#command-line-options)
5. [Server Endpoints](#server-endpoints)
6. [Client Configuration](#client-configuration)
7. [Monitoring and Debugging](#monitoring-and-debugging)
8. [Deployment Scenarios](#deployment-scenarios)

---

## Overview

The Ledger Server provides HTTP access to the Distributed Ledger, allowing remote clients to participate in coordinated operations over the network.

### Key Features

- **Stateless HTTP server** - Each request reads/writes files directly
- **REST API** - Simple JSON-based request/response format
- **Participant identification** - Clients identify themselves with each request
- **Full ledger API** - Create, join, heartbeat, and complete operations

### Architecture

```
┌──────────────────┐        HTTP        ┌──────────────────┐
│ RemoteLedgerClient│ ◄───────────────► │  LedgerServer    │
│ (remote_worker)  │                    │                  │
└──────────────────┘                    │  ┌────────────┐  │
                                        │  │   Ledger   │  │
┌──────────────────┐        HTTP        │  │ (file-based)│  │
│ RemoteLedgerClient│ ◄───────────────► │  └────────────┘  │
│ (worker_2)       │                    │                  │
└──────────────────┘                    └──────────────────┘
                                                │
                                                ▼
                                        ┌──────────────────┐
                                        │  Ledger Files    │
                                        │  /tmp/ledger/    │
                                        └──────────────────┘
```

---

## Installation

### From Source

Build and install the CLI tool:

```bash
cd tom_dist_ledger_tool
dart pub get
dart compile exe bin/ledger_server.dart -o ledger_server
```

### Running Directly

Or run directly with Dart:

```bash
dart run tom_dist_ledger_tool:ledger_server
```

---

## Starting the Server

### Basic Usage

Start with default settings (port 19880, current directory):

```bash
./ledger_server
```

Output:

```
Starting Distributed Ledger Server...
  Port: 19880
  Base path: /current/directory
Server listening on http://localhost:19880
Press Ctrl+C to stop.
```

### With Custom Port

```bash
./ledger_server --port=9000
```

Or using the short form:

```bash
./ledger_server -p 9000
```

### With Custom Path

```bash
./ledger_server --path=/var/lib/ledger
```

Or using the short form:

```bash
./ledger_server -d /var/lib/ledger
```

### Combined Options

```bash
./ledger_server --port=9000 --path=/var/lib/ledger
```

---

## Command-Line Options

| Option | Short | Default | Description |
|--------|-------|---------|-------------|
| `--port=<n>` | `-p <n>` | `19880` | Port to listen on |
| `--path=<dir>` | `-d <dir>` | Current directory | Directory for ledger files |

### Examples

```bash
# Listen on port 9000
./ledger_server --port=9000

# Use a specific directory
./ledger_server --path=/data/ledger

# Both options
./ledger_server -p 9000 -d /data/ledger
```

---

## Server Endpoints

### Health Check

```bash
curl http://localhost:19880/health
```

Response:

```json
{"status": "ok"}
```

### Create Operation

```bash
curl -X POST http://localhost:19880/operation/create \
  -H "Content-Type: application/json" \
  -d '{"participantId": "cli", "description": "Test operation"}'
```

Response:

```json
{
  "operationId": "20260122T14:30:45.123-cli-a1b2c3d4",
  "participantId": "cli",
  "isInitiator": true,
  "sessionId": 1,
  "startTime": "2026-01-22T14:30:45.123Z"
}
```

### Join Operation

```bash
curl -X POST http://localhost:19880/operation/join \
  -H "Content-Type: application/json" \
  -d '{"operationId": "20260122T14:30:45.123-cli-a1b2c3d4", "participantId": "worker-1"}'
```

### Send Heartbeat

```bash
curl -X POST http://localhost:19880/operation/heartbeat \
  -H "Content-Type: application/json" \
  -d '{"operationId": "20260122T14:30:45.123-cli-a1b2c3d4"}'
```

Response:

```json
{
  "success": true,
  "abortFlag": false,
  "callFrameCount": 1,
  "participants": ["cli", "worker-1"],
  "staleParticipants": []
}
```

### Start Call

```bash
curl -X POST http://localhost:19880/call/start \
  -H "Content-Type: application/json" \
  -d '{"operationId": "20260122T14:30:45.123-cli-a1b2c3d4", "sessionId": 1, "description": "Process data"}'
```

Response:

```json
{
  "callId": "call_cli_1_a1b2",
  "startedAt": "2026-01-22T14:30:46.000Z"
}
```

### End Call

```bash
curl -X POST http://localhost:19880/call/end \
  -H "Content-Type: application/json" \
  -d '{"operationId": "20260122T14:30:45.123-cli-a1b2c3d4", "callId": "call_cli_1_a1b2"}'
```

### Complete Operation

```bash
curl -X POST http://localhost:19880/operation/complete \
  -H "Content-Type: application/json" \
  -d '{"operationId": "20260122T14:30:45.123-cli-a1b2c3d4"}'
```

---

## Client Configuration

### Dart Client

The `RemoteLedgerClient` provides the **same typed API** as the local `Ledger`:

```dart
import 'package:tom_dist_ledger/tom_dist_ledger.dart';

final client = RemoteLedgerClient(
  serverUrl: 'http://localhost:19880',
  participantId: 'my_app',
  heartbeatInterval: Duration(seconds: 5),
  staleThreshold: Duration(seconds: 15),
);

// Create or join operations
final operation = await client.createOperation(
  description: 'Remote task',
);

// Do typed work with callbacks - same API as local!
final call = await operation.startCall<String>(
  callback: CallCallback<String>(
    onCompletion: (result) async => print('Got: $result'),
    onCleanup: () async => await cleanup(),
  ),
);

try {
  final result = await doWork();
  await call.end(result);
} catch (e, st) {
  await call.fail(e, st);
}

// Or spawn calls for parallel work
final spawned1 = operation.spawnCall<int>(work: () async => 1);
final spawned2 = operation.spawnCall<int>(work: () async => 2);
final syncResult = await operation.sync([spawned1, spawned2]);

// Complete and cleanup
await operation.complete();
client.dispose();
```

### Unified API

The remote client provides the same API as local operations:

| Feature | Description |
|---------|-------------|
| `startCall<T>()` | Returns `Call<T>` with typed result |
| `spawnCall<T>()` | Returns `SpawnedCall<T>` for async work |
| `CallCallback<T>` | Full callback support (client-side) |
| `sync()` | Wait for multiple spawned calls |
| Session tracking | `hasPendingCalls()`, `getPendingCalls()` |

### Connection Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `serverUrl` | Required | Full URL including port |
| `participantId` | Required | Unique client identifier |
| `heartbeatInterval` | 5 seconds | How often to send heartbeats |
| `staleThreshold` | 15 seconds | When to consider participant crashed |

---

## Monitoring and Debugging

### Server Output

The server logs all requests and errors to stderr:

```
Starting Distributed Ledger Server...
  Port: 19880
  Base path: /tmp/ledger
Server listening on http://localhost:19880
```

Errors are logged with full stack traces:

```
Error handling request: FileSystemException: Cannot open file
  at _handleRequest (ledger_server.dart:95)
  ...
```

### Ledger Files

The server stores files in the specified base path:

```
{basePath}/
├── {operationId}.operation.json     # Operation state
├── {operationId}.operation.log      # Human-readable log
├── {operationId}.operation.debug.log # Debug log
└── backup/
    └── {operationId}/               # Completed/failed operations
```

### Checking Operation State

Read the operation file directly:

```bash
cat /tmp/ledger/*.operation.json | jq .
```

Or check via API:

```bash
curl -X POST http://localhost:19880/operation/state \
  -H "Content-Type: application/json" \
  -d '{"operationId": "..."}'
```

### Viewing Logs

```bash
# Human-readable log
tail -f /tmp/ledger/*.operation.log

# Debug log
tail -f /tmp/ledger/*.operation.debug.log
```

---

## Deployment Scenarios

### Local Development

Run on localhost for development:

```bash
./ledger_server --port=19880 --path=./ledger_data
```

### Docker Container

Example Dockerfile:

```dockerfile
FROM dart:stable AS build
WORKDIR /app
COPY . .
RUN dart pub get
RUN dart compile exe bin/ledger_server.dart -o ledger_server

FROM debian:buster-slim
COPY --from=build /app/ledger_server /usr/local/bin/
VOLUME /data
EXPOSE 19880
CMD ["ledger_server", "--port=19880", "--path=/data"]
```

Run with:

```bash
docker run -p 19880:19880 -v $(pwd)/ledger_data:/data ledger-server
```

### Systemd Service

Create `/etc/systemd/system/ledger-server.service`:

```ini
[Unit]
Description=Distributed Ledger Server
After=network.target

[Service]
Type=simple
User=ledger
ExecStart=/usr/local/bin/ledger_server --port=19880 --path=/var/lib/ledger
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl enable ledger-server
sudo systemctl start ledger-server
```

### Production Considerations

1. **Persistent storage** - Use a persistent volume for ledger files
2. **Firewall rules** - Restrict access to trusted clients
3. **TLS termination** - Use a reverse proxy for HTTPS
4. **Monitoring** - Add health check monitoring
5. **Backup** - Periodically backup the ledger directory

### Behind Nginx

Example nginx configuration:

```nginx
upstream ledger {
    server 127.0.0.1:19880;
}

server {
    listen 443 ssl;
    server_name ledger.example.com;
    
    ssl_certificate /etc/ssl/certs/ledger.crt;
    ssl_certificate_key /etc/ssl/private/ledger.key;
    
    location / {
        proxy_pass http://ledger;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

---

## Troubleshooting

### Port Already in Use

```
SocketException: Address already in use
```

Choose a different port or stop the existing process:

```bash
lsof -i :19880
kill <PID>
```

### Permission Denied

```
FileSystemException: Permission denied
```

Ensure the user has write access to the base path:

```bash
sudo chown -R $USER:$USER /var/lib/ledger
```

### Client Connection Refused

```
RemoteLedgerException: Connection refused
```

Check that:
- Server is running
- Port is correct
- Firewall allows the connection

---

*Generated from tom_dist_ledger_tool v2.0 implementation*
