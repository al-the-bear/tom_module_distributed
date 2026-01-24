/// Tom Distributed Ledger - Distributed Processing Ledger (DPL) implementation.
///
/// This package provides a file-based distributed ledger for coordinating
/// multi-process operations with heartbeat monitoring, abort handling,
/// and temporary resource tracking.
///
/// ## Parts
///
/// - **ledger_api**: High-level API with `Ledger` and `Operation` classes
/// - **local_ledger**: Low-level file-based ledger implementation
///
/// For simulation and testing utilities, use
/// `package:tom_dist_ledger/test_simulator.dart`.
library;

// Ledger API - high-level operation management
export 'src/ledger_api/ledger_api.dart';

// Local Ledger - file-based storage implementation
export 'src/ledger_local/file_ledger.dart';
