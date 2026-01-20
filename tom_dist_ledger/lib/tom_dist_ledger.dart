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
/// - **simulator**: Simulation tools for testing DPL flows
library;

// Ledger API - high-level operation management
export 'src/ledger_api/ledger_api.dart';

// Local Ledger - file-based storage implementation
export 'src/local_ledger/file_ledger.dart';

// Simulator - testing and simulation utilities
export 'src/simulator/simulation_config.dart';
export 'src/simulator/async_simulation.dart';
export 'src/simulator/async_dpl_simulator.dart';
export 'src/simulator/scenario.dart';
export 'src/simulator/scenarios.dart';
export 'src/simulator/participants/async_sim_tom_cli.dart';
export 'src/simulator/participants/async_sim_dartscript_bridge.dart';
export 'src/simulator/participants/async_sim_vscode_extension.dart';
export 'src/simulator/participants/async_sim_copilot_chat.dart';
