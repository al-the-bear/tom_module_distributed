# TypeScript Distributed Clients Guide

This guide explains how to use the `tom_distributed_typescript` library to interact with the Tom Distributed System components: the Distributed Ledger and the Process Monitor.

## Installation

```bash
npm install tom_distributed_typescript
# or
yarn add tom_distributed_typescript
```

## Ledger Client

The `LedgerClient` allows you to interact with the key-value store of the distributed ledger.

### Usage

```typescript
import { LedgerClient } from 'tom_distributed_typescript';

const client = new LedgerClient({
  baseUrl: 'http://localhost:19880' // Default
});

// Write a value
await client.put('my-key', { some: 'data' });

// Read a value
const entry = await client.get('my-key');
console.log(entry?.value);

// List keys
const keys = await client.list('my-');
```

## Process Monitor Client

The `ProcessMonitorClient` allows you to manage processes running under the Tom Process Monitor.

### Usage

```typescript
import { ProcessMonitorClient } from 'tom_distributed_typescript';

const monitor = new ProcessMonitorClient({
  baseUrl: 'http://localhost:19881' // Default for main instance
});

// List processes
const processes = await monitor.getProcesses();
processes.forEach(p => {
  console.log(`${p.name} (${p.state})`);
});

// Control processes
await monitor.startProcess('my-worker');
await monitor.restartProcess('legacy-service');
```

## Deno Usage

This library is compatible with Deno. You can import the source files directly if you have them locally, or via a simplified build (not currently published to deno.land).

Example:

```typescript
import { LedgerClient } from './src/ledger_client.ts';
// Note: Requires dependencies to be resolved via import map or deno.json
```
