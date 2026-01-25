/// Cleanup handler for graceful shutdown and signal handling.
///
/// Provides automatic cleanup of registered temp resources on process
/// termination, signal interruption (SIGINT, SIGTERM), or manual trigger.
library;

import 'dart:async';
import 'dart:io';

/// Callback type for cleanup functions.
typedef CleanupCallback = Future<void> Function();

/// Manages cleanup handlers and responds to process signals.
///
/// This singleton ensures that registered cleanup functions are called
/// when the process receives SIGINT (Ctrl+C) or SIGTERM signals, or when
/// [cleanup] is called manually.
///
/// ## Usage
///
/// ```dart
/// // Register a cleanup callback
/// final id = CleanupHandler.instance.register(() async {
///   await myOperation.cleanupLocalTempResources();
/// });
///
/// // ... do work ...
///
/// // Unregister when no longer needed
/// CleanupHandler.instance.unregister(id);
/// ```
///
/// Signal handlers are automatically installed on first registration.
class CleanupHandler {
  static CleanupHandler? _instance;

  /// Get the singleton instance.
  static CleanupHandler get instance => _instance ??= CleanupHandler._();

  CleanupHandler._();

  final Map<int, CleanupCallback> _handlers = {};
  int _nextId = 0;
  bool _signalsInstalled = false;
  bool _isCleaningUp = false;
  StreamSubscription<ProcessSignal>? _sigintSubscription;
  StreamSubscription<ProcessSignal>? _sigtermSubscription;

  /// Register a cleanup callback.
  ///
  /// Returns an ID that can be used to unregister the callback.
  int register(CleanupCallback callback) {
    _ensureSignalsInstalled();
    final id = _nextId++;
    _handlers[id] = callback;
    return id;
  }

  /// Unregister a cleanup callback by ID.
  void unregister(int id) {
    _handlers.remove(id);
  }

  /// Install signal handlers if not already installed.
  void _ensureSignalsInstalled() {
    if (_signalsInstalled) return;
    _signalsInstalled = true;

    // SIGINT (Ctrl+C)
    try {
      _sigintSubscription = ProcessSignal.sigint.watch().listen((signal) {
        _handleSignal('SIGINT');
      });
    } catch (e) {
      // Signal watching not supported on this platform
      stderr.writeln('Warning: SIGINT handler not installed: $e');
    }

    // SIGTERM (kill)
    try {
      _sigtermSubscription = ProcessSignal.sigterm.watch().listen((signal) {
        _handleSignal('SIGTERM');
      });
    } catch (e) {
      // Signal watching not supported on this platform
      stderr.writeln('Warning: SIGTERM handler not installed: $e');
    }
  }

  /// Handle a signal by running all cleanup handlers.
  Future<void> _handleSignal(String signalName) async {
    stderr.writeln('[$signalName] Running cleanup handlers...');
    await cleanup();
    stderr.writeln('[$signalName] Cleanup complete, exiting.');
    exit(0);
  }

  /// Manually trigger all cleanup handlers.
  ///
  /// This is idempotent - calling multiple times will only run cleanup once.
  Future<void> cleanup() async {
    if (_isCleaningUp) return;
    _isCleaningUp = true;

    // Copy handlers to avoid modification during iteration
    final handlersCopy = Map<int, CleanupCallback>.from(_handlers);

    for (final entry in handlersCopy.entries) {
      try {
        await entry.value();
      } catch (e) {
        stderr.writeln('Cleanup handler ${entry.key} failed: $e');
      }
    }

    _handlers.clear();
    _isCleaningUp = false;
  }

  /// Dispose the cleanup handler and cancel signal subscriptions.
  void dispose() {
    _sigintSubscription?.cancel();
    _sigtermSubscription?.cancel();
    _handlers.clear();
    _signalsInstalled = false;
    _instance = null;
  }
}
