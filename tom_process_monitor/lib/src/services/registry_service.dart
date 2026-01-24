import 'dart:convert';
import 'dart:io';

import '../models/registry.dart';
import 'registry_lock.dart';

/// Service for reading and writing the process registry.
class RegistryService {
  /// Directory containing registry files.
  final String directory;

  /// ProcessMonitor instance ID.
  final String instanceId;

  /// Lock for concurrent access.
  late final RegistryLock _lock;

  /// Creates a registry service.
  RegistryService({
    required this.directory,
    required this.instanceId,
  }) {
    _lock = RegistryLock(
      lockPath: '$directory/processes_$instanceId.lock',
      instanceId: instanceId,
    );
  }

  /// Path to the registry file.
  String get registryPath => '$directory/processes_$instanceId.json';

  /// Loads the registry from disk.
  Future<ProcessRegistry> load() async {
    return _lock.withLock(() async {
      return _loadWithoutLock();
    });
  }

  /// Loads the registry without acquiring lock (for internal use).
  Future<ProcessRegistry> _loadWithoutLock() async {
    final file = File(registryPath);
    if (!await file.exists()) {
      return ProcessRegistry(instanceId: instanceId);
    }

    final content = await file.readAsString();
    return ProcessRegistry.fromJson(
      jsonDecode(content) as Map<String, dynamic>,
    );
  }

  /// Saves the registry to disk.
  Future<void> save(ProcessRegistry registry) async {
    return _lock.withLock(() async {
      await _saveWithoutLock(registry);
    });
  }

  /// Saves the registry without acquiring lock (for internal use).
  Future<void> _saveWithoutLock(ProcessRegistry registry) async {
    registry.lastModified = DateTime.now();
    final file = File(registryPath);
    await file.parent.create(recursive: true);
    
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(registry.toJson()));
  }

  /// Executes an operation while holding the lock.
  Future<T> withLock<T>(Future<T> Function(ProcessRegistry registry) operation) async {
    return _lock.withLock(() async {
      final registry = await _loadWithoutLock();
      final result = await operation(registry);
      await _saveWithoutLock(registry);
      return result;
    });
  }

  /// Executes an operation that may not modify the registry.
  Future<T> withLockReadOnly<T>(
    Future<T> Function(ProcessRegistry registry) operation,
  ) async {
    return _lock.withLock(() async {
      final registry = await _loadWithoutLock();
      return await operation(registry);
    });
  }

  /// Initializes the registry directory.
  Future<void> initialize() async {
    final dir = Directory(directory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Checks if registry exists.
  Future<bool> exists() async {
    return File(registryPath).exists();
  }
}
