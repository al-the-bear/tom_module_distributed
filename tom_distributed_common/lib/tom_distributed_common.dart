/// Common utilities for Tom distributed packages.
///
/// Provides shared functionality for distributed systems:
/// - HTTP retry logic with exponential backoff
/// - Network server discovery
library;

export 'src/http_retry.dart';
export 'src/server_discovery.dart';
