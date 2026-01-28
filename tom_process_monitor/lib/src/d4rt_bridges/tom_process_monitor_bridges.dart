// D4rt Bridge - Generated file, do not edit
// Sources: 26 files
// Generated: 2026-01-28T20:18:30.456836

import 'package:tom_d4rt/d4rt.dart';
import 'package:tom_d4rt/tom_d4rt.dart';
import 'dart:async';

import 'package:tom_process_monitor/tom_process_monitor.dart' as $pkg;

/// Bridge class for all module.
class AllBridge {
  /// Returns all bridge class definitions.
  static List<BridgedClass> bridgeClasses() {
    return [
      _createProcessConfigBridge(),
      _createProcessEntryBridge(),
      _createProcessStatusBridge(),
      _createMonitorStatusBridge(),
      _createRestartPolicyBridge(),
      _createAlivenessCheckBridge(),
      _createStartupCheckBridge(),
      _createRemoteAccessConfigBridge(),
      _createPartnerDiscoveryConfigBridge(),
      _createAlivenessServerConfigBridge(),
      _createWatcherInfoBridge(),
      _createProcessRegistryBridge(),
      _createProcessMonitorExceptionBridge(),
      _createLockTimeoutExceptionBridge(),
      _createProcessNotFoundExceptionBridge(),
      _createProcessDisabledExceptionBridge(),
      _createPermissionDeniedExceptionBridge(),
      _createLockInfoBridge(),
      _createRegistryLockBridge(),
      _createRegistryServiceBridge(),
      _createProcessControlBridge(),
      _createAlivenessCheckerBridge(),
      _createAlivenessCallbackBridge(),
      _createLogManagerBridge(),
      _createRetryExhaustedExceptionBridge(),
      _createRetryConfigBridge(),
      _createProcessMonitorClientBridge(),
      _createLocalProcessMonitorClientBridge(),
      _createDiscoveryFailedExceptionBridge(),
      _createRemoteProcessMonitorClientBridge(),
    ];
  }

  /// Returns all bridged enum definitions.
  static List<BridgedEnumDefinition> bridgedEnums() {
    return [
      BridgedEnumDefinition<$pkg.ProcessState>(
        name: 'ProcessState',
        values: $pkg.ProcessState.values,
      ),
    ];
  }

  /// Registers all bridges with an interpreter.
  ///
  /// [importPath] is the package import path that D4rt scripts will use
  /// to access these classes (e.g., 'package:tom_build/tom.dart').
  static void registerBridges(D4rt interpreter, String importPath) {
    // Register bridged classes
    for (final bridge in bridgeClasses()) {
      interpreter.registerBridgedClass(bridge, importPath);
    }

    // Register bridged enums
    for (final enumDef in bridgedEnums()) {
      interpreter.registerBridgedEnum(enumDef, importPath);
    }

    // Register global variables
    registerGlobalVariables(interpreter);

    // Register global functions
    for (final entry in globalFunctions().entries) {
      interpreter.registertopLevelFunction(entry.key, entry.value);
    }
  }

  /// Registers all global variables with the interpreter.
  static void registerGlobalVariables(D4rt interpreter) {
    interpreter.registerGlobalVariable('kDefaultRetryDelaysMs', $pkg.kDefaultRetryDelaysMs);
  }

  /// Returns a map of global function names to their native implementations.
  static Map<String, NativeFunctionImpl> globalFunctions() {
    return {
      'withRetry': (visitor, positional, named, typeArgs) {
        D4.requireMinArgs(positional, 1, 'withRetry');
        final operation = D4.getRequiredArg<dynamic>(positional, 0, 'operation', 'withRetry');
        final config = D4.getNamedArgWithDefault<$pkg.RetryConfig>(named, 'config', $pkg.RetryConfig.defaultConfig);
        final shouldRetry = D4.getOptionalNamedArg<dynamic?>(named, 'shouldRetry');
        return $pkg.withRetry<dynamic>(operation, config: config, shouldRetry: shouldRetry);
      },
    };
  }

  /// Returns the import statement needed for D4rt scripts.
  ///
  /// Use this in your D4rt initialization script to make all
  /// bridged classes available to scripts.
  static String getImportBlock() {
    return "import 'package:tom_process_monitor/tom_process_monitor.dart';";
  }

  /// Returns a list of bridged enum names.
  static List<String> get enumNames => [
    'ProcessState',
  ];

  /// Returns D4rt script code that documents available global functions.
  ///
  /// These functions are available directly in D4rt scripts when
  /// the import block is included in the initialization script.
  static List<String> get globalFunctionNames => [
    'withRetry',
  ];

  /// Returns a list of global variable names.
  static List<String> get globalVariableNames => [
    'kDefaultRetryDelaysMs',
  ];

  /// Returns D4rt script code to initialize global functions and variables.
  ///
  /// This script creates wrapper functions that delegate to the static methods
  /// in GlobalBridge, and mirrors global variables. Include this in your D4rt
  /// initialization script after registering bridges.
  ///
  /// Example:
  /// ```dart
  /// interpreter.execute(source: getGlobalInitializationScript());
  /// ```
  static String getGlobalInitializationScript() {
    return '''
Future<T> withRetry(Future<T> Function() operation, {RetryConfig? config, bool Function(Object error)? shouldRetry}) => AllBridge.withRetry(operation, config: config, shouldRetry: shouldRetry);
List<int> get kDefaultRetryDelaysMs => AllBridge.kDefaultRetryDelaysMs;
''';
  }

}

// =============================================================================
// ProcessConfig Bridge
// =============================================================================

BridgedClass _createProcessConfigBridge() {
  return BridgedClass(
    nativeType: $pkg.ProcessConfig,
    name: 'ProcessConfig',
    constructors: {
      '': (visitor, positional, named) {
        final id = D4.getRequiredNamedArg<String>(named, 'id', 'ProcessConfig');
        final name = D4.getRequiredNamedArg<String>(named, 'name', 'ProcessConfig');
        final command = D4.getRequiredNamedArg<String>(named, 'command', 'ProcessConfig');
        final args = named.containsKey('args') && named['args'] != null
            ? D4.coerceList<String>(named['args'], 'args')
            : const <String>[];
        final workingDirectory = D4.getOptionalNamedArg<String?>(named, 'workingDirectory');
        final environment = D4.coerceMapOrNull<String, String>(named['environment'], 'environment');
        final autostart = D4.getNamedArgWithDefault<bool>(named, 'autostart', true);
        final restartPolicy = D4.getOptionalNamedArg<$pkg.RestartPolicy?>(named, 'restartPolicy');
        final alivenessCheck = D4.getOptionalNamedArg<$pkg.AlivenessCheck?>(named, 'alivenessCheck');
        return $pkg.ProcessConfig(id: id, name: name, command: command, args: args, workingDirectory: workingDirectory, environment: environment, autostart: autostart, restartPolicy: restartPolicy, alivenessCheck: alivenessCheck);
      },
      'fromJson': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'ProcessConfig');
        if (positional.length <= 0) {
          throw ArgumentError('ProcessConfig: Missing required argument "json" at position 0');
        }
        final json = D4.coerceMap<String, dynamic>(positional[0], 'json');
        return $pkg.ProcessConfig.fromJson(json);
      },
    },
    getters: {
      'id': (visitor, target) => D4.validateTarget<$pkg.ProcessConfig>(target, 'ProcessConfig').id,
      'name': (visitor, target) => D4.validateTarget<$pkg.ProcessConfig>(target, 'ProcessConfig').name,
      'command': (visitor, target) => D4.validateTarget<$pkg.ProcessConfig>(target, 'ProcessConfig').command,
      'args': (visitor, target) => D4.validateTarget<$pkg.ProcessConfig>(target, 'ProcessConfig').args,
      'workingDirectory': (visitor, target) => D4.validateTarget<$pkg.ProcessConfig>(target, 'ProcessConfig').workingDirectory,
      'environment': (visitor, target) => D4.validateTarget<$pkg.ProcessConfig>(target, 'ProcessConfig').environment,
      'autostart': (visitor, target) => D4.validateTarget<$pkg.ProcessConfig>(target, 'ProcessConfig').autostart,
      'restartPolicy': (visitor, target) => D4.validateTarget<$pkg.ProcessConfig>(target, 'ProcessConfig').restartPolicy,
      'alivenessCheck': (visitor, target) => D4.validateTarget<$pkg.ProcessConfig>(target, 'ProcessConfig').alivenessCheck,
    },
    methods: {
      'toJson': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessConfig>(target, 'ProcessConfig');
        return t.toJson();
      },
      'copyWith': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessConfig>(target, 'ProcessConfig');
        final id = D4.getOptionalNamedArg<String?>(named, 'id');
        final name = D4.getOptionalNamedArg<String?>(named, 'name');
        final command = D4.getOptionalNamedArg<String?>(named, 'command');
        final args = D4.coerceListOrNull<String>(named['args'], 'args');
        final workingDirectory = D4.getOptionalNamedArg<String?>(named, 'workingDirectory');
        final environment = D4.coerceMapOrNull<String, String>(named['environment'], 'environment');
        final autostart = D4.getOptionalNamedArg<bool?>(named, 'autostart');
        final restartPolicy = D4.getOptionalNamedArg<$pkg.RestartPolicy?>(named, 'restartPolicy');
        final alivenessCheck = D4.getOptionalNamedArg<$pkg.AlivenessCheck?>(named, 'alivenessCheck');
        return t.copyWith(id: id, name: name, command: command, args: args, workingDirectory: workingDirectory, environment: environment, autostart: autostart, restartPolicy: restartPolicy, alivenessCheck: alivenessCheck);
      },
    },
  );
}

// =============================================================================
// ProcessEntry Bridge
// =============================================================================

BridgedClass _createProcessEntryBridge() {
  return BridgedClass(
    nativeType: $pkg.ProcessEntry,
    name: 'ProcessEntry',
    constructors: {
      '': (visitor, positional, named) {
        final id = D4.getRequiredNamedArg<String>(named, 'id', 'ProcessEntry');
        final name = D4.getRequiredNamedArg<String>(named, 'name', 'ProcessEntry');
        final command = D4.getRequiredNamedArg<String>(named, 'command', 'ProcessEntry');
        final args = named.containsKey('args') && named['args'] != null
            ? D4.coerceList<String>(named['args'], 'args')
            : const <String>[];
        final workingDirectory = D4.getOptionalNamedArg<String?>(named, 'workingDirectory');
        final environment = D4.coerceMapOrNull<String, String>(named['environment'], 'environment');
        final autostart = D4.getNamedArgWithDefault<bool>(named, 'autostart', true);
        final enabled = D4.getNamedArgWithDefault<bool>(named, 'enabled', true);
        final isRemote = D4.getNamedArgWithDefault<bool>(named, 'isRemote', false);
        final restartPolicy = D4.getOptionalNamedArg<$pkg.RestartPolicy?>(named, 'restartPolicy');
        final alivenessCheck = D4.getOptionalNamedArg<$pkg.AlivenessCheck?>(named, 'alivenessCheck');
        final registeredAt = D4.getRequiredNamedArg<DateTime>(named, 'registeredAt', 'ProcessEntry');
        final lastStartedAt = D4.getOptionalNamedArg<DateTime?>(named, 'lastStartedAt');
        final lastStoppedAt = D4.getOptionalNamedArg<DateTime?>(named, 'lastStoppedAt');
        final pid = D4.getOptionalNamedArg<int?>(named, 'pid');
        final state = D4.getNamedArgWithDefault<dynamic>(named, 'state', $pkg.ProcessState.stopped);
        final restartAttempts = D4.getNamedArgWithDefault<int>(named, 'restartAttempts', 0);
        final consecutiveFailures = D4.getNamedArgWithDefault<int>(named, 'consecutiveFailures', 0);
        return $pkg.ProcessEntry(id: id, name: name, command: command, args: args, workingDirectory: workingDirectory, environment: environment, autostart: autostart, enabled: enabled, isRemote: isRemote, restartPolicy: restartPolicy, alivenessCheck: alivenessCheck, registeredAt: registeredAt, lastStartedAt: lastStartedAt, lastStoppedAt: lastStoppedAt, pid: pid, state: state, restartAttempts: restartAttempts, consecutiveFailures: consecutiveFailures);
      },
      'fromJson': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'ProcessEntry');
        if (positional.length <= 0) {
          throw ArgumentError('ProcessEntry: Missing required argument "json" at position 0');
        }
        final json = D4.coerceMap<String, dynamic>(positional[0], 'json');
        return $pkg.ProcessEntry.fromJson(json);
      },
    },
    getters: {
      'id': (visitor, target) => D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').id,
      'name': (visitor, target) => D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').name,
      'command': (visitor, target) => D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').command,
      'args': (visitor, target) => D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').args,
      'workingDirectory': (visitor, target) => D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').workingDirectory,
      'environment': (visitor, target) => D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').environment,
      'autostart': (visitor, target) => D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').autostart,
      'enabled': (visitor, target) => D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').enabled,
      'isRemote': (visitor, target) => D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').isRemote,
      'restartPolicy': (visitor, target) => D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').restartPolicy,
      'alivenessCheck': (visitor, target) => D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').alivenessCheck,
      'registeredAt': (visitor, target) => D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').registeredAt,
      'lastStartedAt': (visitor, target) => D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').lastStartedAt,
      'lastStoppedAt': (visitor, target) => D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').lastStoppedAt,
      'pid': (visitor, target) => D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').pid,
      'state': (visitor, target) => D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').state,
      'restartAttempts': (visitor, target) => D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').restartAttempts,
      'consecutiveFailures': (visitor, target) => D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').consecutiveFailures,
    },
    setters: {
      'id': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').id = value as String,
      'name': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').name = value as String,
      'command': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').command = value as String,
      'args': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').args = value as List<String>,
      'workingDirectory': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').workingDirectory = value as String?,
      'environment': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').environment = value as Map<String, String>,
      'autostart': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').autostart = value as bool,
      'enabled': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').enabled = value as bool,
      'isRemote': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').isRemote = value as bool,
      'restartPolicy': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').restartPolicy = value as $pkg.RestartPolicy?,
      'alivenessCheck': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').alivenessCheck = value as $pkg.AlivenessCheck?,
      'registeredAt': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').registeredAt = value as DateTime,
      'lastStartedAt': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').lastStartedAt = value as DateTime?,
      'lastStoppedAt': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').lastStoppedAt = value as DateTime?,
      'pid': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').pid = value as int?,
      'state': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').state = value as dynamic,
      'restartAttempts': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').restartAttempts = value as int,
      'consecutiveFailures': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry').consecutiveFailures = value as int,
    },
    methods: {
      'toJson': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry');
        return t.toJson();
      },
      'copyWith': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessEntry>(target, 'ProcessEntry');
        final id = D4.getOptionalNamedArg<String?>(named, 'id');
        final name = D4.getOptionalNamedArg<String?>(named, 'name');
        final command = D4.getOptionalNamedArg<String?>(named, 'command');
        final args = D4.coerceListOrNull<String>(named['args'], 'args');
        final workingDirectory = D4.getOptionalNamedArg<String?>(named, 'workingDirectory');
        final environment = D4.coerceMapOrNull<String, String>(named['environment'], 'environment');
        final autostart = D4.getOptionalNamedArg<bool?>(named, 'autostart');
        final enabled = D4.getOptionalNamedArg<bool?>(named, 'enabled');
        final isRemote = D4.getOptionalNamedArg<bool?>(named, 'isRemote');
        final restartPolicy = D4.getOptionalNamedArg<$pkg.RestartPolicy?>(named, 'restartPolicy');
        final alivenessCheck = D4.getOptionalNamedArg<$pkg.AlivenessCheck?>(named, 'alivenessCheck');
        final registeredAt = D4.getOptionalNamedArg<DateTime?>(named, 'registeredAt');
        final lastStartedAt = D4.getOptionalNamedArg<DateTime?>(named, 'lastStartedAt');
        final lastStoppedAt = D4.getOptionalNamedArg<DateTime?>(named, 'lastStoppedAt');
        final pid = D4.getOptionalNamedArg<int?>(named, 'pid');
        final state = D4.getOptionalNamedArg<dynamic>(named, 'state');
        final restartAttempts = D4.getOptionalNamedArg<int?>(named, 'restartAttempts');
        final consecutiveFailures = D4.getOptionalNamedArg<int?>(named, 'consecutiveFailures');
        return t.copyWith(id: id, name: name, command: command, args: args, workingDirectory: workingDirectory, environment: environment, autostart: autostart, enabled: enabled, isRemote: isRemote, restartPolicy: restartPolicy, alivenessCheck: alivenessCheck, registeredAt: registeredAt, lastStartedAt: lastStartedAt, lastStoppedAt: lastStoppedAt, pid: pid, state: state, restartAttempts: restartAttempts, consecutiveFailures: consecutiveFailures);
      },
    },
  );
}

// =============================================================================
// ProcessStatus Bridge
// =============================================================================

BridgedClass _createProcessStatusBridge() {
  return BridgedClass(
    nativeType: $pkg.ProcessStatus,
    name: 'ProcessStatus',
    constructors: {
      '': (visitor, positional, named) {
        final id = D4.getRequiredNamedArg<String>(named, 'id', 'ProcessStatus');
        final name = D4.getRequiredNamedArg<String>(named, 'name', 'ProcessStatus');
        final state = D4.getRequiredNamedArg<dynamic>(named, 'state', 'ProcessStatus');
        final enabled = D4.getRequiredNamedArg<bool>(named, 'enabled', 'ProcessStatus');
        final autostart = D4.getRequiredNamedArg<bool>(named, 'autostart', 'ProcessStatus');
        final isRemote = D4.getRequiredNamedArg<bool>(named, 'isRemote', 'ProcessStatus');
        final pid = D4.getOptionalNamedArg<int?>(named, 'pid');
        final lastStartedAt = D4.getOptionalNamedArg<DateTime?>(named, 'lastStartedAt');
        final lastStoppedAt = D4.getOptionalNamedArg<DateTime?>(named, 'lastStoppedAt');
        final restartAttempts = D4.getNamedArgWithDefault<int>(named, 'restartAttempts', 0);
        return $pkg.ProcessStatus(id: id, name: name, state: state, enabled: enabled, autostart: autostart, isRemote: isRemote, pid: pid, lastStartedAt: lastStartedAt, lastStoppedAt: lastStoppedAt, restartAttempts: restartAttempts);
      },
      'fromJson': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'ProcessStatus');
        if (positional.length <= 0) {
          throw ArgumentError('ProcessStatus: Missing required argument "json" at position 0');
        }
        final json = D4.coerceMap<String, dynamic>(positional[0], 'json');
        return $pkg.ProcessStatus.fromJson(json);
      },
    },
    getters: {
      'id': (visitor, target) => D4.validateTarget<$pkg.ProcessStatus>(target, 'ProcessStatus').id,
      'name': (visitor, target) => D4.validateTarget<$pkg.ProcessStatus>(target, 'ProcessStatus').name,
      'state': (visitor, target) => D4.validateTarget<$pkg.ProcessStatus>(target, 'ProcessStatus').state,
      'enabled': (visitor, target) => D4.validateTarget<$pkg.ProcessStatus>(target, 'ProcessStatus').enabled,
      'autostart': (visitor, target) => D4.validateTarget<$pkg.ProcessStatus>(target, 'ProcessStatus').autostart,
      'isRemote': (visitor, target) => D4.validateTarget<$pkg.ProcessStatus>(target, 'ProcessStatus').isRemote,
      'pid': (visitor, target) => D4.validateTarget<$pkg.ProcessStatus>(target, 'ProcessStatus').pid,
      'lastStartedAt': (visitor, target) => D4.validateTarget<$pkg.ProcessStatus>(target, 'ProcessStatus').lastStartedAt,
      'lastStoppedAt': (visitor, target) => D4.validateTarget<$pkg.ProcessStatus>(target, 'ProcessStatus').lastStoppedAt,
      'restartAttempts': (visitor, target) => D4.validateTarget<$pkg.ProcessStatus>(target, 'ProcessStatus').restartAttempts,
    },
    methods: {
      'toJson': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessStatus>(target, 'ProcessStatus');
        return t.toJson();
      },
    },
  );
}

// =============================================================================
// MonitorStatus Bridge
// =============================================================================

BridgedClass _createMonitorStatusBridge() {
  return BridgedClass(
    nativeType: $pkg.MonitorStatus,
    name: 'MonitorStatus',
    constructors: {
      '': (visitor, positional, named) {
        final instanceId = D4.getRequiredNamedArg<String>(named, 'instanceId', 'MonitorStatus');
        final pid = D4.getRequiredNamedArg<int>(named, 'pid', 'MonitorStatus');
        final startedAt = D4.getRequiredNamedArg<DateTime>(named, 'startedAt', 'MonitorStatus');
        final uptime = D4.getRequiredNamedArg<int>(named, 'uptime', 'MonitorStatus');
        final state = D4.getRequiredNamedArg<String>(named, 'state', 'MonitorStatus');
        final standaloneMode = D4.getRequiredNamedArg<bool>(named, 'standaloneMode', 'MonitorStatus');
        final partnerInstanceId = D4.getOptionalNamedArg<String?>(named, 'partnerInstanceId');
        final partnerStatus = D4.getOptionalNamedArg<String?>(named, 'partnerStatus');
        final partnerPid = D4.getOptionalNamedArg<int?>(named, 'partnerPid');
        final managedProcessCount = D4.getRequiredNamedArg<int>(named, 'managedProcessCount', 'MonitorStatus');
        final runningProcessCount = D4.getRequiredNamedArg<int>(named, 'runningProcessCount', 'MonitorStatus');
        return $pkg.MonitorStatus(instanceId: instanceId, pid: pid, startedAt: startedAt, uptime: uptime, state: state, standaloneMode: standaloneMode, partnerInstanceId: partnerInstanceId, partnerStatus: partnerStatus, partnerPid: partnerPid, managedProcessCount: managedProcessCount, runningProcessCount: runningProcessCount);
      },
      'fromJson': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'MonitorStatus');
        if (positional.length <= 0) {
          throw ArgumentError('MonitorStatus: Missing required argument "json" at position 0');
        }
        final json = D4.coerceMap<String, dynamic>(positional[0], 'json');
        return $pkg.MonitorStatus.fromJson(json);
      },
    },
    getters: {
      'instanceId': (visitor, target) => D4.validateTarget<$pkg.MonitorStatus>(target, 'MonitorStatus').instanceId,
      'pid': (visitor, target) => D4.validateTarget<$pkg.MonitorStatus>(target, 'MonitorStatus').pid,
      'startedAt': (visitor, target) => D4.validateTarget<$pkg.MonitorStatus>(target, 'MonitorStatus').startedAt,
      'uptime': (visitor, target) => D4.validateTarget<$pkg.MonitorStatus>(target, 'MonitorStatus').uptime,
      'state': (visitor, target) => D4.validateTarget<$pkg.MonitorStatus>(target, 'MonitorStatus').state,
      'standaloneMode': (visitor, target) => D4.validateTarget<$pkg.MonitorStatus>(target, 'MonitorStatus').standaloneMode,
      'partnerInstanceId': (visitor, target) => D4.validateTarget<$pkg.MonitorStatus>(target, 'MonitorStatus').partnerInstanceId,
      'partnerStatus': (visitor, target) => D4.validateTarget<$pkg.MonitorStatus>(target, 'MonitorStatus').partnerStatus,
      'partnerPid': (visitor, target) => D4.validateTarget<$pkg.MonitorStatus>(target, 'MonitorStatus').partnerPid,
      'managedProcessCount': (visitor, target) => D4.validateTarget<$pkg.MonitorStatus>(target, 'MonitorStatus').managedProcessCount,
      'runningProcessCount': (visitor, target) => D4.validateTarget<$pkg.MonitorStatus>(target, 'MonitorStatus').runningProcessCount,
    },
    methods: {
      'toJson': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.MonitorStatus>(target, 'MonitorStatus');
        return t.toJson();
      },
    },
  );
}

// =============================================================================
// RestartPolicy Bridge
// =============================================================================

BridgedClass _createRestartPolicyBridge() {
  return BridgedClass(
    nativeType: $pkg.RestartPolicy,
    name: 'RestartPolicy',
    constructors: {
      '': (visitor, positional, named) {
        final maxAttempts = D4.getNamedArgWithDefault<int>(named, 'maxAttempts', 5);
        final backoffIntervalsMs = named.containsKey('backoffIntervalsMs') && named['backoffIntervalsMs'] != null
            ? D4.coerceList<int>(named['backoffIntervalsMs'], 'backoffIntervalsMs')
            : const [1000, 2000, 5000];
        final resetAfterMs = D4.getNamedArgWithDefault<int>(named, 'resetAfterMs', 300000);
        final retryIndefinitely = D4.getNamedArgWithDefault<bool>(named, 'retryIndefinitely', false);
        final indefiniteIntervalMs = D4.getNamedArgWithDefault<int>(named, 'indefiniteIntervalMs', 21600000);
        return $pkg.RestartPolicy(maxAttempts: maxAttempts, backoffIntervalsMs: backoffIntervalsMs, resetAfterMs: resetAfterMs, retryIndefinitely: retryIndefinitely, indefiniteIntervalMs: indefiniteIntervalMs);
      },
      'fromJson': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'RestartPolicy');
        if (positional.length <= 0) {
          throw ArgumentError('RestartPolicy: Missing required argument "json" at position 0');
        }
        final json = D4.coerceMap<String, dynamic>(positional[0], 'json');
        return $pkg.RestartPolicy.fromJson(json);
      },
    },
    getters: {
      'maxAttempts': (visitor, target) => D4.validateTarget<$pkg.RestartPolicy>(target, 'RestartPolicy').maxAttempts,
      'backoffIntervalsMs': (visitor, target) => D4.validateTarget<$pkg.RestartPolicy>(target, 'RestartPolicy').backoffIntervalsMs,
      'resetAfterMs': (visitor, target) => D4.validateTarget<$pkg.RestartPolicy>(target, 'RestartPolicy').resetAfterMs,
      'retryIndefinitely': (visitor, target) => D4.validateTarget<$pkg.RestartPolicy>(target, 'RestartPolicy').retryIndefinitely,
      'indefiniteIntervalMs': (visitor, target) => D4.validateTarget<$pkg.RestartPolicy>(target, 'RestartPolicy').indefiniteIntervalMs,
    },
    methods: {
      'toJson': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RestartPolicy>(target, 'RestartPolicy');
        return t.toJson();
      },
      'copyWith': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RestartPolicy>(target, 'RestartPolicy');
        final maxAttempts = D4.getOptionalNamedArg<int?>(named, 'maxAttempts');
        final backoffIntervalsMs = D4.coerceListOrNull<int>(named['backoffIntervalsMs'], 'backoffIntervalsMs');
        final resetAfterMs = D4.getOptionalNamedArg<int?>(named, 'resetAfterMs');
        final retryIndefinitely = D4.getOptionalNamedArg<bool?>(named, 'retryIndefinitely');
        final indefiniteIntervalMs = D4.getOptionalNamedArg<int?>(named, 'indefiniteIntervalMs');
        return t.copyWith(maxAttempts: maxAttempts, backoffIntervalsMs: backoffIntervalsMs, resetAfterMs: resetAfterMs, retryIndefinitely: retryIndefinitely, indefiniteIntervalMs: indefiniteIntervalMs);
      },
    },
    staticGetters: {
      'defaultPolicy': (visitor) => $pkg.RestartPolicy.defaultPolicy,
    },
  );
}

// =============================================================================
// AlivenessCheck Bridge
// =============================================================================

BridgedClass _createAlivenessCheckBridge() {
  return BridgedClass(
    nativeType: $pkg.AlivenessCheck,
    name: 'AlivenessCheck',
    constructors: {
      '': (visitor, positional, named) {
        final enabled = D4.getRequiredNamedArg<bool>(named, 'enabled', 'AlivenessCheck');
        final url = D4.getRequiredNamedArg<String>(named, 'url', 'AlivenessCheck');
        final statusUrl = D4.getOptionalNamedArg<String?>(named, 'statusUrl');
        final intervalMs = D4.getNamedArgWithDefault<int>(named, 'intervalMs', 3000);
        final timeoutMs = D4.getNamedArgWithDefault<int>(named, 'timeoutMs', 2000);
        final consecutiveFailuresRequired = D4.getNamedArgWithDefault<int>(named, 'consecutiveFailuresRequired', 2);
        final startupCheck = D4.getOptionalNamedArg<$pkg.StartupCheck?>(named, 'startupCheck');
        return $pkg.AlivenessCheck(enabled: enabled, url: url, statusUrl: statusUrl, intervalMs: intervalMs, timeoutMs: timeoutMs, consecutiveFailuresRequired: consecutiveFailuresRequired, startupCheck: startupCheck);
      },
      'fromJson': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'AlivenessCheck');
        if (positional.length <= 0) {
          throw ArgumentError('AlivenessCheck: Missing required argument "json" at position 0');
        }
        final json = D4.coerceMap<String, dynamic>(positional[0], 'json');
        return $pkg.AlivenessCheck.fromJson(json);
      },
    },
    getters: {
      'enabled': (visitor, target) => D4.validateTarget<$pkg.AlivenessCheck>(target, 'AlivenessCheck').enabled,
      'url': (visitor, target) => D4.validateTarget<$pkg.AlivenessCheck>(target, 'AlivenessCheck').url,
      'statusUrl': (visitor, target) => D4.validateTarget<$pkg.AlivenessCheck>(target, 'AlivenessCheck').statusUrl,
      'intervalMs': (visitor, target) => D4.validateTarget<$pkg.AlivenessCheck>(target, 'AlivenessCheck').intervalMs,
      'timeoutMs': (visitor, target) => D4.validateTarget<$pkg.AlivenessCheck>(target, 'AlivenessCheck').timeoutMs,
      'consecutiveFailuresRequired': (visitor, target) => D4.validateTarget<$pkg.AlivenessCheck>(target, 'AlivenessCheck').consecutiveFailuresRequired,
      'startupCheck': (visitor, target) => D4.validateTarget<$pkg.AlivenessCheck>(target, 'AlivenessCheck').startupCheck,
    },
    methods: {
      'toJson': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.AlivenessCheck>(target, 'AlivenessCheck');
        return t.toJson();
      },
      'copyWith': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.AlivenessCheck>(target, 'AlivenessCheck');
        final enabled = D4.getOptionalNamedArg<bool?>(named, 'enabled');
        final url = D4.getOptionalNamedArg<String?>(named, 'url');
        final statusUrl = D4.getOptionalNamedArg<String?>(named, 'statusUrl');
        final intervalMs = D4.getOptionalNamedArg<int?>(named, 'intervalMs');
        final timeoutMs = D4.getOptionalNamedArg<int?>(named, 'timeoutMs');
        final consecutiveFailuresRequired = D4.getOptionalNamedArg<int?>(named, 'consecutiveFailuresRequired');
        final startupCheck = D4.getOptionalNamedArg<$pkg.StartupCheck?>(named, 'startupCheck');
        return t.copyWith(enabled: enabled, url: url, statusUrl: statusUrl, intervalMs: intervalMs, timeoutMs: timeoutMs, consecutiveFailuresRequired: consecutiveFailuresRequired, startupCheck: startupCheck);
      },
    },
  );
}

// =============================================================================
// StartupCheck Bridge
// =============================================================================

BridgedClass _createStartupCheckBridge() {
  return BridgedClass(
    nativeType: $pkg.StartupCheck,
    name: 'StartupCheck',
    constructors: {
      '': (visitor, positional, named) {
        final enabled = D4.getNamedArgWithDefault<bool>(named, 'enabled', true);
        final initialDelayMs = D4.getNamedArgWithDefault<int>(named, 'initialDelayMs', 2000);
        final checkIntervalMs = D4.getNamedArgWithDefault<int>(named, 'checkIntervalMs', 1000);
        final maxAttempts = D4.getNamedArgWithDefault<int>(named, 'maxAttempts', 30);
        final failAction = D4.getNamedArgWithDefault<String>(named, 'failAction', 'restart');
        return $pkg.StartupCheck(enabled: enabled, initialDelayMs: initialDelayMs, checkIntervalMs: checkIntervalMs, maxAttempts: maxAttempts, failAction: failAction);
      },
      'fromJson': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'StartupCheck');
        if (positional.length <= 0) {
          throw ArgumentError('StartupCheck: Missing required argument "json" at position 0');
        }
        final json = D4.coerceMap<String, dynamic>(positional[0], 'json');
        return $pkg.StartupCheck.fromJson(json);
      },
    },
    getters: {
      'enabled': (visitor, target) => D4.validateTarget<$pkg.StartupCheck>(target, 'StartupCheck').enabled,
      'initialDelayMs': (visitor, target) => D4.validateTarget<$pkg.StartupCheck>(target, 'StartupCheck').initialDelayMs,
      'checkIntervalMs': (visitor, target) => D4.validateTarget<$pkg.StartupCheck>(target, 'StartupCheck').checkIntervalMs,
      'maxAttempts': (visitor, target) => D4.validateTarget<$pkg.StartupCheck>(target, 'StartupCheck').maxAttempts,
      'failAction': (visitor, target) => D4.validateTarget<$pkg.StartupCheck>(target, 'StartupCheck').failAction,
    },
    methods: {
      'toJson': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.StartupCheck>(target, 'StartupCheck');
        return t.toJson();
      },
      'copyWith': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.StartupCheck>(target, 'StartupCheck');
        final enabled = D4.getOptionalNamedArg<bool?>(named, 'enabled');
        final initialDelayMs = D4.getOptionalNamedArg<int?>(named, 'initialDelayMs');
        final checkIntervalMs = D4.getOptionalNamedArg<int?>(named, 'checkIntervalMs');
        final maxAttempts = D4.getOptionalNamedArg<int?>(named, 'maxAttempts');
        final failAction = D4.getOptionalNamedArg<String?>(named, 'failAction');
        return t.copyWith(enabled: enabled, initialDelayMs: initialDelayMs, checkIntervalMs: checkIntervalMs, maxAttempts: maxAttempts, failAction: failAction);
      },
    },
  );
}

// =============================================================================
// RemoteAccessConfig Bridge
// =============================================================================

BridgedClass _createRemoteAccessConfigBridge() {
  return BridgedClass(
    nativeType: $pkg.RemoteAccessConfig,
    name: 'RemoteAccessConfig',
    constructors: {
      '': (visitor, positional, named) {
        final startRemoteAccess = D4.getNamedArgWithDefault<bool>(named, 'startRemoteAccess', false);
        final remotePort = D4.getNamedArgWithDefault<int>(named, 'remotePort', 19881);
        final trustedHosts = named.containsKey('trustedHosts') && named['trustedHosts'] != null
            ? D4.coerceList<String>(named['trustedHosts'], 'trustedHosts')
            : const ['localhost', '127.0.0.1', '::1'];
        final allowRemoteRegister = D4.getNamedArgWithDefault<bool>(named, 'allowRemoteRegister', true);
        final allowRemoteDeregister = D4.getNamedArgWithDefault<bool>(named, 'allowRemoteDeregister', true);
        final allowRemoteStart = D4.getNamedArgWithDefault<bool>(named, 'allowRemoteStart', true);
        final allowRemoteStop = D4.getNamedArgWithDefault<bool>(named, 'allowRemoteStop', true);
        final allowRemoteDisable = D4.getNamedArgWithDefault<bool>(named, 'allowRemoteDisable', true);
        final allowRemoteAutostart = D4.getNamedArgWithDefault<bool>(named, 'allowRemoteAutostart', true);
        final allowRemoteMonitorRestart = D4.getNamedArgWithDefault<bool>(named, 'allowRemoteMonitorRestart', false);
        final executableWhitelist = named.containsKey('executableWhitelist') && named['executableWhitelist'] != null
            ? D4.coerceList<String>(named['executableWhitelist'], 'executableWhitelist')
            : const <String>[];
        final executableBlacklist = named.containsKey('executableBlacklist') && named['executableBlacklist'] != null
            ? D4.coerceList<String>(named['executableBlacklist'], 'executableBlacklist')
            : const <String>[];
        return $pkg.RemoteAccessConfig(startRemoteAccess: startRemoteAccess, remotePort: remotePort, trustedHosts: trustedHosts, allowRemoteRegister: allowRemoteRegister, allowRemoteDeregister: allowRemoteDeregister, allowRemoteStart: allowRemoteStart, allowRemoteStop: allowRemoteStop, allowRemoteDisable: allowRemoteDisable, allowRemoteAutostart: allowRemoteAutostart, allowRemoteMonitorRestart: allowRemoteMonitorRestart, executableWhitelist: executableWhitelist, executableBlacklist: executableBlacklist);
      },
      'fromJson': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'RemoteAccessConfig');
        if (positional.length <= 0) {
          throw ArgumentError('RemoteAccessConfig: Missing required argument "json" at position 0');
        }
        final json = D4.coerceMap<String, dynamic>(positional[0], 'json');
        return $pkg.RemoteAccessConfig.fromJson(json);
      },
    },
    getters: {
      'startRemoteAccess': (visitor, target) => D4.validateTarget<$pkg.RemoteAccessConfig>(target, 'RemoteAccessConfig').startRemoteAccess,
      'remotePort': (visitor, target) => D4.validateTarget<$pkg.RemoteAccessConfig>(target, 'RemoteAccessConfig').remotePort,
      'trustedHosts': (visitor, target) => D4.validateTarget<$pkg.RemoteAccessConfig>(target, 'RemoteAccessConfig').trustedHosts,
      'allowRemoteRegister': (visitor, target) => D4.validateTarget<$pkg.RemoteAccessConfig>(target, 'RemoteAccessConfig').allowRemoteRegister,
      'allowRemoteDeregister': (visitor, target) => D4.validateTarget<$pkg.RemoteAccessConfig>(target, 'RemoteAccessConfig').allowRemoteDeregister,
      'allowRemoteStart': (visitor, target) => D4.validateTarget<$pkg.RemoteAccessConfig>(target, 'RemoteAccessConfig').allowRemoteStart,
      'allowRemoteStop': (visitor, target) => D4.validateTarget<$pkg.RemoteAccessConfig>(target, 'RemoteAccessConfig').allowRemoteStop,
      'allowRemoteDisable': (visitor, target) => D4.validateTarget<$pkg.RemoteAccessConfig>(target, 'RemoteAccessConfig').allowRemoteDisable,
      'allowRemoteAutostart': (visitor, target) => D4.validateTarget<$pkg.RemoteAccessConfig>(target, 'RemoteAccessConfig').allowRemoteAutostart,
      'allowRemoteMonitorRestart': (visitor, target) => D4.validateTarget<$pkg.RemoteAccessConfig>(target, 'RemoteAccessConfig').allowRemoteMonitorRestart,
      'executableWhitelist': (visitor, target) => D4.validateTarget<$pkg.RemoteAccessConfig>(target, 'RemoteAccessConfig').executableWhitelist,
      'executableBlacklist': (visitor, target) => D4.validateTarget<$pkg.RemoteAccessConfig>(target, 'RemoteAccessConfig').executableBlacklist,
    },
    methods: {
      'toJson': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteAccessConfig>(target, 'RemoteAccessConfig');
        return t.toJson();
      },
      'copyWith': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteAccessConfig>(target, 'RemoteAccessConfig');
        final startRemoteAccess = D4.getOptionalNamedArg<bool?>(named, 'startRemoteAccess');
        final remotePort = D4.getOptionalNamedArg<int?>(named, 'remotePort');
        final trustedHosts = D4.coerceListOrNull<String>(named['trustedHosts'], 'trustedHosts');
        final allowRemoteRegister = D4.getOptionalNamedArg<bool?>(named, 'allowRemoteRegister');
        final allowRemoteDeregister = D4.getOptionalNamedArg<bool?>(named, 'allowRemoteDeregister');
        final allowRemoteStart = D4.getOptionalNamedArg<bool?>(named, 'allowRemoteStart');
        final allowRemoteStop = D4.getOptionalNamedArg<bool?>(named, 'allowRemoteStop');
        final allowRemoteDisable = D4.getOptionalNamedArg<bool?>(named, 'allowRemoteDisable');
        final allowRemoteAutostart = D4.getOptionalNamedArg<bool?>(named, 'allowRemoteAutostart');
        final allowRemoteMonitorRestart = D4.getOptionalNamedArg<bool?>(named, 'allowRemoteMonitorRestart');
        final executableWhitelist = D4.coerceListOrNull<String>(named['executableWhitelist'], 'executableWhitelist');
        final executableBlacklist = D4.coerceListOrNull<String>(named['executableBlacklist'], 'executableBlacklist');
        return t.copyWith(startRemoteAccess: startRemoteAccess, remotePort: remotePort, trustedHosts: trustedHosts, allowRemoteRegister: allowRemoteRegister, allowRemoteDeregister: allowRemoteDeregister, allowRemoteStart: allowRemoteStart, allowRemoteStop: allowRemoteStop, allowRemoteDisable: allowRemoteDisable, allowRemoteAutostart: allowRemoteAutostart, allowRemoteMonitorRestart: allowRemoteMonitorRestart, executableWhitelist: executableWhitelist, executableBlacklist: executableBlacklist);
      },
    },
    staticGetters: {
      'defaultConfig': (visitor) => $pkg.RemoteAccessConfig.defaultConfig,
    },
  );
}

// =============================================================================
// PartnerDiscoveryConfig Bridge
// =============================================================================

BridgedClass _createPartnerDiscoveryConfigBridge() {
  return BridgedClass(
    nativeType: $pkg.PartnerDiscoveryConfig,
    name: 'PartnerDiscoveryConfig',
    constructors: {
      '': (visitor, positional, named) {
        final partnerInstanceId = D4.getOptionalNamedArg<String?>(named, 'partnerInstanceId');
        final partnerAlivenessPort = D4.getOptionalNamedArg<int?>(named, 'partnerAlivenessPort');
        final partnerStatusUrl = D4.getOptionalNamedArg<String?>(named, 'partnerStatusUrl');
        final discoveryOnStartup = D4.getNamedArgWithDefault<bool>(named, 'discoveryOnStartup', true);
        return $pkg.PartnerDiscoveryConfig(partnerInstanceId: partnerInstanceId, partnerAlivenessPort: partnerAlivenessPort, partnerStatusUrl: partnerStatusUrl, discoveryOnStartup: discoveryOnStartup);
      },
      'fromJson': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'PartnerDiscoveryConfig');
        if (positional.length <= 0) {
          throw ArgumentError('PartnerDiscoveryConfig: Missing required argument "json" at position 0');
        }
        final json = D4.coerceMap<String, dynamic>(positional[0], 'json');
        return $pkg.PartnerDiscoveryConfig.fromJson(json);
      },
    },
    getters: {
      'partnerInstanceId': (visitor, target) => D4.validateTarget<$pkg.PartnerDiscoveryConfig>(target, 'PartnerDiscoveryConfig').partnerInstanceId,
      'partnerAlivenessPort': (visitor, target) => D4.validateTarget<$pkg.PartnerDiscoveryConfig>(target, 'PartnerDiscoveryConfig').partnerAlivenessPort,
      'partnerStatusUrl': (visitor, target) => D4.validateTarget<$pkg.PartnerDiscoveryConfig>(target, 'PartnerDiscoveryConfig').partnerStatusUrl,
      'discoveryOnStartup': (visitor, target) => D4.validateTarget<$pkg.PartnerDiscoveryConfig>(target, 'PartnerDiscoveryConfig').discoveryOnStartup,
    },
    methods: {
      'toJson': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.PartnerDiscoveryConfig>(target, 'PartnerDiscoveryConfig');
        return t.toJson();
      },
      'copyWith': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.PartnerDiscoveryConfig>(target, 'PartnerDiscoveryConfig');
        final partnerInstanceId = D4.getOptionalNamedArg<String?>(named, 'partnerInstanceId');
        final partnerAlivenessPort = D4.getOptionalNamedArg<int?>(named, 'partnerAlivenessPort');
        final partnerStatusUrl = D4.getOptionalNamedArg<String?>(named, 'partnerStatusUrl');
        final discoveryOnStartup = D4.getOptionalNamedArg<bool?>(named, 'discoveryOnStartup');
        return t.copyWith(partnerInstanceId: partnerInstanceId, partnerAlivenessPort: partnerAlivenessPort, partnerStatusUrl: partnerStatusUrl, discoveryOnStartup: discoveryOnStartup);
      },
    },
    staticMethods: {
      'defaultForInstance': (visitor, positional, named, typeArgs) {
        D4.requireMinArgs(positional, 1, 'defaultForInstance');
        final instanceId = D4.getRequiredArg<String>(positional, 0, 'instanceId', 'defaultForInstance');
        return $pkg.PartnerDiscoveryConfig.defaultForInstance(instanceId);
      },
    },
  );
}

// =============================================================================
// AlivenessServerConfig Bridge
// =============================================================================

BridgedClass _createAlivenessServerConfigBridge() {
  return BridgedClass(
    nativeType: $pkg.AlivenessServerConfig,
    name: 'AlivenessServerConfig',
    constructors: {
      '': (visitor, positional, named) {
        final enabled = D4.getNamedArgWithDefault<bool>(named, 'enabled', true);
        final port = D4.getNamedArgWithDefault<int>(named, 'port', 19883);
        return $pkg.AlivenessServerConfig(enabled: enabled, port: port);
      },
      'fromJson': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'AlivenessServerConfig');
        if (positional.length <= 0) {
          throw ArgumentError('AlivenessServerConfig: Missing required argument "json" at position 0');
        }
        final json = D4.coerceMap<String, dynamic>(positional[0], 'json');
        return $pkg.AlivenessServerConfig.fromJson(json);
      },
    },
    getters: {
      'enabled': (visitor, target) => D4.validateTarget<$pkg.AlivenessServerConfig>(target, 'AlivenessServerConfig').enabled,
      'port': (visitor, target) => D4.validateTarget<$pkg.AlivenessServerConfig>(target, 'AlivenessServerConfig').port,
    },
    methods: {
      'toJson': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.AlivenessServerConfig>(target, 'AlivenessServerConfig');
        return t.toJson();
      },
    },
  );
}

// =============================================================================
// WatcherInfo Bridge
// =============================================================================

BridgedClass _createWatcherInfoBridge() {
  return BridgedClass(
    nativeType: $pkg.WatcherInfo,
    name: 'WatcherInfo',
    constructors: {
      '': (visitor, positional, named) {
        final watcherPid = D4.getRequiredNamedArg<int>(named, 'watcherPid', 'WatcherInfo');
        final watcherInstanceId = D4.getRequiredNamedArg<String>(named, 'watcherInstanceId', 'WatcherInfo');
        final watcherAlivenessPort = D4.getRequiredNamedArg<int>(named, 'watcherAlivenessPort', 'WatcherInfo');
        return $pkg.WatcherInfo(watcherPid: watcherPid, watcherInstanceId: watcherInstanceId, watcherAlivenessPort: watcherAlivenessPort);
      },
      'fromJson': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'WatcherInfo');
        if (positional.length <= 0) {
          throw ArgumentError('WatcherInfo: Missing required argument "json" at position 0');
        }
        final json = D4.coerceMap<String, dynamic>(positional[0], 'json');
        return $pkg.WatcherInfo.fromJson(json);
      },
    },
    getters: {
      'watcherPid': (visitor, target) => D4.validateTarget<$pkg.WatcherInfo>(target, 'WatcherInfo').watcherPid,
      'watcherInstanceId': (visitor, target) => D4.validateTarget<$pkg.WatcherInfo>(target, 'WatcherInfo').watcherInstanceId,
      'watcherAlivenessPort': (visitor, target) => D4.validateTarget<$pkg.WatcherInfo>(target, 'WatcherInfo').watcherAlivenessPort,
    },
    methods: {
      'toJson': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.WatcherInfo>(target, 'WatcherInfo');
        return t.toJson();
      },
    },
  );
}

// =============================================================================
// ProcessRegistry Bridge
// =============================================================================

BridgedClass _createProcessRegistryBridge() {
  return BridgedClass(
    nativeType: $pkg.ProcessRegistry,
    name: 'ProcessRegistry',
    constructors: {
      '': (visitor, positional, named) {
        final version = D4.getNamedArgWithDefault<int>(named, 'version', 1);
        final lastModified = D4.getOptionalNamedArg<DateTime?>(named, 'lastModified');
        final instanceId = D4.getRequiredNamedArg<String>(named, 'instanceId', 'ProcessRegistry');
        final monitorIntervalMs = D4.getNamedArgWithDefault<int>(named, 'monitorIntervalMs', 5000);
        final standaloneMode = D4.getNamedArgWithDefault<bool>(named, 'standaloneMode', false);
        final partnerDiscovery = D4.getOptionalNamedArg<$pkg.PartnerDiscoveryConfig?>(named, 'partnerDiscovery');
        final remoteAccess = D4.getOptionalNamedArg<$pkg.RemoteAccessConfig?>(named, 'remoteAccess');
        final alivenessServer = D4.getOptionalNamedArg<$pkg.AlivenessServerConfig?>(named, 'alivenessServer');
        final watcherInfo = D4.getOptionalNamedArg<$pkg.WatcherInfo?>(named, 'watcherInfo');
        final processes = D4.coerceMapOrNull<String, $pkg.ProcessEntry>(named['processes'], 'processes');
        return $pkg.ProcessRegistry(version: version, lastModified: lastModified, instanceId: instanceId, monitorIntervalMs: monitorIntervalMs, standaloneMode: standaloneMode, partnerDiscovery: partnerDiscovery, remoteAccess: remoteAccess, alivenessServer: alivenessServer, watcherInfo: watcherInfo, processes: processes);
      },
      'fromJson': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'ProcessRegistry');
        if (positional.length <= 0) {
          throw ArgumentError('ProcessRegistry: Missing required argument "json" at position 0');
        }
        final json = D4.coerceMap<String, dynamic>(positional[0], 'json');
        return $pkg.ProcessRegistry.fromJson(json);
      },
    },
    getters: {
      'version': (visitor, target) => D4.validateTarget<$pkg.ProcessRegistry>(target, 'ProcessRegistry').version,
      'lastModified': (visitor, target) => D4.validateTarget<$pkg.ProcessRegistry>(target, 'ProcessRegistry').lastModified,
      'instanceId': (visitor, target) => D4.validateTarget<$pkg.ProcessRegistry>(target, 'ProcessRegistry').instanceId,
      'monitorIntervalMs': (visitor, target) => D4.validateTarget<$pkg.ProcessRegistry>(target, 'ProcessRegistry').monitorIntervalMs,
      'standaloneMode': (visitor, target) => D4.validateTarget<$pkg.ProcessRegistry>(target, 'ProcessRegistry').standaloneMode,
      'partnerDiscovery': (visitor, target) => D4.validateTarget<$pkg.ProcessRegistry>(target, 'ProcessRegistry').partnerDiscovery,
      'remoteAccess': (visitor, target) => D4.validateTarget<$pkg.ProcessRegistry>(target, 'ProcessRegistry').remoteAccess,
      'alivenessServer': (visitor, target) => D4.validateTarget<$pkg.ProcessRegistry>(target, 'ProcessRegistry').alivenessServer,
      'watcherInfo': (visitor, target) => D4.validateTarget<$pkg.ProcessRegistry>(target, 'ProcessRegistry').watcherInfo,
      'processes': (visitor, target) => D4.validateTarget<$pkg.ProcessRegistry>(target, 'ProcessRegistry').processes,
    },
    setters: {
      'version': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessRegistry>(target, 'ProcessRegistry').version = value as int,
      'lastModified': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessRegistry>(target, 'ProcessRegistry').lastModified = value as DateTime,
      'instanceId': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessRegistry>(target, 'ProcessRegistry').instanceId = value as String,
      'monitorIntervalMs': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessRegistry>(target, 'ProcessRegistry').monitorIntervalMs = value as int,
      'standaloneMode': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessRegistry>(target, 'ProcessRegistry').standaloneMode = value as bool,
      'partnerDiscovery': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessRegistry>(target, 'ProcessRegistry').partnerDiscovery = value as $pkg.PartnerDiscoveryConfig,
      'remoteAccess': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessRegistry>(target, 'ProcessRegistry').remoteAccess = value as $pkg.RemoteAccessConfig,
      'alivenessServer': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessRegistry>(target, 'ProcessRegistry').alivenessServer = value as $pkg.AlivenessServerConfig,
      'watcherInfo': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessRegistry>(target, 'ProcessRegistry').watcherInfo = value as $pkg.WatcherInfo?,
      'processes': (visitor, target, value) => 
        D4.validateTarget<$pkg.ProcessRegistry>(target, 'ProcessRegistry').processes = value as Map<String, $pkg.ProcessEntry>,
    },
    methods: {
      'toJson': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessRegistry>(target, 'ProcessRegistry');
        return t.toJson();
      },
    },
  );
}

// =============================================================================
// ProcessMonitorException Bridge
// =============================================================================

BridgedClass _createProcessMonitorExceptionBridge() {
  return BridgedClass(
    nativeType: $pkg.ProcessMonitorException,
    name: 'ProcessMonitorException',
    constructors: {
      '': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'ProcessMonitorException');
        final message = D4.getRequiredArg<String>(positional, 0, 'message', 'ProcessMonitorException');
        return $pkg.ProcessMonitorException(message);
      },
    },
    getters: {
      'message': (visitor, target) => D4.validateTarget<$pkg.ProcessMonitorException>(target, 'ProcessMonitorException').message,
    },
    methods: {
      'toString': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorException>(target, 'ProcessMonitorException');
        return t.toString();
      },
    },
  );
}

// =============================================================================
// LockTimeoutException Bridge
// =============================================================================

BridgedClass _createLockTimeoutExceptionBridge() {
  return BridgedClass(
    nativeType: $pkg.LockTimeoutException,
    name: 'LockTimeoutException',
    constructors: {
      '': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'LockTimeoutException');
        final message = D4.getRequiredArg<String>(positional, 0, 'message', 'LockTimeoutException');
        return $pkg.LockTimeoutException(message);
      },
    },
    getters: {
      'message': (visitor, target) => D4.validateTarget<$pkg.LockTimeoutException>(target, 'LockTimeoutException').message,
    },
    methods: {
      'toString': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LockTimeoutException>(target, 'LockTimeoutException');
        return t.toString();
      },
    },
  );
}

// =============================================================================
// ProcessNotFoundException Bridge
// =============================================================================

BridgedClass _createProcessNotFoundExceptionBridge() {
  return BridgedClass(
    nativeType: $pkg.ProcessNotFoundException,
    name: 'ProcessNotFoundException',
    constructors: {
      '': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'ProcessNotFoundException');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'ProcessNotFoundException');
        return $pkg.ProcessNotFoundException(processId);
      },
    },
    getters: {
      'message': (visitor, target) => D4.validateTarget<$pkg.ProcessNotFoundException>(target, 'ProcessNotFoundException').message,
      'processId': (visitor, target) => D4.validateTarget<$pkg.ProcessNotFoundException>(target, 'ProcessNotFoundException').processId,
    },
    methods: {
      'toString': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessNotFoundException>(target, 'ProcessNotFoundException');
        return t.toString();
      },
    },
  );
}

// =============================================================================
// ProcessDisabledException Bridge
// =============================================================================

BridgedClass _createProcessDisabledExceptionBridge() {
  return BridgedClass(
    nativeType: $pkg.ProcessDisabledException,
    name: 'ProcessDisabledException',
    constructors: {
      '': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'ProcessDisabledException');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'ProcessDisabledException');
        return $pkg.ProcessDisabledException(processId);
      },
    },
    getters: {
      'message': (visitor, target) => D4.validateTarget<$pkg.ProcessDisabledException>(target, 'ProcessDisabledException').message,
      'processId': (visitor, target) => D4.validateTarget<$pkg.ProcessDisabledException>(target, 'ProcessDisabledException').processId,
    },
    methods: {
      'toString': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessDisabledException>(target, 'ProcessDisabledException');
        return t.toString();
      },
    },
  );
}

// =============================================================================
// PermissionDeniedException Bridge
// =============================================================================

BridgedClass _createPermissionDeniedExceptionBridge() {
  return BridgedClass(
    nativeType: $pkg.PermissionDeniedException,
    name: 'PermissionDeniedException',
    constructors: {
      '': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'PermissionDeniedException');
        final operation = D4.getRequiredArg<String>(positional, 0, 'operation', 'PermissionDeniedException');
        return $pkg.PermissionDeniedException(operation);
      },
    },
    getters: {
      'message': (visitor, target) => D4.validateTarget<$pkg.PermissionDeniedException>(target, 'PermissionDeniedException').message,
      'operation': (visitor, target) => D4.validateTarget<$pkg.PermissionDeniedException>(target, 'PermissionDeniedException').operation,
    },
    methods: {
      'toString': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.PermissionDeniedException>(target, 'PermissionDeniedException');
        return t.toString();
      },
    },
  );
}

// =============================================================================
// LockInfo Bridge
// =============================================================================

BridgedClass _createLockInfoBridge() {
  return BridgedClass(
    nativeType: $pkg.LockInfo,
    name: 'LockInfo',
    constructors: {
      '': (visitor, positional, named) {
        final lockedBy = D4.getRequiredNamedArg<String>(named, 'lockedBy', 'LockInfo');
        final lockedAt = D4.getRequiredNamedArg<DateTime>(named, 'lockedAt', 'LockInfo');
        final pid = D4.getRequiredNamedArg<int>(named, 'pid', 'LockInfo');
        final operation = D4.getRequiredNamedArg<String>(named, 'operation', 'LockInfo');
        return $pkg.LockInfo(lockedBy: lockedBy, lockedAt: lockedAt, pid: pid, operation: operation);
      },
      'fromJson': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'LockInfo');
        if (positional.length <= 0) {
          throw ArgumentError('LockInfo: Missing required argument "json" at position 0');
        }
        final json = D4.coerceMap<String, dynamic>(positional[0], 'json');
        return $pkg.LockInfo.fromJson(json);
      },
    },
    getters: {
      'lockedBy': (visitor, target) => D4.validateTarget<$pkg.LockInfo>(target, 'LockInfo').lockedBy,
      'lockedAt': (visitor, target) => D4.validateTarget<$pkg.LockInfo>(target, 'LockInfo').lockedAt,
      'pid': (visitor, target) => D4.validateTarget<$pkg.LockInfo>(target, 'LockInfo').pid,
      'operation': (visitor, target) => D4.validateTarget<$pkg.LockInfo>(target, 'LockInfo').operation,
    },
    methods: {
      'toJson': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LockInfo>(target, 'LockInfo');
        return t.toJson();
      },
    },
  );
}

// =============================================================================
// RegistryLock Bridge
// =============================================================================

BridgedClass _createRegistryLockBridge() {
  return BridgedClass(
    nativeType: $pkg.RegistryLock,
    name: 'RegistryLock',
    constructors: {
      '': (visitor, positional, named) {
        final lockPath = D4.getRequiredNamedArg<String>(named, 'lockPath', 'RegistryLock');
        final instanceId = D4.getRequiredNamedArg<String>(named, 'instanceId', 'RegistryLock');
        final timeout = D4.getNamedArgWithDefault<Duration>(named, 'timeout', const Duration(milliseconds: 5000));
        return $pkg.RegistryLock(lockPath: lockPath, instanceId: instanceId, timeout: timeout);
      },
    },
    getters: {
      'lockPath': (visitor, target) => D4.validateTarget<$pkg.RegistryLock>(target, 'RegistryLock').lockPath,
      'instanceId': (visitor, target) => D4.validateTarget<$pkg.RegistryLock>(target, 'RegistryLock').instanceId,
      'timeout': (visitor, target) => D4.validateTarget<$pkg.RegistryLock>(target, 'RegistryLock').timeout,
    },
    methods: {
      'withLock': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RegistryLock>(target, 'RegistryLock');
        D4.requireMinArgs(positional, 1, 'withLock');
        if (positional.length <= 0) {
          throw ArgumentError('withLock: Missing required argument "operation" at position 0');
        }
        final operation_raw = positional[0];
        return t.withLock(() { return (operation_raw as InterpretedFunction).call(visitor as InterpreterVisitor, []) as Future<dynamic>; });
      },
    },
  );
}

// =============================================================================
// RegistryService Bridge
// =============================================================================

BridgedClass _createRegistryServiceBridge() {
  return BridgedClass(
    nativeType: $pkg.RegistryService,
    name: 'RegistryService',
    constructors: {
      '': (visitor, positional, named) {
        final directory = D4.getRequiredNamedArg<String>(named, 'directory', 'RegistryService');
        final instanceId = D4.getRequiredNamedArg<String>(named, 'instanceId', 'RegistryService');
        return $pkg.RegistryService(directory: directory, instanceId: instanceId);
      },
    },
    getters: {
      'directory': (visitor, target) => D4.validateTarget<$pkg.RegistryService>(target, 'RegistryService').directory,
      'instanceId': (visitor, target) => D4.validateTarget<$pkg.RegistryService>(target, 'RegistryService').instanceId,
      'registryPath': (visitor, target) => D4.validateTarget<$pkg.RegistryService>(target, 'RegistryService').registryPath,
    },
    methods: {
      'load': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RegistryService>(target, 'RegistryService');
        return t.load();
      },
      'save': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RegistryService>(target, 'RegistryService');
        D4.requireMinArgs(positional, 1, 'save');
        final registry = D4.getRequiredArg<$pkg.ProcessRegistry>(positional, 0, 'registry', 'save');
        return t.save(registry);
      },
      'withLock': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RegistryService>(target, 'RegistryService');
        D4.requireMinArgs(positional, 1, 'withLock');
        if (positional.length <= 0) {
          throw ArgumentError('withLock: Missing required argument "operation" at position 0');
        }
        final operation_raw = positional[0];
        return t.withLock(($pkg.ProcessRegistry p0) { return (operation_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]) as Future<dynamic>; });
      },
      'withLockReadOnly': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RegistryService>(target, 'RegistryService');
        D4.requireMinArgs(positional, 1, 'withLockReadOnly');
        if (positional.length <= 0) {
          throw ArgumentError('withLockReadOnly: Missing required argument "operation" at position 0');
        }
        final operation_raw = positional[0];
        return t.withLockReadOnly(($pkg.ProcessRegistry p0) { return (operation_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]) as Future<dynamic>; });
      },
      'initialize': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RegistryService>(target, 'RegistryService');
        return t.initialize();
      },
      'exists': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RegistryService>(target, 'RegistryService');
        return t.exists();
      },
    },
  );
}

// =============================================================================
// ProcessControl Bridge
// =============================================================================

BridgedClass _createProcessControlBridge() {
  return BridgedClass(
    nativeType: $pkg.ProcessControl,
    name: 'ProcessControl',
    constructors: {
      '': (visitor, positional, named) {
        final logDirectory = D4.getRequiredNamedArg<String>(named, 'logDirectory', 'ProcessControl');
        final instanceId = D4.getRequiredNamedArg<String>(named, 'instanceId', 'ProcessControl');
        final logger_raw = named['logger'];
        return $pkg.ProcessControl(logDirectory: logDirectory, instanceId: instanceId, logger: logger_raw == null ? null : (String p0) { (logger_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]); });
      },
    },
    getters: {
      'logDirectory': (visitor, target) => D4.validateTarget<$pkg.ProcessControl>(target, 'ProcessControl').logDirectory,
      'instanceId': (visitor, target) => D4.validateTarget<$pkg.ProcessControl>(target, 'ProcessControl').instanceId,
      'logger': (visitor, target) => D4.validateTarget<$pkg.ProcessControl>(target, 'ProcessControl').logger,
    },
    methods: {
      'isProcessAlive': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessControl>(target, 'ProcessControl');
        D4.requireMinArgs(positional, 1, 'isProcessAlive');
        final pid = D4.getRequiredArg<int>(positional, 0, 'pid', 'isProcessAlive');
        return t.isProcessAlive(pid);
      },
      'startProcess': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessControl>(target, 'ProcessControl');
        D4.requireMinArgs(positional, 1, 'startProcess');
        final process = D4.getRequiredArg<$pkg.ProcessEntry>(positional, 0, 'process', 'startProcess');
        return t.startProcess(process);
      },
      'stopProcess': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessControl>(target, 'ProcessControl');
        D4.requireMinArgs(positional, 1, 'stopProcess');
        final pid = D4.getRequiredArg<int>(positional, 0, 'pid', 'stopProcess');
        final force = D4.getNamedArgWithDefault<bool>(named, 'force', false);
        return t.stopProcess(pid, force: force);
      },
      'stopProcessGracefully': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessControl>(target, 'ProcessControl');
        D4.requireMinArgs(positional, 1, 'stopProcessGracefully');
        final pid = D4.getRequiredArg<int>(positional, 0, 'pid', 'stopProcessGracefully');
        final timeout = D4.getNamedArgWithDefault<Duration>(named, 'timeout', const Duration(seconds: 10));
        return t.stopProcessGracefully(pid, timeout: timeout);
      },
    },
  );
}

// =============================================================================
// AlivenessChecker Bridge
// =============================================================================

BridgedClass _createAlivenessCheckerBridge() {
  return BridgedClass(
    nativeType: $pkg.AlivenessChecker,
    name: 'AlivenessChecker',
    constructors: {
      '': (visitor, positional, named) {
        final logger_raw = named['logger'];
        return $pkg.AlivenessChecker(logger: logger_raw == null ? null : (String p0) { (logger_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]); });
      },
    },
    getters: {
      'logger': (visitor, target) => D4.validateTarget<$pkg.AlivenessChecker>(target, 'AlivenessChecker').logger,
    },
    methods: {
      'dispose': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.AlivenessChecker>(target, 'AlivenessChecker');
        t.dispose();
        return null;
      },
      'checkAlive': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.AlivenessChecker>(target, 'AlivenessChecker');
        D4.requireMinArgs(positional, 1, 'checkAlive');
        final url = D4.getRequiredArg<String>(positional, 0, 'url', 'checkAlive');
        final timeout = D4.getOptionalNamedArg<Duration?>(named, 'timeout');
        return t.checkAlive(url, timeout: timeout);
      },
      'fetchPid': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.AlivenessChecker>(target, 'AlivenessChecker');
        D4.requireMinArgs(positional, 1, 'fetchPid');
        final url = D4.getRequiredArg<String>(positional, 0, 'url', 'fetchPid');
        final timeout = D4.getOptionalNamedArg<Duration?>(named, 'timeout');
        return t.fetchPid(url, timeout: timeout);
      },
      'fetchStatus': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.AlivenessChecker>(target, 'AlivenessChecker');
        D4.requireMinArgs(positional, 1, 'fetchStatus');
        final url = D4.getRequiredArg<String>(positional, 0, 'url', 'fetchStatus');
        final timeout = D4.getOptionalNamedArg<Duration?>(named, 'timeout');
        return t.fetchStatus(url, timeout: timeout);
      },
    },
  );
}

// =============================================================================
// AlivenessCallback Bridge
// =============================================================================

BridgedClass _createAlivenessCallbackBridge() {
  return BridgedClass(
    nativeType: $pkg.AlivenessCallback,
    name: 'AlivenessCallback',
    constructors: {
      '': (visitor, positional, named) {
        final onHealthCheck_raw = named['onHealthCheck'];
        final onStatusRequest_raw = named['onStatusRequest'];
        return $pkg.AlivenessCallback(onHealthCheck: onHealthCheck_raw == null ? null : () { return (onHealthCheck_raw as InterpretedFunction).call(visitor as InterpreterVisitor, []) as Future<bool>; }, onStatusRequest: onStatusRequest_raw == null ? null : () { return (onStatusRequest_raw as InterpretedFunction).call(visitor as InterpreterVisitor, []) as Future<Map<String, dynamic>>; });
      },
    },
    getters: {
      'onHealthCheck': (visitor, target) => D4.validateTarget<$pkg.AlivenessCallback>(target, 'AlivenessCallback').onHealthCheck,
      'onStatusRequest': (visitor, target) => D4.validateTarget<$pkg.AlivenessCallback>(target, 'AlivenessCallback').onStatusRequest,
    },
  );
}

// =============================================================================
// LogManager Bridge
// =============================================================================

BridgedClass _createLogManagerBridge() {
  return BridgedClass(
    nativeType: $pkg.LogManager,
    name: 'LogManager',
    constructors: {
      '': (visitor, positional, named) {
        final baseDirectory = D4.getRequiredNamedArg<String>(named, 'baseDirectory', 'LogManager');
        final instanceId = D4.getRequiredNamedArg<String>(named, 'instanceId', 'LogManager');
        final maxLogFiles = D4.getNamedArgWithDefault<int>(named, 'maxLogFiles', 10);
        return $pkg.LogManager(baseDirectory: baseDirectory, instanceId: instanceId, maxLogFiles: maxLogFiles);
      },
    },
    getters: {
      'baseDirectory': (visitor, target) => D4.validateTarget<$pkg.LogManager>(target, 'LogManager').baseDirectory,
      'instanceId': (visitor, target) => D4.validateTarget<$pkg.LogManager>(target, 'LogManager').instanceId,
      'maxLogFiles': (visitor, target) => D4.validateTarget<$pkg.LogManager>(target, 'LogManager').maxLogFiles,
    },
    methods: {
      'initialize': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LogManager>(target, 'LogManager');
        return t.initialize();
      },
      'log': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LogManager>(target, 'LogManager');
        D4.requireMinArgs(positional, 1, 'log');
        final message = D4.getRequiredArg<String>(positional, 0, 'message', 'log');
        final level = D4.getNamedArgWithDefault<String>(named, 'level', 'INFO');
        t.log(message, level: level);
        return null;
      },
      'info': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LogManager>(target, 'LogManager');
        D4.requireMinArgs(positional, 1, 'info');
        final message = D4.getRequiredArg<String>(positional, 0, 'message', 'info');
        t.info(message);
        return null;
      },
      'warn': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LogManager>(target, 'LogManager');
        D4.requireMinArgs(positional, 1, 'warn');
        final message = D4.getRequiredArg<String>(positional, 0, 'message', 'warn');
        t.warn(message);
        return null;
      },
      'error': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LogManager>(target, 'LogManager');
        D4.requireMinArgs(positional, 1, 'error');
        final message = D4.getRequiredArg<String>(positional, 0, 'message', 'error');
        t.error(message);
        return null;
      },
      'close': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LogManager>(target, 'LogManager');
        return t.close();
      },
      'getProcessLogDir': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LogManager>(target, 'LogManager');
        D4.requireMinArgs(positional, 1, 'getProcessLogDir');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'getProcessLogDir');
        return t.getProcessLogDir(processId);
      },
      'cleanupProcessLogs': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LogManager>(target, 'LogManager');
        D4.requireMinArgs(positional, 1, 'cleanupProcessLogs');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'cleanupProcessLogs');
        return t.cleanupProcessLogs(processId);
      },
    },
  );
}

// =============================================================================
// RetryExhaustedException Bridge
// =============================================================================

BridgedClass _createRetryExhaustedExceptionBridge() {
  return BridgedClass(
    nativeType: $pkg.RetryExhaustedException,
    name: 'RetryExhaustedException',
    constructors: {
      '': (visitor, positional, named) {
        final lastError = D4.getRequiredNamedArg<Object>(named, 'lastError', 'RetryExhaustedException');
        final lastStackTrace = D4.getOptionalNamedArg<StackTrace?>(named, 'lastStackTrace');
        final attempts = D4.getRequiredNamedArg<int>(named, 'attempts', 'RetryExhaustedException');
        return $pkg.RetryExhaustedException(lastError: lastError, lastStackTrace: lastStackTrace, attempts: attempts);
      },
    },
    getters: {
      'lastError': (visitor, target) => D4.validateTarget<$pkg.RetryExhaustedException>(target, 'RetryExhaustedException').lastError,
      'lastStackTrace': (visitor, target) => D4.validateTarget<$pkg.RetryExhaustedException>(target, 'RetryExhaustedException').lastStackTrace,
      'attempts': (visitor, target) => D4.validateTarget<$pkg.RetryExhaustedException>(target, 'RetryExhaustedException').attempts,
    },
    methods: {
      'toString': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RetryExhaustedException>(target, 'RetryExhaustedException');
        return t.toString();
      },
    },
  );
}

// =============================================================================
// RetryConfig Bridge
// =============================================================================

BridgedClass _createRetryConfigBridge() {
  return BridgedClass(
    nativeType: $pkg.RetryConfig,
    name: 'RetryConfig',
    constructors: {
      '': (visitor, positional, named) {
        final onRetry_raw = named['onRetry'];
        if (!named.containsKey('retryDelaysMs')) {
          return $pkg.RetryConfig(onRetry: onRetry_raw == null ? null : (int p0, Object p1, Duration p2) { (onRetry_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0, p1, p2]); });
        }
        if (named.containsKey('retryDelaysMs')) {
          final retryDelaysMs = D4.getRequiredNamedArg<List<int>>(named, 'retryDelaysMs', 'RetryConfig');
          return $pkg.RetryConfig(onRetry: onRetry_raw == null ? null : (int p0, Object p1, Duration p2) { (onRetry_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0, p1, p2]); }, retryDelaysMs: retryDelaysMs);
        }
      },
    },
    getters: {
      'retryDelaysMs': (visitor, target) => D4.validateTarget<$pkg.RetryConfig>(target, 'RetryConfig').retryDelaysMs,
      'onRetry': (visitor, target) => D4.validateTarget<$pkg.RetryConfig>(target, 'RetryConfig').onRetry,
    },
    staticGetters: {
      'defaultConfig': (visitor) => $pkg.RetryConfig.defaultConfig,
    },
  );
}

// =============================================================================
// ProcessMonitorClient Bridge
// =============================================================================

BridgedClass _createProcessMonitorClientBridge() {
  return BridgedClass(
    nativeType: $pkg.ProcessMonitorClient,
    name: 'ProcessMonitorClient',
    constructors: {
    },
    getters: {
      'instanceId': (visitor, target) => D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient').instanceId,
    },
    methods: {
      'register': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'register');
        final config = D4.getRequiredArg<$pkg.ProcessConfig>(positional, 0, 'config', 'register');
        return t.register(config);
      },
      'deregister': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'deregister');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'deregister');
        return t.deregister(processId);
      },
      'enable': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'enable');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'enable');
        return t.enable(processId);
      },
      'disable': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'disable');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'disable');
        return t.disable(processId);
      },
      'setAutostart': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        D4.requireMinArgs(positional, 2, 'setAutostart');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'setAutostart');
        final autostart = D4.getRequiredArg<bool>(positional, 1, 'autostart', 'setAutostart');
        return t.setAutostart(processId, autostart);
      },
      'start': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'start');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'start');
        return t.start(processId);
      },
      'stop': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'stop');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'stop');
        return t.stop(processId);
      },
      'restart': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'restart');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'restart');
        return t.restart(processId);
      },
      'getStatus': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'getStatus');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'getStatus');
        return t.getStatus(processId);
      },
      'getAllStatus': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        return t.getAllStatus();
      },
      'getMonitorStatus': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        return t.getMonitorStatus();
      },
      'setRemoteAccess': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'setRemoteAccess');
        final enabled = D4.getRequiredArg<bool>(positional, 0, 'enabled', 'setRemoteAccess');
        return t.setRemoteAccess(enabled);
      },
      'getRemoteAccessConfig': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        return t.getRemoteAccessConfig();
      },
      'setRemoteAccessPermissions': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        final allowRegister = D4.getOptionalNamedArg<bool?>(named, 'allowRegister');
        final allowDeregister = D4.getOptionalNamedArg<bool?>(named, 'allowDeregister');
        final allowStart = D4.getOptionalNamedArg<bool?>(named, 'allowStart');
        final allowStop = D4.getOptionalNamedArg<bool?>(named, 'allowStop');
        final allowDisable = D4.getOptionalNamedArg<bool?>(named, 'allowDisable');
        final allowAutostart = D4.getOptionalNamedArg<bool?>(named, 'allowAutostart');
        final allowMonitorRestart = D4.getOptionalNamedArg<bool?>(named, 'allowMonitorRestart');
        return t.setRemoteAccessPermissions(allowRegister: allowRegister, allowDeregister: allowDeregister, allowStart: allowStart, allowStop: allowStop, allowDisable: allowDisable, allowAutostart: allowAutostart, allowMonitorRestart: allowMonitorRestart);
      },
      'setTrustedHosts': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'setTrustedHosts');
        if (positional.length <= 0) {
          throw ArgumentError('setTrustedHosts: Missing required argument "hosts" at position 0');
        }
        final hosts = D4.coerceList<String>(positional[0], 'hosts');
        return t.setTrustedHosts(hosts);
      },
      'getTrustedHosts': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        return t.getTrustedHosts();
      },
      'getRemoteExecutableWhitelist': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        return t.getRemoteExecutableWhitelist();
      },
      'setRemoteExecutableWhitelist': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'setRemoteExecutableWhitelist');
        if (positional.length <= 0) {
          throw ArgumentError('setRemoteExecutableWhitelist: Missing required argument "patterns" at position 0');
        }
        final patterns = D4.coerceList<String>(positional[0], 'patterns');
        return t.setRemoteExecutableWhitelist(patterns);
      },
      'getRemoteExecutableBlacklist': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        return t.getRemoteExecutableBlacklist();
      },
      'setRemoteExecutableBlacklist': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'setRemoteExecutableBlacklist');
        if (positional.length <= 0) {
          throw ArgumentError('setRemoteExecutableBlacklist: Missing required argument "patterns" at position 0');
        }
        final patterns = D4.coerceList<String>(positional[0], 'patterns');
        return t.setRemoteExecutableBlacklist(patterns);
      },
      'setStandaloneMode': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'setStandaloneMode');
        final enabled = D4.getRequiredArg<bool>(positional, 0, 'enabled', 'setStandaloneMode');
        return t.setStandaloneMode(enabled);
      },
      'isStandaloneMode': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        return t.isStandaloneMode();
      },
      'getPartnerDiscoveryConfig': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        return t.getPartnerDiscoveryConfig();
      },
      'setPartnerDiscoveryConfig': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'setPartnerDiscoveryConfig');
        final config = D4.getRequiredArg<$pkg.PartnerDiscoveryConfig>(positional, 0, 'config', 'setPartnerDiscoveryConfig');
        return t.setPartnerDiscoveryConfig(config);
      },
      'restartMonitor': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        return t.restartMonitor();
      },
      'dispose': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.ProcessMonitorClient>(target, 'ProcessMonitorClient');
        t.dispose();
        return null;
      },
    },
    staticMethods: {
      'connect': (visitor, positional, named, typeArgs) {
        final instanceId = D4.getNamedArgWithDefault<String>(named, 'instanceId', 'default');
        final directory = D4.getOptionalNamedArg<String?>(named, 'directory');
        final baseUrl = D4.getOptionalNamedArg<String?>(named, 'baseUrl');
        final port = D4.getNamedArgWithDefault<int>(named, 'port', 19881);
        final timeout = D4.getNamedArgWithDefault<Duration>(named, 'timeout', const Duration(seconds: 5));
        return $pkg.ProcessMonitorClient.connect(instanceId: instanceId, directory: directory, baseUrl: baseUrl, port: port, timeout: timeout);
      },
    },
  );
}

// =============================================================================
// LocalProcessMonitorClient Bridge
// =============================================================================

BridgedClass _createLocalProcessMonitorClientBridge() {
  return BridgedClass(
    nativeType: $pkg.LocalProcessMonitorClient,
    name: 'LocalProcessMonitorClient',
    constructors: {
      '': (visitor, positional, named) {
        final directory = D4.getOptionalNamedArg<String?>(named, 'directory');
        final instanceId = D4.getNamedArgWithDefault<String>(named, 'instanceId', 'default');
        return $pkg.LocalProcessMonitorClient(directory: directory, instanceId: instanceId);
      },
    },
    getters: {
      'directory': (visitor, target) => D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient').directory,
      'instanceId': (visitor, target) => D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient').instanceId,
    },
    methods: {
      'register': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'register');
        final config = D4.getRequiredArg<$pkg.ProcessConfig>(positional, 0, 'config', 'register');
        return t.register(config);
      },
      'deregister': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'deregister');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'deregister');
        return t.deregister(processId);
      },
      'enable': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'enable');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'enable');
        return t.enable(processId);
      },
      'disable': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'disable');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'disable');
        return t.disable(processId);
      },
      'setAutostart': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        D4.requireMinArgs(positional, 2, 'setAutostart');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'setAutostart');
        final autostart = D4.getRequiredArg<bool>(positional, 1, 'autostart', 'setAutostart');
        return t.setAutostart(processId, autostart);
      },
      'start': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'start');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'start');
        return t.start(processId);
      },
      'stop': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'stop');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'stop');
        return t.stop(processId);
      },
      'restart': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'restart');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'restart');
        return t.restart(processId);
      },
      'getStatus': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'getStatus');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'getStatus');
        return t.getStatus(processId);
      },
      'getAllStatus': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        return t.getAllStatus();
      },
      'setRemoteAccess': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'setRemoteAccess');
        final enabled = D4.getRequiredArg<bool>(positional, 0, 'enabled', 'setRemoteAccess');
        return t.setRemoteAccess(enabled);
      },
      'getRemoteAccessConfig': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        return t.getRemoteAccessConfig();
      },
      'setRemoteAccessPermissions': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        final allowRegister = D4.getOptionalNamedArg<bool?>(named, 'allowRegister');
        final allowDeregister = D4.getOptionalNamedArg<bool?>(named, 'allowDeregister');
        final allowStart = D4.getOptionalNamedArg<bool?>(named, 'allowStart');
        final allowStop = D4.getOptionalNamedArg<bool?>(named, 'allowStop');
        final allowDisable = D4.getOptionalNamedArg<bool?>(named, 'allowDisable');
        final allowAutostart = D4.getOptionalNamedArg<bool?>(named, 'allowAutostart');
        final allowMonitorRestart = D4.getOptionalNamedArg<bool?>(named, 'allowMonitorRestart');
        return t.setRemoteAccessPermissions(allowRegister: allowRegister, allowDeregister: allowDeregister, allowStart: allowStart, allowStop: allowStop, allowDisable: allowDisable, allowAutostart: allowAutostart, allowMonitorRestart: allowMonitorRestart);
      },
      'setTrustedHosts': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'setTrustedHosts');
        if (positional.length <= 0) {
          throw ArgumentError('setTrustedHosts: Missing required argument "hosts" at position 0');
        }
        final hosts = D4.coerceList<String>(positional[0], 'hosts');
        return t.setTrustedHosts(hosts);
      },
      'getTrustedHosts': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        return t.getTrustedHosts();
      },
      'getRemoteExecutableWhitelist': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        return t.getRemoteExecutableWhitelist();
      },
      'setRemoteExecutableWhitelist': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'setRemoteExecutableWhitelist');
        if (positional.length <= 0) {
          throw ArgumentError('setRemoteExecutableWhitelist: Missing required argument "patterns" at position 0');
        }
        final patterns = D4.coerceList<String>(positional[0], 'patterns');
        return t.setRemoteExecutableWhitelist(patterns);
      },
      'getRemoteExecutableBlacklist': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        return t.getRemoteExecutableBlacklist();
      },
      'setRemoteExecutableBlacklist': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'setRemoteExecutableBlacklist');
        if (positional.length <= 0) {
          throw ArgumentError('setRemoteExecutableBlacklist: Missing required argument "patterns" at position 0');
        }
        final patterns = D4.coerceList<String>(positional[0], 'patterns');
        return t.setRemoteExecutableBlacklist(patterns);
      },
      'setStandaloneMode': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'setStandaloneMode');
        final enabled = D4.getRequiredArg<bool>(positional, 0, 'enabled', 'setStandaloneMode');
        return t.setStandaloneMode(enabled);
      },
      'isStandaloneMode': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        return t.isStandaloneMode();
      },
      'getPartnerDiscoveryConfig': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        return t.getPartnerDiscoveryConfig();
      },
      'setPartnerDiscoveryConfig': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'setPartnerDiscoveryConfig');
        final config = D4.getRequiredArg<$pkg.PartnerDiscoveryConfig>(positional, 0, 'config', 'setPartnerDiscoveryConfig');
        return t.setPartnerDiscoveryConfig(config);
      },
      'restartMonitor': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        return t.restartMonitor();
      },
      'getMonitorStatus': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        return t.getMonitorStatus();
      },
      'dispose': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalProcessMonitorClient>(target, 'LocalProcessMonitorClient');
        t.dispose();
        return null;
      },
    },
  );
}

// =============================================================================
// DiscoveryFailedException Bridge
// =============================================================================

BridgedClass _createDiscoveryFailedExceptionBridge() {
  return BridgedClass(
    nativeType: $pkg.DiscoveryFailedException,
    name: 'DiscoveryFailedException',
    constructors: {
      '': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'DiscoveryFailedException');
        final message = D4.getRequiredArg<String>(positional, 0, 'message', 'DiscoveryFailedException');
        return $pkg.DiscoveryFailedException(message);
      },
    },
    getters: {
      'message': (visitor, target) => D4.validateTarget<$pkg.DiscoveryFailedException>(target, 'DiscoveryFailedException').message,
    },
    methods: {
      'toString': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.DiscoveryFailedException>(target, 'DiscoveryFailedException');
        return t.toString();
      },
    },
  );
}

// =============================================================================
// RemoteProcessMonitorClient Bridge
// =============================================================================

BridgedClass _createRemoteProcessMonitorClientBridge() {
  return BridgedClass(
    nativeType: $pkg.RemoteProcessMonitorClient,
    name: 'RemoteProcessMonitorClient',
    constructors: {
      '': (visitor, positional, named) {
        final baseUrl = D4.getOptionalNamedArg<String?>(named, 'baseUrl');
        final instanceId = D4.getNamedArgWithDefault<String>(named, 'instanceId', 'default');
        return $pkg.RemoteProcessMonitorClient(baseUrl: baseUrl, instanceId: instanceId);
      },
    },
    getters: {
      'baseUrl': (visitor, target) => D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient').baseUrl,
      'instanceId': (visitor, target) => D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient').instanceId,
    },
    methods: {
      'dispose': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        t.dispose();
        return null;
      },
      'register': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'register');
        final config = D4.getRequiredArg<$pkg.ProcessConfig>(positional, 0, 'config', 'register');
        return t.register(config);
      },
      'deregister': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'deregister');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'deregister');
        return t.deregister(processId);
      },
      'enable': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'enable');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'enable');
        return t.enable(processId);
      },
      'disable': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'disable');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'disable');
        return t.disable(processId);
      },
      'setAutostart': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        D4.requireMinArgs(positional, 2, 'setAutostart');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'setAutostart');
        final autostart = D4.getRequiredArg<bool>(positional, 1, 'autostart', 'setAutostart');
        return t.setAutostart(processId, autostart);
      },
      'start': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'start');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'start');
        return t.start(processId);
      },
      'stop': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'stop');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'stop');
        return t.stop(processId);
      },
      'restart': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'restart');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'restart');
        return t.restart(processId);
      },
      'getStatus': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'getStatus');
        final processId = D4.getRequiredArg<String>(positional, 0, 'processId', 'getStatus');
        return t.getStatus(processId);
      },
      'getAllStatus': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        return t.getAllStatus();
      },
      'getMonitorStatus': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        return t.getMonitorStatus();
      },
      'setRemoteAccess': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'setRemoteAccess');
        final enabled = D4.getRequiredArg<bool>(positional, 0, 'enabled', 'setRemoteAccess');
        return t.setRemoteAccess(enabled);
      },
      'getRemoteAccessConfig': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        return t.getRemoteAccessConfig();
      },
      'setRemoteAccessPermissions': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        final allowRegister = D4.getOptionalNamedArg<bool?>(named, 'allowRegister');
        final allowDeregister = D4.getOptionalNamedArg<bool?>(named, 'allowDeregister');
        final allowStart = D4.getOptionalNamedArg<bool?>(named, 'allowStart');
        final allowStop = D4.getOptionalNamedArg<bool?>(named, 'allowStop');
        final allowDisable = D4.getOptionalNamedArg<bool?>(named, 'allowDisable');
        final allowAutostart = D4.getOptionalNamedArg<bool?>(named, 'allowAutostart');
        final allowMonitorRestart = D4.getOptionalNamedArg<bool?>(named, 'allowMonitorRestart');
        return t.setRemoteAccessPermissions(allowRegister: allowRegister, allowDeregister: allowDeregister, allowStart: allowStart, allowStop: allowStop, allowDisable: allowDisable, allowAutostart: allowAutostart, allowMonitorRestart: allowMonitorRestart);
      },
      'setTrustedHosts': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'setTrustedHosts');
        if (positional.length <= 0) {
          throw ArgumentError('setTrustedHosts: Missing required argument "hosts" at position 0');
        }
        final hosts = D4.coerceList<String>(positional[0], 'hosts');
        return t.setTrustedHosts(hosts);
      },
      'getTrustedHosts': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        return t.getTrustedHosts();
      },
      'getRemoteExecutableWhitelist': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        return t.getRemoteExecutableWhitelist();
      },
      'setRemoteExecutableWhitelist': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'setRemoteExecutableWhitelist');
        if (positional.length <= 0) {
          throw ArgumentError('setRemoteExecutableWhitelist: Missing required argument "patterns" at position 0');
        }
        final patterns = D4.coerceList<String>(positional[0], 'patterns');
        return t.setRemoteExecutableWhitelist(patterns);
      },
      'getRemoteExecutableBlacklist': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        return t.getRemoteExecutableBlacklist();
      },
      'setRemoteExecutableBlacklist': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'setRemoteExecutableBlacklist');
        if (positional.length <= 0) {
          throw ArgumentError('setRemoteExecutableBlacklist: Missing required argument "patterns" at position 0');
        }
        final patterns = D4.coerceList<String>(positional[0], 'patterns');
        return t.setRemoteExecutableBlacklist(patterns);
      },
      'setStandaloneMode': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'setStandaloneMode');
        final enabled = D4.getRequiredArg<bool>(positional, 0, 'enabled', 'setStandaloneMode');
        return t.setStandaloneMode(enabled);
      },
      'isStandaloneMode': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        return t.isStandaloneMode();
      },
      'getPartnerDiscoveryConfig': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        return t.getPartnerDiscoveryConfig();
      },
      'setPartnerDiscoveryConfig': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        D4.requireMinArgs(positional, 1, 'setPartnerDiscoveryConfig');
        final config = D4.getRequiredArg<$pkg.PartnerDiscoveryConfig>(positional, 0, 'config', 'setPartnerDiscoveryConfig');
        return t.setPartnerDiscoveryConfig(config);
      },
      'restartMonitor': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteProcessMonitorClient>(target, 'RemoteProcessMonitorClient');
        return t.restartMonitor();
      },
    },
    staticMethods: {
      'discover': (visitor, positional, named, typeArgs) {
        final port = D4.getNamedArgWithDefault<int>(named, 'port', 19881);
        final timeout = D4.getNamedArgWithDefault<Duration>(named, 'timeout', const Duration(seconds: 5));
        final instanceId = D4.getNamedArgWithDefault<String>(named, 'instanceId', 'default');
        return $pkg.RemoteProcessMonitorClient.discover(port: port, timeout: timeout, instanceId: instanceId);
      },
      'scanSubnet': (visitor, positional, named, typeArgs) {
        D4.requireMinArgs(positional, 1, 'scanSubnet');
        final subnet = D4.getRequiredArg<String>(positional, 0, 'subnet', 'scanSubnet');
        final port = D4.getNamedArgWithDefault<int>(named, 'port', 19881);
        final timeout = D4.getNamedArgWithDefault<Duration>(named, 'timeout', const Duration(milliseconds: 500));
        return $pkg.RemoteProcessMonitorClient.scanSubnet(subnet, port: port, timeout: timeout);
      },
    },
  );
}

