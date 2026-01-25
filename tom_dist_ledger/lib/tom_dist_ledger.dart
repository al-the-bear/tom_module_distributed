/// Tom Distributed Ledger - Distributed Processing Ledger (DPL) implementation.
///
/// This package provides a file-based distributed ledger for coordinating
/// multi-process operations with heartbeat monitoring, abort handling,
/// and temporary resource tracking.
///
/// ## Parts
///
/// - **ledger_api**: High-level API with `Ledger` and `Operation` classes
/// - **ledger_local**: Low-level file-based ledger implementation
/// - **ledger_server**: HTTP server for remote ledger access (part of ledger_api)
/// - **ledger_client**: HTTP client for remote ledger access
///
/// For simulation and testing utilities, use
/// `package:tom_dist_ledger/test_simulator.dart`.
library;

// Ledger API - high-level operation management (includes LedgerServer)
export 'src/ledger_api/ledger_api.dart';

// Local Ledger - file-based storage implementation
export 'src/ledger_local/file_ledger.dart';

// Remote Ledger Client - HTTP client for remote access
export 'src/ledger_client/remote_ledger_client.dart';

// Server Discovery - auto-discovery for remote servers
export 'src/ledger_client/server_discovery.dart';
