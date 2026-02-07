/// HTTP client for remote ledger access.
///
/// This client communicates with a LedgerServer to provide remote access
/// to the distributed ledger. It maintains the same API as the local Ledger
/// so clients can use either local or remote access transparently.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tom_basics_network/tom_basics_network.dart';

import '../ledger_api/ledger_api.dart';
import '../ledger_local/file_ledger.dart';

/// HTTP client for remote ledger access.
///
/// Provides the same API as [Ledger] but communicates with a remote
/// [LedgerServer] via HTTP. Session tracking, call management, and callbacks
/// are handled client-side. The server only manages the ledger file access.
///
/// ## Usage
///
/// The recommended way to create a client is using [connect], which supports
/// both explicit server URLs and auto-discovery:
///
/// ```dart
/// // Auto-discover a server on the network
/// final client = await RemoteLedgerClient.connect(
///   participantId: 'remote_worker',
/// );
///
/// // Or connect to a specific server
/// final client = await RemoteLedgerClient.connect(
///   serverUrl: 'http://localhost:19880',
///   participantId: 'remote_worker',
/// );
///
/// if (client != null) {
///   final op = await client.createOperation();
///   final call = await op.startCall<int>();
///   await call.end(42);
///   await op.complete();
///   client.dispose();
/// }
/// ```
///
/// For synchronous construction when you already have the server URL:
///
/// ```dart
/// final client = RemoteLedgerClient(
///   serverUrl: 'http://localhost:19880',
///   participantId: 'remote_worker',
/// );
/// ```
class RemoteLedgerClient extends Ledger {
  /// The URL of the ledger server.
  final String serverUrl;

  /// The participant ID for this client.
  @override
  final String participantId;

  /// The process ID for this client.
  @override
  final int participantPid;

  /// Maximum number of backup operations to retain.
  @override
  final int maxBackups;

  /// Heartbeat interval for client-side heartbeat.
  @override
  final Duration heartbeatInterval;

  /// Staleness threshold for detecting crashed operations.
  @override
  final Duration staleThreshold;

  /// HTTP client for making requests.
  final HttpClient _httpClient;

  /// Active remote operations.
  final Map<String, _RemoteOperation> _operations = {};

  /// Creates a new remote ledger client.
  ///
  /// Parameters:
  /// - [serverUrl] - URL of the ledger server (e.g., 'http://localhost:19880')
  /// - [participantId] - Unique identifier for this client
  /// - [participantPid] - Process ID (defaults to current PID)
  /// - [heartbeatInterval] - How often to send heartbeats
  /// - [staleThreshold] - How long before an operation is considered stale
  RemoteLedgerClient({
    required this.serverUrl,
    required this.participantId,
    int? participantPid,
    this.maxBackups = 20,
    this.heartbeatInterval = const Duration(seconds: 5),
    this.staleThreshold = const Duration(seconds: 15),
  }) : participantPid = participantPid ?? pid,
       _httpClient = HttpClient();

  /// Discover a LedgerServer and create a client connected to it.
  ///
  /// If [serverUrl] is provided, connects directly to that server.
  /// If [serverUrl] is `null`, uses auto-discovery to find a running server.
  ///
  /// Discovery scans in order:
  /// 1. `localhost` / `127.0.0.1`
  /// 2. Local machine's IP addresses
  /// 3. All IPs in the local subnet (if [scanSubnet] is true)
  ///
  /// Returns `null` if no server is found (discovery mode) or if connection
  /// fails (direct mode).
  ///
  /// ## Examples
  ///
  /// ```dart
  /// // Auto-discover a server
  /// final client = await RemoteLedgerClient.connect(
  ///   participantId: 'my_client',
  /// );
  ///
  /// // Connect to a specific server
  /// final client = await RemoteLedgerClient.connect(
  ///   serverUrl: 'http://192.168.1.100:19880',
  ///   participantId: 'my_client',
  /// );
  /// ```
  static Future<RemoteLedgerClient?> connect({
    required String participantId,
    String? serverUrl,
    int? participantPid,
    int maxBackups = 20,
    Duration heartbeatInterval = const Duration(seconds: 5),
    Duration staleThreshold = const Duration(seconds: 15),
    int port = 19880,
    Duration timeout = const Duration(milliseconds: 500),
    bool scanSubnet = true,
    void Function(String message)? logger,
  }) async {
    String resolvedServerUrl;

    if (serverUrl != null) {
      // Direct connection - verify server is reachable
      final result = await _tryConnect(serverUrl, timeout, logger);
      if (result == null) {
        logger?.call('Failed to connect to $serverUrl');
        return null;
      }
      resolvedServerUrl = serverUrl;
    } else {
      // Auto-discovery mode
      final discovery = await _discoverServer(
        port: port,
        timeout: timeout,
        scanSubnet: scanSubnet,
        logger: logger,
      );

      if (discovery == null) {
        logger?.call('No server found via auto-discovery');
        return null;
      }
      resolvedServerUrl = discovery['serverUrl'] as String;
    }

    return RemoteLedgerClient(
      serverUrl: resolvedServerUrl,
      participantId: participantId,
      participantPid: participantPid,
      maxBackups: maxBackups,
      heartbeatInterval: heartbeatInterval,
      staleThreshold: staleThreshold,
    );
  }

  /// Discover a LedgerServer and create a client connected to it.
  ///
  /// This is an alias for [connect] with [serverUrl] set to `null`.
  /// Use [connect] for both discovery and direct connection.
  @Deprecated('Use connect() instead')
  static Future<RemoteLedgerClient?> discover({
    required String participantId,
    int? participantPid,
    int maxBackups = 20,
    Duration heartbeatInterval = const Duration(seconds: 5),
    Duration staleThreshold = const Duration(seconds: 15),
    int port = 19880,
    Duration timeout = const Duration(milliseconds: 500),
    bool scanSubnet = true,
    void Function(String message)? logger,
  }) async {
    // Import here to avoid circular dependency
    final discovery = await _discoverServer(
      port: port,
      timeout: timeout,
      scanSubnet: scanSubnet,
      logger: logger,
    );

    if (discovery == null) return null;

    return RemoteLedgerClient(
      serverUrl: discovery['serverUrl'] as String,
      participantId: participantId,
      participantPid: participantPid,
      maxBackups: maxBackups,
      heartbeatInterval: heartbeatInterval,
      staleThreshold: staleThreshold,
    );
  }

  /// Internal discovery implementation.
  static Future<Map<String, dynamic>?> _discoverServer({
    required int port,
    required Duration timeout,
    required bool scanSubnet,
    void Function(String message)? logger,
  }) async {
    // Build candidate list
    final candidates = <String>[];

    // 1. Primary localhost addresses
    candidates.add('http://127.0.0.1:$port');
    candidates.add('http://localhost:$port');

    // 2. Get local machine's IP addresses
    final localIps = await _getLocalIpAddresses();
    for (final ip in localIps) {
      candidates.add('http://$ip:$port');
    }

    // 3. Scan subnet if enabled
    if (scanSubnet && localIps.isNotEmpty) {
      final subnetAddresses = _getSubnetAddresses(localIps.first);
      for (final ip in subnetAddresses) {
        final url = 'http://$ip:$port';
        if (!candidates.contains(url)) {
          candidates.add(url);
        }
      }
    }

    // Try each candidate
    for (final url in candidates) {
      final result = await _tryConnect(url, timeout, logger);
      if (result != null) {
        return {'serverUrl': url, 'status': result};
      }
    }

    return null;
  }

  /// Get local IP addresses of the machine.
  static Future<List<String>> _getLocalIpAddresses() async {
    final addresses = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) {
            addresses.add(addr.address);
          }
        }
      }
    } catch (_) {
      // Ignore errors
    }
    return addresses;
  }

  /// Get all addresses in the /24 subnet.
  static List<String> _getSubnetAddresses(String ip) {
    final addresses = <String>[];
    final parts = ip.split('.');
    if (parts.length != 4) return addresses;

    final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
    for (var i = 1; i < 255; i++) {
      final addr = '$prefix.$i';
      if (addr != ip) {
        addresses.add(addr);
      }
    }
    return addresses;
  }

  /// Try to connect to a server.
  static Future<Map<String, dynamic>?> _tryConnect(
    String url,
    Duration timeout,
    void Function(String message)? logger,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = timeout;

    try {
      logger?.call('Trying $url/status...');
      final request = await client.getUrl(Uri.parse('$url/status'));
      final response = await request.close().timeout(timeout);

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        if (body.isNotEmpty) {
          final json = jsonDecode(body) as Map<String, dynamic>;
          if (json['service'] == 'tom_dist_ledger') {
            logger?.call('Found server at $url');
            return json;
          }
        }
      }
    } on TimeoutException {
      // Expected
    } on SocketException {
      // Expected
    } catch (_) {
      // Other errors
    } finally {
      client.close(force: true);
    }
    return null;
  }

  /// Pattern for valid operation IDs.
  ///
  /// Only allows alphanumeric characters, hyphens, underscores, colons, and dots.
  /// Prevents path traversal attacks via `..` or `/` sequences.
  static final _validOperationIdPattern = RegExp(r'^[a-zA-Z0-9_\-:.]+$');

  /// Validates that an operation ID is safe for use.
  ///
  /// Throws [ArgumentError] if the operation ID contains invalid characters
  /// or could be used for path traversal.
  void _validateOperationId(String operationId) {
    if (operationId.isEmpty) {
      throw ArgumentError.value(
        operationId,
        'operationId',
        'Operation ID cannot be empty',
      );
    }
    if (operationId.contains('..') || operationId.contains('/')) {
      throw ArgumentError.value(
        operationId,
        'operationId',
        'Operation ID contains invalid path characters',
      );
    }
    if (!_validOperationIdPattern.hasMatch(operationId)) {
      throw ArgumentError.value(
        operationId,
        'operationId',
        'Operation ID contains invalid characters',
      );
    }
  }

  /// Create a new operation on the remote server.
  ///
  /// Returns a [RemoteOperation] with the same API as local [Operation].
  @override
  Future<RemoteOperation> createOperation({
    String? description,
    OperationCallback? callback,
  }) async {
    final response = await _post('/operation/create', {
      'participantId': participantId,
      'participantPid': participantPid,
      'description': ?description,
    });

    final operationId = response['operationId'] as String;
    final sessionId = response['sessionId'] as int;
    final startTime = DateTime.parse(response['startTime'] as String);

    final remoteOp = _RemoteOperation(
      client: this,
      operationId: operationId,
      participantId: participantId,
      pid: participantPid,
      isInitiator: true,
      startTime: startTime,
    );
    _operations[operationId] = remoteOp;

    // Register the session locally for call tracking
    remoteOp._registerSession(sessionId);

    final operation = RemoteOperation._(remoteOp, sessionId);

    // Start client-side heartbeat
    operation.startHeartbeat(
      interval: heartbeatInterval,
      onSuccess: callback?.onHeartbeatSuccess,
      onError: callback?.onHeartbeatError,
    );

    return operation;
  }

  /// Join an existing operation on the remote server.
  ///
  /// Returns a [RemoteOperation] with the same API as local [Operation].
  ///
  /// Throws [ArgumentError] if [operationId] contains invalid characters
  /// or could be used for path traversal.
  @override
  Future<RemoteOperation> joinOperation({
    required String operationId,
    OperationCallback? callback,
  }) async {
    // Validate operationId to prevent path traversal attacks
    _validateOperationId(operationId);

    final response = await _post('/operation/join', {
      'operationId': operationId,
      'participantId': participantId,
      'participantPid': participantPid,
    });

    final sessionId = response['sessionId'] as int;
    final startTime = DateTime.parse(response['startTime'] as String);

    var remoteOp = _operations[operationId];
    final isFirstJoin = remoteOp == null;

    if (isFirstJoin) {
      remoteOp = _RemoteOperation(
        client: this,
        operationId: operationId,
        participantId: participantId,
        pid: participantPid,
        isInitiator: false,
        startTime: startTime,
      );
      _operations[operationId] = remoteOp;
    }

    // Register the session locally for call tracking
    remoteOp._registerSession(sessionId);

    final operation = RemoteOperation._(remoteOp, sessionId);

    // Start client-side heartbeat on first join
    if (isFirstJoin) {
      operation.startHeartbeat(
        interval: heartbeatInterval,
        onSuccess: callback?.onHeartbeatSuccess,
        onError: callback?.onHeartbeatError,
      );
    }

    return operation;
  }

  /// Remove an operation from local tracking.
  void _unregisterOperation(String operationId) {
    _operations.remove(operationId);
  }

  /// Make a POST request to the server with retry logic.
  ///
  /// Retries on connection errors with exponential backoff:
  /// 2, 4, 8, 16, 32 seconds (up to 62 seconds total).
  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    return withRetry(
      () async {
        final uri = Uri.parse('$serverUrl$path');
        final request = await _httpClient.postUrl(uri);
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));

        final response = await request.close();
        final responseBody = await utf8.decoder.bind(response).join();
        final data = jsonDecode(responseBody) as Map<String, dynamic>;

        // Retry on server errors (5xx)
        if (response.statusCode >= 500 && response.statusCode < 600) {
          throw RemoteLedgerException(
            data['error'] as String? ?? 'Server error',
            statusCode: response.statusCode,
          );
        }

        if (response.statusCode != 200) {
          throw RemoteLedgerException(
            data['error'] as String? ?? 'Unknown error',
            statusCode: response.statusCode,
          );
        }

        return data;
      },
      shouldRetry: (error) {
        // Retry on RemoteLedgerException with 5xx status
        if (error is RemoteLedgerException) {
          final code = error.statusCode;
          return code != null && code >= 500 && code < 600;
        }
        // Default retry behavior for connection errors
        return true;
      },
    );
  }

  /// Dispose of the client.
  @override
  void dispose() {
    for (final op in _operations.values) {
      op.stopHeartbeat();
    }
    _operations.clear();
    _httpClient.close();
  }
}

/// Exception thrown by remote ledger operations.
class RemoteLedgerException implements Exception {
  final String message;
  final int? statusCode;

  RemoteLedgerException(this.message, {this.statusCode});

  @override
  String toString() => 'RemoteLedgerException: $message (status: $statusCode)';
}

// ═══════════════════════════════════════════════════════════════════
// INTERNAL TYPES
// ═══════════════════════════════════════════════════════════════════

/// Information about an active call (client-side tracking).
class _ActiveCallInfo<T> {
  final String callId;
  final int sessionId;
  final DateTime startedAt;
  final CallCallback<T> callback;
  final bool failOnCrash;
  final Completer<void> completer;

  _ActiveCallInfo({
    required this.callId,
    required this.sessionId,
    required this.startedAt,
    required this.callback,
    required this.failOnCrash,
    required this.completer,
  });
}

/// Internal class representing a remote operation.
class _RemoteOperation {
  final RemoteLedgerClient client;
  final String operationId;
  final String participantId;
  final int pid;
  final bool isInitiator;
  final DateTime startTime;

  Timer? _heartbeatTimer;
  bool _isAborted = false;
  int _joinCount = 0;
  int _sessionCounter = 0;
  final Set<int> _activeSessions = {};

  /// Active calls tracked by this operation (client-side).
  final Map<String, _ActiveCallInfo> _activeCalls = {};

  /// Map of callId to Call object for lookup.
  final Map<String, dynamic> _calls = {};

  /// Calls tracked per session.
  final Map<int, Set<String>> _sessionCalls = {};

  /// Cached operation data from server responses.
  LedgerData? _cachedData;

  /// Locally tracked temporary resources for cleanup on exit.
  final Set<String> _localTempResources = {};

  /// Cleanup handler registration ID for signal handling.
  int? _cleanupHandlerId;

  final Completer<void> _abortCompleter = Completer<void>();
  final Completer<OperationFailedInfo> _failureCompleter =
      Completer<OperationFailedInfo>();

  _RemoteOperation({
    required this.client,
    required this.operationId,
    required this.participantId,
    required this.pid,
    required this.isInitiator,
    required this.startTime,
  }) {
    // Register cleanup handler for graceful shutdown
    _cleanupHandlerId = CleanupHandler.instance.register(_cleanupTempResources);
  }

  /// Cleanup temp resources (called by CleanupHandler on signal).
  Future<void> _cleanupTempResources() async {
    for (final path in _localTempResources.toList()) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        } else {
          final dir = Directory(path);
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        }
      } catch (e) {
        // Silently ignore errors - file may have been cleaned up by another participant
      }
    }
    _localTempResources.clear();
  }

  /// Unregister from cleanup handler.
  void _unregisterCleanup() {
    if (_cleanupHandlerId != null) {
      CleanupHandler.instance.unregister(_cleanupHandlerId!);
      _cleanupHandlerId = null;
    }
  }

  bool get isAborted => _isAborted;
  Future<void> get onAbort => _abortCompleter.future;
  Future<OperationFailedInfo> get onFailure => _failureCompleter.future;
  int get joinCount => _joinCount;

  /// Register a session ID received from the server.
  ///
  /// This is used when the session is created on the server and we need
  /// to track it locally for call management.
  void _registerSession(int sessionId) {
    _activeSessions.add(sessionId);
    _sessionCalls[sessionId] = {};
    _joinCount++;
    // Update counter to avoid ID conflicts
    if (sessionId > _sessionCounter) {
      _sessionCounter = sessionId;
    }
  }

  int createSession() {
    _sessionCounter++;
    _activeSessions.add(_sessionCounter);
    _sessionCalls[_sessionCounter] = {};
    _joinCount++;
    return _sessionCounter;
  }

  void leaveSession(int sessionId, {bool cancelPendingCalls = false}) {
    if (!_activeSessions.contains(sessionId)) {
      throw StateError('Session $sessionId is not active');
    }

    final sessionCallIds = _sessionCalls[sessionId] ?? {};
    if (sessionCallIds.isNotEmpty && !cancelPendingCalls) {
      throw StateError(
        'Session $sessionId has ${sessionCallIds.length} pending calls. '
        'Use cancelPendingCalls: true to cancel them.',
      );
    }

    // Cancel pending calls for this session
    if (cancelPendingCalls) {
      for (final callId in sessionCallIds.toList()) {
        final call = _calls[callId];
        if (call is SpawnedCall) {
          call.cancel();
        }
        _activeCalls.remove(callId);
        _calls.remove(callId);
      }
    }

    _activeSessions.remove(sessionId);
    _sessionCalls.remove(sessionId);
    _joinCount--;

    if (_joinCount == 0) {
      stopHeartbeat();
      _unregisterCleanup();
      client._unregisterOperation(operationId);
    }
  }

  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void triggerAbort() {
    _isAborted = true;
    stopHeartbeat();
    if (!_abortCompleter.isCompleted) {
      _abortCompleter.complete();
    }
  }

  void signalFailure(OperationFailedInfo info) {
    if (!_failureCompleter.isCompleted) {
      _failureCompleter.complete(info);
    }
  }

  String get elapsedFormatted {
    final duration = DateTime.now().difference(startTime);
    final seconds = duration.inSeconds;
    final millis = duration.inMilliseconds % 1000;
    return '${seconds.toString().padLeft(3, '0')}.${millis.toString().padLeft(3, '0')}';
  }

  Duration get elapsedDuration => DateTime.now().difference(startTime);
  String get startTimeIso => startTime.toIso8601String();
  int get startTimeMs => startTime.millisecondsSinceEpoch;

  /// Check if a session has pending calls.
  bool hasPendingCallsForSession(int sessionId) {
    return _sessionCalls[sessionId]?.isNotEmpty ?? false;
  }

  /// Get pending call count for a session.
  int pendingCallCountForSession(int sessionId) {
    return _sessionCalls[sessionId]?.length ?? 0;
  }

  /// Get pending spawned calls for a session.
  List<SpawnedCall> getPendingSpawnedCallsForSession(int sessionId) {
    final callIds = _sessionCalls[sessionId] ?? {};
    return callIds
        .map((id) => _calls[id])
        .whereType<SpawnedCall>()
        .where((call) => !call.isCompleted)
        .toList();
  }

  /// Get pending regular calls for a session.
  List<Call> getPendingCallsForSession(int sessionId) {
    final callIds = _sessionCalls[sessionId] ?? {};
    return callIds
        .map((id) => _calls[id])
        .whereType<Call>()
        .where((call) => !call.isCompleted)
        .toList();
  }
}

// ═══════════════════════════════════════════════════════════════════
// REMOTE OPERATION CLASS
// ═══════════════════════════════════════════════════════════════════

/// A remote operation handle with session tracking.
///
/// This provides the same interface as [LocalOperation] but communicates
/// with a remote server for ledger access. Callbacks and work execution
/// happen client-side.
class RemoteOperation implements Operation, CallLifecycle {
  final _RemoteOperation _operation;

  @override
  final int sessionId;

  RemoteOperation._(this._operation, this.sessionId);

  // ─────────────────────────────────────────────────────────────
  // Properties (same as Operation)
  // ─────────────────────────────────────────────────────────────

  @override
  String get operationId => _operation.operationId;

  @override
  String get participantId => _operation.participantId;

  /// The process ID.
  int get pid => _operation.pid;

  @override
  bool get isInitiator => _operation.isInitiator;

  @override
  DateTime get startTime => _operation.startTime;

  @override
  bool get isAborted => _operation._isAborted;

  @override
  Future<void> get onAbort => _operation.onAbort;

  /// Future that completes when operation fails.
  @override
  Future<OperationFailedInfo> get onFailure => _operation.onFailure;

  /// Elapsed time formatted as "SSS.mmm".
  @override
  String get elapsedFormatted => _operation.elapsedFormatted;

  /// Elapsed duration since operation start.
  @override
  Duration get elapsedDuration => _operation.elapsedDuration;

  /// Start time as ISO 8601 string.
  @override
  String get startTimeIso => _operation.startTimeIso;

  /// Start time as milliseconds since epoch.
  @override
  int get startTimeMs => _operation.startTimeMs;

  /// Number of pending calls for this session.
  @override
  int get pendingCallCount => _operation.pendingCallCountForSession(sessionId);

  // ─────────────────────────────────────────────────────────────
  // Call Management (unified API with Operation)
  // ─────────────────────────────────────────────────────────────

  /// Start a call tracked to this session.
  ///
  /// Returns a [Call<T>] object for lifecycle management.
  /// Callbacks execute client-side; call frame is registered on server.
  @override
  Future<Call<T>> startCall<T>({
    CallCallback<T>? callback,
    String? description,
    bool failOnCrash = true,
  }) async {
    final response = await _operation.client._post('/call/start', {
      'operationId': operationId,
      'sessionId': sessionId,
      'description': description,
      'failOnCrash': failOnCrash,
    });

    final callId = response['callId'] as String;
    final startedAt = DateTime.parse(response['startedAt'] as String);

    // Track call client-side
    final activeCall = _ActiveCallInfo<T>(
      callId: callId,
      sessionId: sessionId,
      startedAt: startedAt,
      callback: callback ?? CallCallback<T>(),
      failOnCrash: failOnCrash,
      completer: Completer<void>(),
    );
    _operation._activeCalls[callId] = activeCall;
    _operation._sessionCalls[sessionId]?.add(callId);

    // Create Call<T> object that works with this remote operation
    final call = Call<T>.internal(
      callId: callId,
      operation: this, // RemoteOperation implements CallLifecycle
      startedAt: startedAt,
      description: description,
    );
    _operation._calls[callId] = call;

    return call;
  }

  /// Spawn a call that runs asynchronously.
  ///
  /// Work executes client-side; call frame is registered on server.
  /// Returns immediately with a [SpawnedCall<T>].
  ///
  /// The [work] function receives both the [SpawnedCall] (for cancellation checks)
  /// and this [Operation] (for logging, abort checks, etc.).
  @override
  SpawnedCall<T> spawnCall<T>({
    required Future<T> Function(SpawnedCall<T> call, Operation operation)
    work,
    CallCallback<T>? callback,
    String? description,
    bool failOnCrash = true,
  }) {
    // Generate a temporary call ID (will be replaced by server response)
    final tempCallId =
        'spawn_${DateTime.now().millisecondsSinceEpoch}_${_operation._calls.length}';

    // Create spawned call object immediately
    final spawnedCall = SpawnedCall<T>(
      callId: tempCallId,
      description: description,
    );

    // Track in session
    _operation._sessionCalls[sessionId]?.add(tempCallId);
    _operation._calls[tempCallId] = spawnedCall;

    // Start the work asynchronously
    _runSpawnedCall(
      spawnedCall: spawnedCall,
      work: () => work(spawnedCall, this),
      callback: callback ?? CallCallback<T>(),
      description: description,
      failOnCrash: failOnCrash,
    );

    return spawnedCall;
  }

  /// Internal method to run a spawned call.
  Future<void> _runSpawnedCall<T>({
    required SpawnedCall<T> spawnedCall,
    required Future<T> Function() work,
    required CallCallback<T> callback,
    String? description,
    required bool failOnCrash,
  }) async {
    String? serverCallId;

    try {
      // Register call frame on server
      final response = await _operation.client._post('/call/start', {
        'operationId': operationId,
        'sessionId': sessionId,
        'description': description,
        'failOnCrash': failOnCrash,
      });

      serverCallId = response['callId'] as String;
      final startedAt = DateTime.parse(response['startedAt'] as String);

      // Track call client-side
      final activeCall = _ActiveCallInfo<T>(
        callId: serverCallId,
        sessionId: sessionId,
        startedAt: startedAt,
        callback: callback,
        failOnCrash: failOnCrash,
        completer: Completer<void>(),
      );
      _operation._activeCalls[serverCallId] = activeCall;

      // Execute the work
      final result = await work();

      // End call on server
      await _operation.client._post('/call/end', {
        'operationId': operationId,
        'callId': serverCallId,
      });

      // Remove from tracking
      _operation._activeCalls.remove(serverCallId);
      _operation._sessionCalls[sessionId]?.remove(spawnedCall.callId);
      _operation._calls.remove(spawnedCall.callId);

      // Trigger onCompletion callback
      await callback.onCompletion?.call(result);

      // Complete the spawned call
      spawnedCall.complete(result);
    } catch (e, st) {
      // Handle failure
      if (serverCallId != null) {
        // Fail call on server
        try {
          await _operation.client._post('/call/fail', {
            'operationId': operationId,
            'callId': serverCallId,
            'error': e.toString(),
          });
        } catch (_) {
          // Ignore server errors during failure handling
        }

        _operation._activeCalls.remove(serverCallId);
      }

      // Remove from tracking
      _operation._sessionCalls[sessionId]?.remove(spawnedCall.callId);
      _operation._calls.remove(spawnedCall.callId);

      // Try onCallCrashed callback for fallback
      T? fallback;
      bool hasFallback = false;
      if (callback.onCallCrashed != null) {
        try {
          fallback = await callback.onCallCrashed!();
          hasFallback = true;
        } catch (_) {
          // Fallback failed
        }
      }

      // Trigger onCleanup callback
      await callback.onCleanup?.call();

      if (hasFallback) {
        spawnedCall.complete(fallback as T);
      } else {
        spawnedCall.fail(e, st);

        // Signal operation failure if failOnCrash
        if (failOnCrash) {
          _operation.signalFailure(
            OperationFailedInfo(
              operationId: operationId,
              failedAt: DateTime.now(),
              reason: 'Spawned call failed: $e',
              crashedCallIds: [serverCallId ?? spawnedCall.callId],
            ),
          );
        }
      }
    }
  }

  /// Internal method to end a call, called by Call.end().
  @override
  Future<void> endCallInternal<T>({required String callId, T? result}) async {
    final activeCall = _operation._activeCalls.remove(callId);
    if (activeCall == null) {
      throw StateError('No active call with ID: $callId');
    }
    _operation._calls.remove(callId);
    _operation._sessionCalls[sessionId]?.remove(callId);

    // End call on server
    await _operation.client._post('/call/end', {
      'operationId': operationId,
      'callId': callId,
    });

    // Trigger onCompletion callback client-side
    if (result != null && activeCall is _ActiveCallInfo<T>) {
      await activeCall.callback.onCompletion?.call(result);
    }

    // Complete the completer
    if (!activeCall.completer.isCompleted) {
      activeCall.completer.complete();
    }
  }

  /// Internal method to fail a call, called by Call.fail().
  @override
  Future<void> failCallInternal({
    required String callId,
    required Object error,
    StackTrace? stackTrace,
  }) async {
    final activeCall = _operation._activeCalls.remove(callId);
    if (activeCall == null) {
      throw StateError('No active call with ID: $callId');
    }
    _operation._calls.remove(callId);
    _operation._sessionCalls[sessionId]?.remove(callId);

    // Fail call on server
    await _operation.client._post('/call/fail', {
      'operationId': operationId,
      'callId': callId,
      'error': error.toString(),
    });

    // Trigger onCleanup callback client-side
    await activeCall.callback.onCleanup?.call();

    // Signal operation failure if failOnCrash
    if (activeCall.failOnCrash) {
      _operation.signalFailure(
        OperationFailedInfo(
          operationId: operationId,
          failedAt: DateTime.now(),
          reason: 'Call $callId failed: $error',
          crashedCallIds: [callId],
        ),
      );
    }

    // Complete the completer
    if (!activeCall.completer.isCompleted) {
      activeCall.completer.complete();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Session Call Tracking (same as Operation)
  // ─────────────────────────────────────────────────────────────

  /// Check if this session has any pending calls.
  @override
  bool hasPendingCalls() => _operation.hasPendingCallsForSession(sessionId);

  /// Get pending spawned calls for this session.
  List<SpawnedCall> getPendingSpawnedCalls() =>
      _operation.getPendingSpawnedCallsForSession(sessionId);

  /// Get pending regular calls for this session.
  List<Call> getPendingCalls() =>
      _operation.getPendingCallsForSession(sessionId);

  // ─────────────────────────────────────────────────────────────
  // Sync Methods (same as Operation)
  // ─────────────────────────────────────────────────────────────

  /// Wait for spawned calls to complete.
  @override
  Future<SyncResult> sync(
    List<SpawnedCall> calls, {
    Future<void> Function(OperationFailedInfo info)? onOperationFailed,
    Future<void> Function()? onCompletion,
  }) async {
    final successfulCalls = <SpawnedCall>[];
    final failedCalls = <SpawnedCall>[];
    final unknownCalls = <SpawnedCall>[];
    var operationFailed = false;

    // Wait for all calls or operation failure
    final callFutures = calls.map((c) => c.future).toList();
    final opFailureFuture = onFailure;

    await Future.any([
      Future.wait(callFutures),
      opFailureFuture.then((info) async {
        operationFailed = true;
        await onOperationFailed?.call(info);
      }),
    ]);

    // Categorize calls
    for (final call in calls) {
      if (call.isCompleted) {
        if (call.isSuccess) {
          successfulCalls.add(call);
        } else {
          failedCalls.add(call);
        }
      } else {
        unknownCalls.add(call);
      }
    }

    // Trigger completion callback if all succeeded
    if (successfulCalls.length == calls.length && !operationFailed) {
      await onCompletion?.call();
    }

    return SyncResult(
      successfulCalls: successfulCalls,
      failedCalls: failedCalls,
      unknownCalls: unknownCalls,
      operationFailed: operationFailed,
    );
  }

  /// Wait for a single spawned call to complete.
  @override
  Future<SyncResult> awaitCall<T>(
    SpawnedCall<T> call, {
    Future<void> Function(OperationFailedInfo info)? onOperationFailed,
    Future<void> Function()? onCompletion,
  }) {
    return sync(
      [call],
      onOperationFailed: onOperationFailed,
      onCompletion: onCompletion,
    );
  }

  /// Execute work while monitoring operation state.
  @override
  Future<T> waitForCompletion<T>(
    Future<T> Function() work, {
    Future<void> Function(OperationFailedInfo info)? onOperationFailed,
    Future<T> Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    final workFuture = work();
    final failureFuture = onFailure;

    // Race between work completion and operation failure
    final result = await Future.any<dynamic>([
      workFuture.then((r) => ('success', r)),
      failureFuture.then((info) => ('failed', info)),
    ]);

    if (result.$1 == 'failed') {
      final info = result.$2 as OperationFailedInfo;
      await onOperationFailed?.call(info);
      throw OperationFailedException(info);
    }

    return result.$2 as T;
  }

  // ─────────────────────────────────────────────────────────────
  // Operation Lifecycle (same as Operation)
  // ─────────────────────────────────────────────────────────────

  @override
  Future<void> leave({bool cancelPendingCalls = false}) async {
    // Check for pending calls before notifying server
    _operation.leaveSession(sessionId, cancelPendingCalls: cancelPendingCalls);

    // Notify server (optional - server just acknowledges)
    await _operation.client._post('/operation/leave', {
      'operationId': operationId,
      'sessionId': sessionId,
      'cancelPendingCalls': cancelPendingCalls,
    });
  }

  @override
  Future<void> log(String message, {DLLogLevel level = DLLogLevel.info}) async {
    await _operation.client._post('/operation/log', {
      'operationId': operationId,
      'message': message,
      'level': level.name,
    });
  }

  @override
  Future<void> complete() async {
    if (!isInitiator) {
      throw StateError('Only the initiator can complete an operation');
    }
    _operation.stopHeartbeat();
    await _operation.client._post('/operation/complete', {
      'operationId': operationId,
    });
    _operation.client._unregisterOperation(operationId);
  }

  @override
  Future<void> setAbortFlag(bool value) async {
    await _operation.client._post('/operation/abort', {
      'operationId': operationId,
      'value': value,
    });
  }

  @override
  Future<bool> checkAbort() async {
    final response = await _operation.client._post('/operation/state', {
      'operationId': operationId,
    });
    final aborted = response['aborted'] as bool? ?? false;
    if (aborted && !_operation._isAborted) {
      _operation._isAborted = true;
      if (!_operation._abortCompleter.isCompleted) {
        _operation._abortCompleter.complete();
      }
    }
    return aborted;
  }

  @override
  void triggerAbort() => _operation.triggerAbort();

  // ─────────────────────────────────────────────────────────────
  // Low-level call frame operations
  // ─────────────────────────────────────────────────────────────

  /// Cached operation data from server responses.
  ///
  /// Updated after server calls that return operation state.
  @override
  LedgerData? get cachedData => _operation._cachedData;

  /// Create a call frame directly (low-level operation).
  ///
  /// This calls the server to create a call frame in the ledger.
  @override
  Future<void> createCallFrame({required String callId}) async {
    final response = await _operation.client._post('/callframe/create', {
      'operationId': operationId,
      'callId': callId,
      'participantId': participantId,
    });

    // Update cached data if returned
    if (response['data'] != null) {
      _operation._cachedData = LedgerData.fromJson(
        response['data'] as Map<String, dynamic>,
      );
    }
  }

  /// Delete a call frame directly (low-level operation).
  ///
  /// This calls the server to delete a call frame from the ledger.
  @override
  Future<void> deleteCallFrame({required String callId}) async {
    final response = await _operation.client._post('/callframe/delete', {
      'operationId': operationId,
      'callId': callId,
    });

    // Update cached data if returned
    if (response['data'] != null) {
      _operation._cachedData = LedgerData.fromJson(
        response['data'] as Map<String, dynamic>,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Temporary resource management (local tracking)
  // ─────────────────────────────────────────────────────────────

  /// Register a temporary resource for local cleanup tracking.
  ///
  /// For remote operations, temp resources are tracked locally and cleaned
  /// up on process exit, signal interruption, or operation completion.
  /// This does NOT register the resource on the server ledger.
  @override
  Future<void> registerTempResource({required String path}) async {
    _operation._localTempResources.add(path);
  }

  /// Unregister a temporary resource.
  ///
  /// Call this after successfully cleaning up a temporary resource.
  @override
  Future<void> unregisterTempResource({required String path}) async {
    _operation._localTempResources.remove(path);
  }

  /// Get locally registered temp resources (for cleanup).
  Set<String> get localTempResources =>
      Set.unmodifiable(_operation._localTempResources);

  /// Clean up all locally registered temp resources.
  ///
  /// Attempts to delete all registered temp files/directories.
  /// Errors are logged but don't stop cleanup of remaining resources.
  Future<void> cleanupLocalTempResources() async {
    for (final path in _operation._localTempResources.toList()) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        } else {
          final dir = Directory(path);
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        }
        _operation._localTempResources.remove(path);
      } catch (e) {
        // Log but continue cleanup
        stderr.writeln('Failed to cleanup temp resource $path: $e');
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Heartbeat Management
  // ─────────────────────────────────────────────────────────────

  /// Start the heartbeat.
  @override
  void startHeartbeat({
    Duration interval = const Duration(milliseconds: 4500),
    int jitterMs = 500,
    HeartbeatErrorCallback? onError,
    HeartbeatSuccessCallback? onSuccess,
  }) {
    _operation.stopHeartbeat();
    _scheduleNextHeartbeat(
      interval: interval,
      jitterMs: jitterMs,
      onError: onError,
      onSuccess: onSuccess,
    );
  }

  void _scheduleNextHeartbeat({
    required Duration interval,
    required int jitterMs,
    HeartbeatErrorCallback? onError,
    HeartbeatSuccessCallback? onSuccess,
  }) {
    if (_operation._isAborted) return;

    final jitter = DateTime.now().millisecond % jitterMs;
    final delay = interval + Duration(milliseconds: jitter);

    _operation._heartbeatTimer = Timer(delay, () async {
      if (_operation._isAborted) return;
      await _doHeartbeat(onError: onError, onSuccess: onSuccess);
      _scheduleNextHeartbeat(
        interval: interval,
        jitterMs: jitterMs,
        onError: onError,
        onSuccess: onSuccess,
      );
    });
  }

  Future<void> _doHeartbeat({
    HeartbeatErrorCallback? onError,
    HeartbeatSuccessCallback? onSuccess,
  }) async {
    try {
      final response = await _operation.client._post('/operation/heartbeat', {
        'operationId': operationId,
      });

      if (response['success'] != true) {
        onError?.call(
          this,
          HeartbeatError(
            type: HeartbeatErrorType.ledgerNotFound,
            message: response['reason'] as String? ?? 'Unknown error',
          ),
        );
        return;
      }

      // Check for abort
      if (response['abortFlag'] == true) {
        _operation._isAborted = true;
        if (!_operation._abortCompleter.isCompleted) {
          _operation._abortCompleter.complete();
        }
        onError?.call(
          this,
          const HeartbeatError(
            type: HeartbeatErrorType.abortFlagSet,
            message: 'Abort flag is set',
          ),
        );
        return;
      }

      // Check for stale participants
      final staleParticipants =
          (response['staleParticipants'] as List<dynamic>?)?.cast<String>() ??
          [];
      if (staleParticipants.isNotEmpty) {
        onError?.call(
          this,
          HeartbeatError(
            type: HeartbeatErrorType.heartbeatStale,
            message:
                'Stale heartbeat detected from: ${staleParticipants.join(", ")}',
          ),
        );
        return;
      }

      // Success
      onSuccess?.call(
        this,
        HeartbeatResult(
          abortFlag: response['abortFlag'] as bool? ?? false,
          ledgerExists: true,
          heartbeatUpdated: true,
          callFrameCount: response['callFrameCount'] as int? ?? 0,
          tempResourceCount: response['tempResourceCount'] as int? ?? 0,
          heartbeatAgeMs: response['heartbeatAgeMs'] as int? ?? 0,
          isStale: response['isStale'] as bool? ?? false,
          participants:
              (response['participants'] as List<dynamic>?)?.cast<String>() ??
              [],
          staleParticipants: staleParticipants,
        ),
      );
    } catch (e) {
      onError?.call(
        this,
        HeartbeatError(
          type: HeartbeatErrorType.ioError,
          message: 'Heartbeat failed: $e',
          cause: e,
        ),
      );
    }
  }

  /// Stop the heartbeat.
  void stopHeartbeat() => _operation.stopHeartbeat();

  /// Perform a single heartbeat.
  Future<HeartbeatResult?> heartbeat() async {
    try {
      final response = await _operation.client._post('/operation/heartbeat', {
        'operationId': operationId,
      });

      if (response['success'] != true) {
        return null;
      }

      return HeartbeatResult(
        abortFlag: response['abortFlag'] as bool? ?? false,
        ledgerExists: true,
        heartbeatUpdated: true,
        callFrameCount: response['callFrameCount'] as int? ?? 0,
        tempResourceCount: response['tempResourceCount'] as int? ?? 0,
        heartbeatAgeMs: response['heartbeatAgeMs'] as int? ?? 0,
        isStale: response['isStale'] as bool? ?? false,
        participants:
            (response['participants'] as List<dynamic>?)?.cast<String>() ?? [],
        staleParticipants:
            (response['staleParticipants'] as List<dynamic>?)?.cast<String>() ??
            [],
      );
    } catch (_) {
      return null;
    }
  }
}
