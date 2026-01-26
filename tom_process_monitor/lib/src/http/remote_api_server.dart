import 'dart:convert';
import 'dart:io';

import 'package:glob/glob.dart';

import '../models/monitor_status.dart';
import '../models/process_config.dart';
import '../models/process_entry.dart';
import '../models/process_state.dart';
import '../models/process_status.dart';
import '../models/registry.dart';
import '../services/process_control.dart';
import '../services/registry_service.dart';

/// Remote HTTP API server for ProcessMonitor.
class RemoteApiServer {
  /// Server port.
  final int port;

  /// Address pattern to bind to.
  ///
  /// Can be:
  /// - `null` - bind to all interfaces (InternetAddress.anyIPv4)
  /// - A full IP like `192.168.1.100` - bind to that specific IP
  /// - A partial pattern like `192.` or `192.168.` - find first matching local IP
  final String? bindAddress;

  /// Registry service.
  final RegistryService registryService;

  /// Process control service.
  final ProcessControl processControl;

  /// Function to get current monitor status.
  final Future<MonitorStatus> Function() getStatus;

  /// Function to trigger monitor restart.
  final Future<void> Function()? onRestartRequested;

  /// Logger function.
  final void Function(String message)? logger;

  HttpServer? _server;
  String? _boundAddress;

  /// Creates a remote API server.
  RemoteApiServer({
    required this.port,
    this.bindAddress,
    required this.registryService,
    required this.processControl,
    required this.getStatus,
    this.onRestartRequested,
    this.logger,
  });

  /// Whether the server is running.
  bool get isRunning => _server != null;

  /// The actual address the server is bound to (available after start).
  String? get boundAddress => _boundAddress;

  /// Starts the server.
  Future<void> start() async {
    final address = await _resolveBindAddress();
    _server = await HttpServer.bind(address, port);
    _boundAddress = address is InternetAddress ? address.address : address.toString();
    _log('Remote API server started on $_boundAddress:$port');
    _server!.listen(_handleRequest);
  }

  /// Resolves the bind address based on the [bindAddress] pattern.
  Future<dynamic> _resolveBindAddress() async {
    if (bindAddress == null) {
      return InternetAddress.anyIPv4;
    }

    // Check if it's a complete IP address (4 octets)
    final parts = bindAddress!.split('.');
    if (parts.length == 4 && parts.every((p) => int.tryParse(p) != null)) {
      return InternetAddress(bindAddress!);
    }

    // It's a pattern - find matching local IP
    final pattern = bindAddress!.endsWith('.') ? bindAddress! : '$bindAddress.';

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.address.startsWith(pattern)) {
            _log('Resolved bind pattern "$bindAddress" to ${addr.address}');
            return addr;
          }
        }
      }
    } catch (e) {
      _log('Error listing network interfaces: $e');
    }

    throw StateError(
      'No network interface found matching pattern "$bindAddress"',
    );
  }

  /// Stops the server.
  Future<void> stop() async {
    _log('Stopping remote API server');
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final registry = await registryService.load();
      final isTrusted = _isTrustedHost(request, registry);

      final pathParts = request.uri.pathSegments;

      if (pathParts.isEmpty) {
        await _sendError(request, HttpStatus.notFound, 'Not Found');
        return;
      }

      // Route handling
      if (pathParts[0] == 'processes') {
        await _handleProcesses(request, registry, isTrusted);
      } else if (pathParts[0] == 'monitor') {
        await _handleMonitor(request, registry, isTrusted);
      } else if (pathParts[0] == 'config') {
        await _handleConfig(request, registry, isTrusted);
      } else {
        await _sendError(request, HttpStatus.notFound, 'Not Found');
      }
    } catch (e) {
      _log('Error handling request: $e');
      await _sendError(request, HttpStatus.internalServerError, e.toString());
    }
  }

  Future<void> _handleProcesses(
    HttpRequest request,
    ProcessRegistry registry,
    bool isTrusted,
  ) async {
    final pathParts = request.uri.pathSegments;

    if (pathParts.length == 1) {
      // /processes
      if (request.method == 'GET') {
        await _listProcesses(request, registry);
      } else if (request.method == 'POST') {
        await _registerProcess(request, registry, isTrusted);
      } else {
        await _sendError(
          request,
          HttpStatus.methodNotAllowed,
          'Method Not Allowed',
        );
      }
    } else if (pathParts.length == 2) {
      // /processes/{id}
      final processId = pathParts[1];
      if (request.method == 'GET') {
        await _getProcess(request, registry, processId);
      } else if (request.method == 'DELETE') {
        await _deregisterProcess(request, registry, processId, isTrusted);
      } else {
        await _sendError(
          request,
          HttpStatus.methodNotAllowed,
          'Method Not Allowed',
        );
      }
    } else if (pathParts.length == 3) {
      // /processes/{id}/{action}
      final processId = pathParts[1];
      final action = pathParts[2];
      await _handleProcessAction(
        request,
        registry,
        processId,
        action,
        isTrusted,
      );
    } else {
      await _sendError(request, HttpStatus.notFound, 'Not Found');
    }
  }

  Future<void> _listProcesses(
    HttpRequest request,
    ProcessRegistry registry,
  ) async {
    final processes = registry.processes.values.map(_toStatusJson).toList();
    await _sendJson(request, {'processes': processes});
  }

  Future<void> _getProcess(
    HttpRequest request,
    ProcessRegistry registry,
    String processId,
  ) async {
    final process = registry.processes[processId];
    if (process == null) {
      await _sendError(
        request,
        HttpStatus.notFound,
        'Process not found',
        extra: {'processId': processId},
      );
      return;
    }
    await _sendJson(request, _toStatusJson(process));
  }

  Future<void> _registerProcess(
    HttpRequest request,
    ProcessRegistry registry,
    bool isTrusted,
  ) async {
    if (!isTrusted && !registry.remoteAccess.allowRemoteRegister) {
      await _sendError(
        request,
        HttpStatus.forbidden,
        'Remote registration not allowed',
      );
      return;
    }

    // Parse and validate request body
    final ProcessConfig config;
    try {
      final body = await _readJsonBody(request);
      config = ProcessConfig.fromJson(body);
    } on FormatException catch (e) {
      await _sendError(
        request,
        HttpStatus.badRequest,
        'Invalid JSON: ${e.message}',
      );
      return;
    } on TypeError catch (e) {
      await _sendError(
        request,
        HttpStatus.badRequest,
        'Missing or invalid field: $e',
      );
      return;
    }

    // Check executable against whitelist/blacklist
    if (!isTrusted && !_isExecutableAllowed(config.command, registry)) {
      await _sendError(
        request,
        HttpStatus.forbidden,
        'Executable not permitted by whitelist/blacklist',
      );
      return;
    }

    if (registry.processes.containsKey(config.id)) {
      await _sendError(
        request,
        HttpStatus.conflict,
        'Process ID already exists',
        extra: {'processId': config.id},
      );
      return;
    }

    // Create entry
    final entry = ProcessEntry(
      id: config.id,
      name: config.name,
      command: config.command,
      args: config.args,
      workingDirectory: config.workingDirectory,
      environment: config.environment,
      autostart: config.autostart,
      enabled: true,
      isRemote: true,
      restartPolicy: config.restartPolicy,
      alivenessCheck: config.alivenessCheck,
      registeredAt: DateTime.now(),
    );

    registry.processes[config.id] = entry;
    await registryService.save(registry);

    await _sendJson(request, {'success': true, 'processId': config.id});
  }

  Future<void> _deregisterProcess(
    HttpRequest request,
    ProcessRegistry registry,
    String processId,
    bool isTrusted,
  ) async {
    final process = registry.processes[processId];
    if (process == null) {
      await _sendError(
        request,
        HttpStatus.notFound,
        'Process not found',
        extra: {'processId': processId},
      );
      return;
    }

    if (!isTrusted) {
      if (!registry.remoteAccess.allowRemoteDeregister) {
        await _sendError(
          request,
          HttpStatus.forbidden,
          'Remote deregistration not allowed',
        );
        return;
      }
      if (!process.isRemote) {
        await _sendError(
          request,
          HttpStatus.forbidden,
          'Cannot modify local process',
        );
        return;
      }
    }

    // Stop if running
    if (process.pid != null && process.state == ProcessState.running) {
      await processControl.stopProcessGracefully(process.pid!);
    }

    registry.processes.remove(processId);
    await registryService.save(registry);

    await _sendJson(request, {'success': true});
  }

  Future<void> _handleProcessAction(
    HttpRequest request,
    ProcessRegistry registry,
    String processId,
    String action,
    bool isTrusted,
  ) async {
    final process = registry.processes[processId];
    if (process == null) {
      await _sendError(
        request,
        HttpStatus.notFound,
        'Process not found',
        extra: {'processId': processId},
      );
      return;
    }

    // Check permissions for non-trusted hosts
    if (!isTrusted && !process.isRemote) {
      await _sendError(
        request,
        HttpStatus.forbidden,
        'Cannot modify local process',
      );
      return;
    }

    switch (action) {
      case 'start':
        if (!isTrusted && !registry.remoteAccess.allowRemoteStart) {
          await _sendError(
            request,
            HttpStatus.forbidden,
            'Remote start not allowed',
          );
          return;
        }
        if (!process.enabled) {
          await _sendError(
            request,
            HttpStatus.badRequest,
            'Process is disabled',
          );
          return;
        }
        process.state = ProcessState.starting;
        await registryService.save(registry);
        await _sendJson(request, {'success': true, 'state': 'starting'});

      case 'stop':
        if (!isTrusted && !registry.remoteAccess.allowRemoteStop) {
          await _sendError(
            request,
            HttpStatus.forbidden,
            'Remote stop not allowed',
          );
          return;
        }
        if (process.pid != null) {
          process.state = ProcessState.stopping;
          await processControl.stopProcessGracefully(process.pid!);
          process.pid = null;
          process.lastStoppedAt = DateTime.now();
        }
        process.state = ProcessState.stopped;
        await registryService.save(registry);
        await _sendJson(request, {'success': true, 'state': 'stopped'});

      case 'restart':
        if (!isTrusted && !registry.remoteAccess.allowRemoteStart) {
          await _sendError(
            request,
            HttpStatus.forbidden,
            'Remote restart not allowed',
          );
          return;
        }
        // Stop then start
        if (process.pid != null) {
          await processControl.stopProcessGracefully(process.pid!);
          process.pid = null;
          process.lastStoppedAt = DateTime.now();
        }
        process.state = ProcessState.starting;
        await registryService.save(registry);
        await _sendJson(request, {'success': true, 'state': 'starting'});

      case 'enable':
        if (!isTrusted && !registry.remoteAccess.allowRemoteDisable) {
          await _sendError(
            request,
            HttpStatus.forbidden,
            'Remote enable not allowed',
          );
          return;
        }
        process.enabled = true;
        if (process.state == ProcessState.disabled) {
          process.state = ProcessState.stopped;
        }
        await registryService.save(registry);
        await _sendJson(request, {'success': true});

      case 'disable':
        if (!isTrusted && !registry.remoteAccess.allowRemoteDisable) {
          await _sendError(
            request,
            HttpStatus.forbidden,
            'Remote disable not allowed',
          );
          return;
        }
        if (process.pid != null && process.state == ProcessState.running) {
          await processControl.stopProcessGracefully(process.pid!);
          process.pid = null;
          process.lastStoppedAt = DateTime.now();
        }
        process.enabled = false;
        process.state = ProcessState.disabled;
        await registryService.save(registry);
        await _sendJson(request, {'success': true});

      case 'autostart':
        if (request.method != 'PUT') {
          await _sendError(request, HttpStatus.methodNotAllowed, 'Use PUT');
          return;
        }
        if (!isTrusted && !registry.remoteAccess.allowRemoteAutostart) {
          await _sendError(
            request,
            HttpStatus.forbidden,
            'Remote autostart not allowed',
          );
          return;
        }
        final body = await _readJsonBody(request);
        process.autostart = body['autostart'] as bool;
        await registryService.save(registry);
        await _sendJson(request, {'success': true});

      default:
        await _sendError(
          request,
          HttpStatus.notFound,
          'Unknown action: $action',
        );
    }
  }

  Future<void> _handleMonitor(
    HttpRequest request,
    ProcessRegistry registry,
    bool isTrusted,
  ) async {
    final pathParts = request.uri.pathSegments;

    if (pathParts.length < 2) {
      await _sendError(request, HttpStatus.notFound, 'Not Found');
      return;
    }

    final action = pathParts[1];

    switch (action) {
      case 'status':
        if (request.method == 'GET') {
          final status = await getStatus();
          await _sendJson(request, status.toJson());
        } else {
          await _sendError(request, HttpStatus.methodNotAllowed, 'Use GET');
        }

      case 'restart':
        if (request.method == 'POST') {
          if (!isTrusted && !registry.remoteAccess.allowRemoteMonitorRestart) {
            await _sendError(
              request,
              HttpStatus.forbidden,
              'Monitor restart not allowed',
            );
            return;
          }
          await _sendJson(request, {
            'success': true,
            'message': 'ProcessMonitor restart initiated',
          });
          // Trigger restart after response
          onRestartRequested?.call();
        } else {
          await _sendError(request, HttpStatus.methodNotAllowed, 'Use POST');
        }

      default:
        await _sendError(request, HttpStatus.notFound, 'Unknown endpoint');
    }
  }

  Future<void> _handleConfig(
    HttpRequest request,
    ProcessRegistry registry,
    bool isTrusted,
  ) async {
    final pathParts = request.uri.pathSegments;

    if (pathParts.length < 2) {
      await _sendError(request, HttpStatus.notFound, 'Not Found');
      return;
    }

    // All config endpoints require trusted host for write operations
    if (request.method == 'PUT' && !isTrusted) {
      await _sendError(
        request,
        HttpStatus.forbidden,
        'Configuration changes require trusted host',
      );
      return;
    }

    final configType = pathParts[1];

    switch (configType) {
      case 'remote-access':
        if (request.method == 'GET') {
          await _sendJson(request, registry.remoteAccess.toJson());
        } else if (request.method == 'PUT') {
          final body = await _readJsonBody(request);
          registry.remoteAccess = registry.remoteAccess.copyWith(
            allowRemoteRegister: body['allowRemoteRegister'] as bool?,
            allowRemoteDeregister: body['allowRemoteDeregister'] as bool?,
            allowRemoteStart: body['allowRemoteStart'] as bool?,
            allowRemoteStop: body['allowRemoteStop'] as bool?,
            allowRemoteDisable: body['allowRemoteDisable'] as bool?,
            allowRemoteAutostart: body['allowRemoteAutostart'] as bool?,
            allowRemoteMonitorRestart:
                body['allowRemoteMonitorRestart'] as bool?,
          );
          await registryService.save(registry);
          await _sendJson(request, registry.remoteAccess.toJson());
        }

      case 'trusted-hosts':
        if (request.method == 'GET') {
          await _sendJson(request, {
            'trustedHosts': registry.remoteAccess.trustedHosts,
          });
        } else if (request.method == 'PUT') {
          final body = await _readJsonBody(request);
          final hosts = (body['trustedHosts'] as List<dynamic>)
              .map((e) => e as String)
              .toList();
          registry.remoteAccess = registry.remoteAccess.copyWith(
            trustedHosts: hosts,
          );
          await registryService.save(registry);
          await _sendJson(request, {'trustedHosts': hosts});
        }

      case 'executable-whitelist':
        if (request.method == 'GET') {
          await _sendJson(request, {
            'patterns': registry.remoteAccess.executableWhitelist,
          });
        } else if (request.method == 'PUT') {
          final body = await _readJsonBody(request);
          final patterns = (body['patterns'] as List<dynamic>)
              .map((e) => e as String)
              .toList();
          registry.remoteAccess = registry.remoteAccess.copyWith(
            executableWhitelist: patterns,
          );
          await registryService.save(registry);
          await _sendJson(request, {'patterns': patterns});
        }

      case 'executable-blacklist':
        if (request.method == 'GET') {
          await _sendJson(request, {
            'patterns': registry.remoteAccess.executableBlacklist,
          });
        } else if (request.method == 'PUT') {
          final body = await _readJsonBody(request);
          final patterns = (body['patterns'] as List<dynamic>)
              .map((e) => e as String)
              .toList();
          registry.remoteAccess = registry.remoteAccess.copyWith(
            executableBlacklist: patterns,
          );
          await registryService.save(registry);
          await _sendJson(request, {'patterns': patterns});
        }

      case 'standalone-mode':
        if (request.method == 'GET') {
          await _sendJson(request, {'enabled': registry.standaloneMode});
        } else if (request.method == 'PUT') {
          final body = await _readJsonBody(request);
          registry.standaloneMode = body['enabled'] as bool;
          await registryService.save(registry);
          await _sendJson(request, {'enabled': registry.standaloneMode});
        }

      case 'partner-discovery':
        if (request.method == 'GET') {
          await _sendJson(request, registry.partnerDiscovery.toJson());
        } else if (request.method == 'PUT') {
          final body = await _readJsonBody(request);
          registry.partnerDiscovery = registry.partnerDiscovery.copyWith(
            partnerInstanceId: body['partnerInstanceId'] as String?,
            partnerAlivenessPort: body['partnerAlivenessPort'] as int?,
            partnerStatusUrl: body['partnerStatusUrl'] as String?,
            discoveryOnStartup: body['discoveryOnStartup'] as bool?,
            startPartnerIfMissing: body['startPartnerIfMissing'] as bool?,
          );
          await registryService.save(registry);
          await _sendJson(request, registry.partnerDiscovery.toJson());
        }

      default:
        await _sendError(request, HttpStatus.notFound, 'Unknown config type');
    }
  }

  bool _isTrustedHost(HttpRequest request, ProcessRegistry registry) {
    // Get client IP from various headers or socket
    String? clientIp;

    // Check X-Forwarded-For (first IP is the original client)
    final forwarded = request.headers.value('X-Forwarded-For');
    if (forwarded != null) {
      clientIp = forwarded.split(',').first.trim();
    }

    // Check X-Real-IP
    clientIp ??= request.headers.value('X-Real-IP');

    // Use socket address
    clientIp ??= request.connectionInfo?.remoteAddress.address;

    if (clientIp == null) return false;

    // Check each trusted host pattern
    return registry.remoteAccess.trustedHosts.any((pattern) {
      return _matchesTrustedHostPattern(clientIp!, pattern);
    });
  }

  /// Matches a client IP or hostname against a trusted host pattern.
  ///
  /// Supports:
  /// - Exact match: `192.168.1.100`, `localhost`
  /// - IP wildcards: `192.168.1.*`, `10.0.*.*`
  /// - Hostname wildcards: `*.mydomain.com`, `server-*.local`
  bool _matchesTrustedHostPattern(String clientIp, String pattern) {
    // Exact match
    if (clientIp == pattern) return true;

    // Check if pattern contains wildcard
    if (!pattern.contains('*')) return false;

    // Convert pattern to regex
    // Escape special regex chars except *, then convert * to regex pattern
    final escaped = pattern
        .replaceAll('.', r'\.')
        .replaceAll('*', '[^.]*'); // * matches any chars except dots

    final regex = RegExp('^$escaped\$');
    return regex.hasMatch(clientIp);
  }

  bool _isExecutableAllowed(String command, ProcessRegistry registry) {
    final whitelist = registry.remoteAccess.executableWhitelist;
    final blacklist = registry.remoteAccess.executableBlacklist;

    // Security: whitelist MUST be configured for remote registration to work.
    // An empty whitelist blocks all remote registrations.
    if (whitelist.isEmpty) {
      return false;
    }

    // Command must match at least one whitelist pattern
    final matches = whitelist.any((pattern) => Glob(pattern).matches(command));
    if (!matches) return false;

    // If blacklist is non-empty, command must not match any pattern
    if (blacklist.isNotEmpty) {
      final blocked = blacklist.any(
        (pattern) => Glob(pattern).matches(command),
      );
      if (blocked) return false;
    }

    return true;
  }

  Map<String, dynamic> _toStatusJson(ProcessEntry entry) {
    return ProcessStatus(
      id: entry.id,
      name: entry.name,
      state: entry.state,
      enabled: entry.enabled,
      autostart: entry.autostart,
      isRemote: entry.isRemote,
      pid: entry.pid,
      lastStartedAt: entry.lastStartedAt,
      lastStoppedAt: entry.lastStoppedAt,
      restartAttempts: entry.restartAttempts,
    ).toJson();
  }

  Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
    final content = await utf8.decoder.bind(request).join();
    return jsonDecode(content) as Map<String, dynamic>;
  }

  Future<void> _sendJson(HttpRequest request, Map<String, dynamic> data) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(data));
    await request.response.close();
  }

  Future<void> _sendError(
    HttpRequest request,
    int statusCode,
    String message, {
    Map<String, dynamic>? extra,
  }) async {
    final data = {'error': message, ...?extra};
    request.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(data));
    await request.response.close();
  }

  void _log(String message) {
    logger?.call(message);
  }
}
