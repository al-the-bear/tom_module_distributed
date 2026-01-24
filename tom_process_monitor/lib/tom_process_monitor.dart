/// Process lifecycle management with file-based registry and HTTP APIs.
///
/// This package provides automated process lifecycle management including:
/// - File-based process registry
/// - Local and remote client APIs
/// - HTTP aliveness checking
/// - Mutual monitoring (default + watcher instances)
library;

// Core types
export 'src/models/process_config.dart';
export 'src/models/process_entry.dart';
export 'src/models/process_state.dart';
export 'src/models/process_status.dart';
export 'src/models/monitor_status.dart';
export 'src/models/restart_policy.dart';
export 'src/models/aliveness_check.dart';
export 'src/models/startup_check.dart';
export 'src/models/remote_access_config.dart';
export 'src/models/partner_discovery_config.dart';
export 'src/models/registry.dart';

// Exceptions
export 'src/exceptions/process_monitor_exception.dart';
export 'src/exceptions/lock_timeout_exception.dart';
export 'src/exceptions/process_not_found_exception.dart';
export 'src/exceptions/process_disabled_exception.dart';
export 'src/exceptions/permission_denied_exception.dart';

// Core services
export 'src/services/registry_lock.dart';
export 'src/services/registry_service.dart';
export 'src/services/process_control.dart';
export 'src/services/aliveness_server.dart';
export 'src/services/aliveness_checker.dart';
export 'src/services/log_manager.dart';

// Client APIs
export 'src/client/process_monitor_client.dart';
export 'src/client/remote_process_monitor_client.dart';

// HTTP API
export 'src/http/remote_api_server.dart';

// Main daemon
export 'src/process_monitor.dart';
