// ignore_for_file: library_private_types_in_public_api
part of 'ledger_api.dart';

/// HTTP server that provides remote access to the distributed ledger.
///
/// The server is stateless - each request reads/writes files directly.
/// Remote clients send their participantId with each request.
///
/// ## Starting the server
///
/// ```dart
/// final server = await LedgerServer.start(
///   basePath: '/tmp/ledger',
///   port: 19880,
/// );
/// print('Server listening on http://localhost:${server.port}');
/// ```
///
/// ## Stopping the server
///
/// ```dart
/// await server.stop();
/// ```
class LedgerServer {
  /// The underlying HTTP server.
  final HttpServer _server;

  /// The ledger instance used to process requests.
  final LocalLedger _ledger;

  /// The port the server is listening on.
  int get port => _server.port;

  /// The base path for ledger files.
  String get basePath => _ledger.basePath;

  LedgerServer._(this._server, this._ledger);

  /// Start the ledger server.
  ///
  /// The server uses a local [Ledger] instance with participantId 'ledger_server'
  /// but processes requests using each client's participantId.
  ///
  /// Parameters:
  /// - [basePath] - Path for ledger files (default: current directory)
  /// - [port] - Port to listen on (default: 19880)
  /// - [address] - Address to bind to (default: loopback)
  static Future<LedgerServer> start({
    required String basePath,
    int port = 19880,
    InternetAddress? address,
  }) async {
    // Create the ledger with server identity
    final ledger = LocalLedger(basePath: basePath, participantId: 'ledger_server');

    // Start HTTP server
    final server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
    );

    final ledgerServer = LedgerServer._(server, ledger);

    // Handle requests
    unawaited(ledgerServer._handleRequests());

    return ledgerServer;
  }

  /// Stop the server.
  Future<void> stop() async {
    await _server.close(force: true);
    _ledger.dispose();
  }

  /// Handle incoming requests.
  Future<void> _handleRequests() async {
    await for (final request in _server) {
      try {
        await _handleRequest(request);
      } catch (e, st) {
        _sendError(request.response, 500, 'Internal server error: $e');
        stderr.writeln('Error handling request: $e\n$st');
      }
    }
  }

  /// Route and handle a single request.
  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method;

    // Parse JSON body if present
    Map<String, dynamic>? body;
    if (method == 'POST' || method == 'PUT') {
      try {
        final content = await utf8.decoder.bind(request).join();
        if (content.isNotEmpty) {
          body = jsonDecode(content) as Map<String, dynamic>;
        }
      } catch (_) {
        _sendError(request.response, 400, 'Invalid JSON body');
        return;
      }
    }

    // Route requests
    switch (path) {
      case '/health':
        _sendJson(request.response, {'status': 'ok'});
        break;

      case '/status':
        _handleStatus(request);
        break;

      case '/operation/create':
        await _handleCreateOperation(request, body);
        break;

      case '/operation/join':
        await _handleJoinOperation(request, body);
        break;

      case '/operation/leave':
        await _handleLeaveOperation(request, body);
        break;

      case '/operation/complete':
        await _handleCompleteOperation(request, body);
        break;

      case '/operation/heartbeat':
        await _handleHeartbeat(request, body);
        break;

      case '/operation/abort':
        await _handleSetAbort(request, body);
        break;

      case '/operation/state':
        await _handleGetState(request, body);
        break;

      case '/operation/log':
        await _handleLog(request, body);
        break;

      case '/call/start':
        await _handleStartCall(request, body);
        break;

      case '/call/end':
        await _handleEndCall(request, body);
        break;

      case '/call/fail':
        await _handleFailCall(request, body);
        break;

      default:
        _sendError(request.response, 404, 'Not found: $path');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Request handlers
  // ─────────────────────────────────────────────────────────────

  /// Handle GET /status
  ///
  /// Returns server status for auto-discovery and monitoring.
  /// This is a lightweight endpoint used by clients to discover servers.
  void _handleStatus(HttpRequest request) {
    _sendJson(request.response, {
      'service': 'tom_dist_ledger',
      'version': '0.1.0',
      'status': 'ok',
      'port': port,
      'basePath': basePath,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Handle POST /operation/create
  Future<void> _handleCreateOperation(
    HttpRequest request,
    Map<String, dynamic>? body,
  ) async {
    final participantId = body?['participantId'] as String?;
    if (participantId == null) {
      _sendError(request.response, 400, 'Missing participantId');
      return;
    }

    final description = body?['description'] as String?;
    final participantPid = body?['participantPid'] as int? ?? -1;

    try {
      final operation = await _ledger._createOperationForClient(
        participantId: participantId,
        participantPid: participantPid,
        description: description,
      );

      _sendJson(request.response, {
        'operationId': operation.operationId,
        'participantId': operation.participantId,
        'isInitiator': operation.isInitiator,
        'sessionId': operation.sessionId,
        'startTime': operation.startTime.toIso8601String(),
      });
    } catch (e) {
      _sendError(request.response, 500, 'Failed to create operation: $e');
    }
  }

  /// Handle POST /operation/join
  Future<void> _handleJoinOperation(
    HttpRequest request,
    Map<String, dynamic>? body,
  ) async {
    final operationId = body?['operationId'] as String?;
    final participantId = body?['participantId'] as String?;

    if (operationId == null) {
      _sendError(request.response, 400, 'Missing operationId');
      return;
    }
    if (participantId == null) {
      _sendError(request.response, 400, 'Missing participantId');
      return;
    }

    final participantPid = body?['participantPid'] as int? ?? -1;

    try {
      final operation = await _ledger._joinOperationForClient(
        operationId: operationId,
        participantId: participantId,
        participantPid: participantPid,
      );

      _sendJson(request.response, {
        'operationId': operation.operationId,
        'participantId': operation.participantId,
        'isInitiator': operation.isInitiator,
        'sessionId': operation.sessionId,
        'startTime': operation.startTime.toIso8601String(),
      });
    } catch (e) {
      _sendError(request.response, 500, 'Failed to join operation: $e');
    }
  }

  /// Handle POST /operation/leave
  ///
  /// This endpoint handles client session leave notifications.
  /// The actual session cleanup happens on the client side.
  Future<void> _handleLeaveOperation(
    HttpRequest request,
    Map<String, dynamic>? body,
  ) async {
    final operationId = body?['operationId'] as String?;

    if (operationId == null) {
      _sendError(request.response, 400, 'Missing operationId');
      return;
    }

    try {
      final operation = _ledger._getOperationForServer(operationId);
      if (operation == null) {
        _sendError(request.response, 404, 'Operation not found');
        return;
      }

      // Client handles session leave locally - server just acknowledges
      // No session-specific cleanup needed on server side for leave
      _sendJson(request.response, {'success': true});
    } catch (e) {
      _sendError(request.response, 500, 'Failed to leave operation: $e');
    }
  }

  /// Handle POST /operation/complete
  Future<void> _handleCompleteOperation(
    HttpRequest request,
    Map<String, dynamic>? body,
  ) async {
    final operationId = body?['operationId'] as String?;

    if (operationId == null) {
      _sendError(request.response, 400, 'Missing operationId');
      return;
    }

    try {
      final operation = _ledger._getOperationForServer(operationId);
      if (operation == null) {
        _sendError(request.response, 404, 'Operation not found');
        return;
      }

      await operation.complete();

      _sendJson(request.response, {'success': true});
    } catch (e) {
      _sendError(request.response, 500, 'Failed to complete operation: $e');
    }
  }

  /// Handle POST /operation/heartbeat
  Future<void> _handleHeartbeat(
    HttpRequest request,
    Map<String, dynamic>? body,
  ) async {
    final operationId = body?['operationId'] as String?;

    if (operationId == null) {
      _sendError(request.response, 400, 'Missing operationId');
      return;
    }

    try {
      final operation = _ledger._getOperationForServer(operationId);
      if (operation == null) {
        _sendError(request.response, 404, 'Operation not found');
        return;
      }

      final result = await operation.heartbeat();

      if (result == null) {
        _sendJson(request.response, {'success': false, 'reason': 'No ledger'});
      } else {
        _sendJson(request.response, {
          'success': true,
          'abortFlag': result.abortFlag,
          'callFrameCount': result.callFrameCount,
          'tempResourceCount': result.tempResourceCount,
          'heartbeatAgeMs': result.heartbeatAgeMs,
          'isStale': result.isStale,
          'participants': result.participants,
          'staleParticipants': result.staleParticipants,
        });
      }
    } catch (e) {
      _sendError(request.response, 500, 'Heartbeat failed: $e');
    }
  }

  /// Handle POST /operation/abort
  Future<void> _handleSetAbort(
    HttpRequest request,
    Map<String, dynamic>? body,
  ) async {
    final operationId = body?['operationId'] as String?;
    final value = body?['value'] as bool? ?? true;

    if (operationId == null) {
      _sendError(request.response, 400, 'Missing operationId');
      return;
    }

    try {
      final operation = _ledger._getOperationForServer(operationId);
      if (operation == null) {
        _sendError(request.response, 404, 'Operation not found');
        return;
      }

      await operation.setAbortFlag(value);

      _sendJson(request.response, {'success': true});
    } catch (e) {
      _sendError(request.response, 500, 'Failed to set abort flag: $e');
    }
  }

  /// Handle GET /operation/state
  Future<void> _handleGetState(
    HttpRequest request,
    Map<String, dynamic>? body,
  ) async {
    final operationId =
        body?['operationId'] as String? ??
        request.uri.queryParameters['operationId'];

    if (operationId == null) {
      _sendError(request.response, 400, 'Missing operationId');
      return;
    }

    try {
      final operation = _ledger._getOperationForServer(operationId);
      if (operation == null) {
        _sendError(request.response, 404, 'Operation not found');
        return;
      }

      final state = await operation.getOperationState();
      final cachedData = operation.cachedData;

      _sendJson(request.response, {
        'operationId': operationId,
        'state': state?.name ?? 'unknown',
        'aborted': cachedData?.aborted ?? operation.isAborted,
        'callFrameCount': cachedData?.callFrames.length ?? 0,
        'participants': cachedData?.callFrames
            .map((f) => f.participantId)
            .toSet()
            .toList(),
      });
    } catch (e) {
      _sendError(request.response, 500, 'Failed to get state: $e');
    }
  }

  /// Handle POST /operation/log
  Future<void> _handleLog(
    HttpRequest request,
    Map<String, dynamic>? body,
  ) async {
    final operationId = body?['operationId'] as String?;
    final message = body?['message'] as String?;
    final levelStr = body?['level'] as String? ?? 'info';

    if (operationId == null) {
      _sendError(request.response, 400, 'Missing operationId');
      return;
    }
    if (message == null) {
      _sendError(request.response, 400, 'Missing message');
      return;
    }

    try {
      final operation = _ledger._getOperationForServer(operationId);
      if (operation == null) {
        _sendError(request.response, 404, 'Operation not found');
        return;
      }

      final level = LogLevel.values.firstWhere(
        (l) => l.name == levelStr,
        orElse: () => LogLevel.info,
      );

      await operation.log(message, level: level);

      _sendJson(request.response, {'success': true});
    } catch (e) {
      _sendError(request.response, 500, 'Failed to log: $e');
    }
  }

  /// Handle POST /call/start
  Future<void> _handleStartCall(
    HttpRequest request,
    Map<String, dynamic>? body,
  ) async {
    final operationId = body?['operationId'] as String?;
    final description = body?['description'] as String?;
    final failOnCrash = body?['failOnCrash'] as bool? ?? true;

    if (operationId == null) {
      _sendError(request.response, 400, 'Missing operationId');
      return;
    }

    try {
      final operation = _ledger._getOperationForServer(operationId);
      if (operation == null) {
        _sendError(request.response, 404, 'Operation not found');
        return;
      }

      final call = await operation.startCall(
        description: description,
        failOnCrash: failOnCrash,
      );

      _sendJson(request.response, {
        'callId': call.callId,
        'startedAt': call.startedAt.toIso8601String(),
      });
    } catch (e) {
      _sendError(request.response, 500, 'Failed to start call: $e');
    }
  }

  /// Handle POST /call/end
  Future<void> _handleEndCall(
    HttpRequest request,
    Map<String, dynamic>? body,
  ) async {
    final operationId = body?['operationId'] as String?;
    final callId = body?['callId'] as String?;

    if (operationId == null) {
      _sendError(request.response, 400, 'Missing operationId');
      return;
    }
    if (callId == null) {
      _sendError(request.response, 400, 'Missing callId');
      return;
    }

    try {
      final internalOp = _ledger._getInternalOperation(operationId);
      if (internalOp == null) {
        _sendError(request.response, 404, 'Operation not found');
        return;
      }

      // Use low-level API to delete call frame
      await internalOp.deleteCallFrame(callId: callId);

      _sendJson(request.response, {'success': true});
    } catch (e) {
      _sendError(request.response, 500, 'Failed to end call: $e');
    }
  }

  /// Handle POST /call/fail
  Future<void> _handleFailCall(
    HttpRequest request,
    Map<String, dynamic>? body,
  ) async {
    final operationId = body?['operationId'] as String?;
    final callId = body?['callId'] as String?;
    final error = body?['error'] as String?;

    if (operationId == null) {
      _sendError(request.response, 400, 'Missing operationId');
      return;
    }
    if (callId == null) {
      _sendError(request.response, 400, 'Missing callId');
      return;
    }

    try {
      final internalOp = _ledger._getInternalOperation(operationId);
      if (internalOp == null) {
        _sendError(request.response, 404, 'Operation not found');
        return;
      }

      // Delete call frame and log the failure
      await internalOp.deleteCallFrame(callId: callId);
      await internalOp.log(
        'CALL_FAILED callId=$callId error=${error ?? "unknown"}',
        level: LogLevel.error,
      );

      _sendJson(request.response, {'success': true});
    } catch (e) {
      _sendError(request.response, 500, 'Failed to fail call: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Response helpers
  // ─────────────────────────────────────────────────────────────

  void _sendJson(HttpResponse response, Map<String, dynamic> data) {
    response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(data))
      ..close();
  }

  void _sendError(HttpResponse response, int statusCode, String message) {
    response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'error': message}))
      ..close();
  }
}
