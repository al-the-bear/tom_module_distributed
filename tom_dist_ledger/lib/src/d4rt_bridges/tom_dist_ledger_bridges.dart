// D4rt Bridge - Generated file, do not edit
// Sources: 9 files
// Generated: 2026-01-28T20:18:17.658078

import 'package:tom_d4rt/d4rt.dart';
import 'package:tom_d4rt/tom_d4rt.dart';
import 'dart:async';
import 'dart:io';

import 'package:tom_dist_ledger/tom_dist_ledger.dart' as $pkg;

/// Bridge class for all module.
class AllBridge {
  /// Returns all bridge class definitions.
  static List<BridgedClass> bridgeClasses() {
    return [
      _createCleanupHandlerBridge(),
      _createCallFrameBridge(),
      _createTempResourceBridge(),
      _createLedgerDataBridge(),
      _createHeartbeatResultBridge(),
      _createHeartbeatErrorBridge(),
      _createLedgerBridge(),
      _createLocalOperationBridge(),
      _createLocalLedgerBridge(),
      _createLedgerCallbackBridge(),
      _createOperationCallbackBridge(),
      _createCallCallbackBridge(),
      _createOperationFailedInfoBridge(),
      _createOperationFailedExceptionBridge(),
      _createCallBridge(),
      _createSpawnedCallBridge(),
      _createSyncResultBridge(),
      _createOperationHelperBridge(),
      _createRemoteLedgerExceptionBridge(),
      _createRemoteOperationBridge(),
      _createRetryExhaustedExceptionBridge(),
      _createRetryConfigBridge(),
      _createDiscoveredServerBridge(),
      _createDiscoveryOptionsBridge(),
      _createServerDiscoveryBridge(),
    ];
  }

  /// Returns all bridged enum definitions.
  static List<BridgedEnumDefinition> bridgedEnums() {
    return [
      BridgedEnumDefinition<$pkg.FrameState>(
        name: 'FrameState',
        values: $pkg.FrameState.values,
      ),
      BridgedEnumDefinition<$pkg.OperationState>(
        name: 'OperationState',
        values: $pkg.OperationState.values,
      ),
      BridgedEnumDefinition<$pkg.HeartbeatErrorType>(
        name: 'HeartbeatErrorType',
        values: $pkg.HeartbeatErrorType.values,
      ),
      BridgedEnumDefinition<$pkg.DLLogLevel>(
        name: 'DLLogLevel',
        values: $pkg.DLLogLevel.values,
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
    return "import 'package:tom_dist_ledger/tom_dist_ledger.dart';";
  }

  /// Returns a list of bridged enum names.
  static List<String> get enumNames => [
    'FrameState',
    'OperationState',
    'HeartbeatErrorType',
    'DLLogLevel',
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
// CleanupHandler Bridge
// =============================================================================

BridgedClass _createCleanupHandlerBridge() {
  return BridgedClass(
    nativeType: $pkg.CleanupHandler,
    name: 'CleanupHandler',
    constructors: {
    },
    methods: {
      'register': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.CleanupHandler>(target, 'CleanupHandler');
        D4.requireMinArgs(positional, 1, 'register');
        if (positional.length <= 0) {
          throw ArgumentError('register: Missing required argument "callback" at position 0');
        }
        final callback_raw = positional[0];
        return t.register(() { return (callback_raw as InterpretedFunction).call(visitor as InterpreterVisitor, []) as Future<void>; });
      },
      'unregister': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.CleanupHandler>(target, 'CleanupHandler');
        D4.requireMinArgs(positional, 1, 'unregister');
        final id = D4.getRequiredArg<int>(positional, 0, 'id', 'unregister');
        t.unregister(id);
        return null;
      },
      'cleanup': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.CleanupHandler>(target, 'CleanupHandler');
        return t.cleanup();
      },
      'dispose': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.CleanupHandler>(target, 'CleanupHandler');
        t.dispose();
        return null;
      },
    },
    staticGetters: {
      'instance': (visitor) => $pkg.CleanupHandler.instance,
    },
  );
}

// =============================================================================
// CallFrame Bridge
// =============================================================================

BridgedClass _createCallFrameBridge() {
  return BridgedClass(
    nativeType: $pkg.CallFrame,
    name: 'CallFrame',
    constructors: {
      '': (visitor, positional, named) {
        final participantId = D4.getRequiredNamedArg<String>(named, 'participantId', 'CallFrame');
        final callId = D4.getRequiredNamedArg<String>(named, 'callId', 'CallFrame');
        final pid = D4.getRequiredNamedArg<int>(named, 'pid', 'CallFrame');
        final startTime = D4.getRequiredNamedArg<DateTime>(named, 'startTime', 'CallFrame');
        final lastHeartbeat = D4.getOptionalNamedArg<DateTime?>(named, 'lastHeartbeat');
        final state = D4.getOptionalNamedArg<dynamic>(named, 'state');
        final description = D4.getOptionalNamedArg<String?>(named, 'description');
        final resources = D4.coerceListOrNull<String>(named['resources'], 'resources');
        final failOnCrash = D4.getNamedArgWithDefault<bool>(named, 'failOnCrash', true);
        return $pkg.CallFrame(participantId: participantId, callId: callId, pid: pid, startTime: startTime, lastHeartbeat: lastHeartbeat, state: state, description: description, resources: resources, failOnCrash: failOnCrash);
      },
      'fromJson': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'CallFrame');
        if (positional.length <= 0) {
          throw ArgumentError('CallFrame: Missing required argument "json" at position 0');
        }
        final json = D4.coerceMap<String, dynamic>(positional[0], 'json');
        return $pkg.CallFrame.fromJson(json);
      },
    },
    getters: {
      'participantId': (visitor, target) => D4.validateTarget<$pkg.CallFrame>(target, 'CallFrame').participantId,
      'callId': (visitor, target) => D4.validateTarget<$pkg.CallFrame>(target, 'CallFrame').callId,
      'pid': (visitor, target) => D4.validateTarget<$pkg.CallFrame>(target, 'CallFrame').pid,
      'startTime': (visitor, target) => D4.validateTarget<$pkg.CallFrame>(target, 'CallFrame').startTime,
      'lastHeartbeat': (visitor, target) => D4.validateTarget<$pkg.CallFrame>(target, 'CallFrame').lastHeartbeat,
      'state': (visitor, target) => D4.validateTarget<$pkg.CallFrame>(target, 'CallFrame').state,
      'description': (visitor, target) => D4.validateTarget<$pkg.CallFrame>(target, 'CallFrame').description,
      'resources': (visitor, target) => D4.validateTarget<$pkg.CallFrame>(target, 'CallFrame').resources,
      'failOnCrash': (visitor, target) => D4.validateTarget<$pkg.CallFrame>(target, 'CallFrame').failOnCrash,
      'heartbeatAgeMs': (visitor, target) => D4.validateTarget<$pkg.CallFrame>(target, 'CallFrame').heartbeatAgeMs,
    },
    setters: {
      'lastHeartbeat': (visitor, target, value) => 
        D4.validateTarget<$pkg.CallFrame>(target, 'CallFrame').lastHeartbeat = value as DateTime,
      'state': (visitor, target, value) => 
        D4.validateTarget<$pkg.CallFrame>(target, 'CallFrame').state = value as dynamic,
    },
    methods: {
      'toJson': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.CallFrame>(target, 'CallFrame');
        return t.toJson();
      },
      'isStale': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.CallFrame>(target, 'CallFrame');
        final timeoutMs = D4.getNamedArgWithDefault<int>(named, 'timeoutMs', 10000);
        return t.isStale(timeoutMs: timeoutMs);
      },
      'toString': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.CallFrame>(target, 'CallFrame');
        return t.toString();
      },
    },
  );
}

// =============================================================================
// TempResource Bridge
// =============================================================================

BridgedClass _createTempResourceBridge() {
  return BridgedClass(
    nativeType: $pkg.TempResource,
    name: 'TempResource',
    constructors: {
      '': (visitor, positional, named) {
        final path = D4.getRequiredNamedArg<String>(named, 'path', 'TempResource');
        final owner = D4.getRequiredNamedArg<int>(named, 'owner', 'TempResource');
        final registeredAt = D4.getRequiredNamedArg<DateTime>(named, 'registeredAt', 'TempResource');
        return $pkg.TempResource(path: path, owner: owner, registeredAt: registeredAt);
      },
      'fromJson': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'TempResource');
        if (positional.length <= 0) {
          throw ArgumentError('TempResource: Missing required argument "json" at position 0');
        }
        final json = D4.coerceMap<String, dynamic>(positional[0], 'json');
        return $pkg.TempResource.fromJson(json);
      },
    },
    getters: {
      'path': (visitor, target) => D4.validateTarget<$pkg.TempResource>(target, 'TempResource').path,
      'owner': (visitor, target) => D4.validateTarget<$pkg.TempResource>(target, 'TempResource').owner,
      'registeredAt': (visitor, target) => D4.validateTarget<$pkg.TempResource>(target, 'TempResource').registeredAt,
    },
    methods: {
      'toJson': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.TempResource>(target, 'TempResource');
        return t.toJson();
      },
      'toString': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.TempResource>(target, 'TempResource');
        return t.toString();
      },
    },
  );
}

// =============================================================================
// LedgerData Bridge
// =============================================================================

BridgedClass _createLedgerDataBridge() {
  return BridgedClass(
    nativeType: $pkg.LedgerData,
    name: 'LedgerData',
    constructors: {
      '': (visitor, positional, named) {
        final operationId = D4.getRequiredNamedArg<String>(named, 'operationId', 'LedgerData');
        final initiatorId = D4.getRequiredNamedArg<String>(named, 'initiatorId', 'LedgerData');
        final startTime = D4.getOptionalNamedArg<DateTime?>(named, 'startTime');
        final aborted = D4.getNamedArgWithDefault<bool>(named, 'aborted', false);
        final lastHeartbeat = D4.getOptionalNamedArg<DateTime?>(named, 'lastHeartbeat');
        final callFrames = D4.coerceListOrNull<$pkg.CallFrame>(named['callFrames'], 'callFrames');
        final tempResources = D4.coerceListOrNull<$pkg.TempResource>(named['tempResources'], 'tempResources');
        final operationState = D4.getOptionalNamedArg<dynamic>(named, 'operationState');
        final detectionTimestamp = D4.getOptionalNamedArg<DateTime?>(named, 'detectionTimestamp');
        final removalTimestamp = D4.getOptionalNamedArg<DateTime?>(named, 'removalTimestamp');
        return $pkg.LedgerData(operationId: operationId, initiatorId: initiatorId, startTime: startTime, aborted: aborted, lastHeartbeat: lastHeartbeat, callFrames: callFrames, tempResources: tempResources, operationState: operationState, detectionTimestamp: detectionTimestamp, removalTimestamp: removalTimestamp);
      },
      'fromJson': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'LedgerData');
        if (positional.length <= 0) {
          throw ArgumentError('LedgerData: Missing required argument "json" at position 0');
        }
        final json = D4.coerceMap<String, dynamic>(positional[0], 'json');
        return $pkg.LedgerData.fromJson(json);
      },
    },
    getters: {
      'operationId': (visitor, target) => D4.validateTarget<$pkg.LedgerData>(target, 'LedgerData').operationId,
      'initiatorId': (visitor, target) => D4.validateTarget<$pkg.LedgerData>(target, 'LedgerData').initiatorId,
      'startTime': (visitor, target) => D4.validateTarget<$pkg.LedgerData>(target, 'LedgerData').startTime,
      'aborted': (visitor, target) => D4.validateTarget<$pkg.LedgerData>(target, 'LedgerData').aborted,
      'lastHeartbeat': (visitor, target) => D4.validateTarget<$pkg.LedgerData>(target, 'LedgerData').lastHeartbeat,
      'callFrames': (visitor, target) => D4.validateTarget<$pkg.LedgerData>(target, 'LedgerData').callFrames,
      'tempResources': (visitor, target) => D4.validateTarget<$pkg.LedgerData>(target, 'LedgerData').tempResources,
      'operationState': (visitor, target) => D4.validateTarget<$pkg.LedgerData>(target, 'LedgerData').operationState,
      'detectionTimestamp': (visitor, target) => D4.validateTarget<$pkg.LedgerData>(target, 'LedgerData').detectionTimestamp,
      'removalTimestamp': (visitor, target) => D4.validateTarget<$pkg.LedgerData>(target, 'LedgerData').removalTimestamp,
      'isEmpty': (visitor, target) => D4.validateTarget<$pkg.LedgerData>(target, 'LedgerData').isEmpty,
    },
    setters: {
      'aborted': (visitor, target, value) => 
        D4.validateTarget<$pkg.LedgerData>(target, 'LedgerData').aborted = value as bool,
      'lastHeartbeat': (visitor, target, value) => 
        D4.validateTarget<$pkg.LedgerData>(target, 'LedgerData').lastHeartbeat = value as DateTime,
      'operationState': (visitor, target, value) => 
        D4.validateTarget<$pkg.LedgerData>(target, 'LedgerData').operationState = value as dynamic,
      'detectionTimestamp': (visitor, target, value) => 
        D4.validateTarget<$pkg.LedgerData>(target, 'LedgerData').detectionTimestamp = value as DateTime?,
      'removalTimestamp': (visitor, target, value) => 
        D4.validateTarget<$pkg.LedgerData>(target, 'LedgerData').removalTimestamp = value as DateTime?,
    },
    methods: {
      'toJson': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LedgerData>(target, 'LedgerData');
        return t.toJson();
      },
    },
  );
}

// =============================================================================
// HeartbeatResult Bridge
// =============================================================================

BridgedClass _createHeartbeatResultBridge() {
  return BridgedClass(
    nativeType: $pkg.HeartbeatResult,
    name: 'HeartbeatResult',
    constructors: {
      '': (visitor, positional, named) {
        final abortFlag = D4.getRequiredNamedArg<bool>(named, 'abortFlag', 'HeartbeatResult');
        final ledgerExists = D4.getRequiredNamedArg<bool>(named, 'ledgerExists', 'HeartbeatResult');
        final heartbeatUpdated = D4.getRequiredNamedArg<bool>(named, 'heartbeatUpdated', 'HeartbeatResult');
        final callFrameCount = D4.getRequiredNamedArg<int>(named, 'callFrameCount', 'HeartbeatResult');
        final tempResourceCount = D4.getRequiredNamedArg<int>(named, 'tempResourceCount', 'HeartbeatResult');
        final heartbeatAgeMs = D4.getRequiredNamedArg<int>(named, 'heartbeatAgeMs', 'HeartbeatResult');
        final isStale = D4.getRequiredNamedArg<bool>(named, 'isStale', 'HeartbeatResult');
        if (!named.containsKey('participants') || named['participants'] == null) {
          throw ArgumentError('HeartbeatResult: Missing required named argument "participants"');
        }
        final participants = D4.coerceList<String>(named['participants'], 'participants');
        final participantHeartbeatAges = named.containsKey('participantHeartbeatAges') && named['participantHeartbeatAges'] != null
            ? D4.coerceMap<String, int>(named['participantHeartbeatAges'], 'participantHeartbeatAges')
            : const <String, int>{};
        final staleParticipants = named.containsKey('staleParticipants') && named['staleParticipants'] != null
            ? D4.coerceList<String>(named['staleParticipants'], 'staleParticipants')
            : const <String>[];
        final dataBefore = D4.getOptionalNamedArg<$pkg.LedgerData?>(named, 'dataBefore');
        final dataAfter = D4.getOptionalNamedArg<$pkg.LedgerData?>(named, 'dataAfter');
        return $pkg.HeartbeatResult(abortFlag: abortFlag, ledgerExists: ledgerExists, heartbeatUpdated: heartbeatUpdated, callFrameCount: callFrameCount, tempResourceCount: tempResourceCount, heartbeatAgeMs: heartbeatAgeMs, isStale: isStale, participants: participants, participantHeartbeatAges: participantHeartbeatAges, staleParticipants: staleParticipants, dataBefore: dataBefore, dataAfter: dataAfter);
      },
      'noLedger': (visitor, positional, named) {
        return $pkg.HeartbeatResult.noLedger();
      },
    },
    getters: {
      'abortFlag': (visitor, target) => D4.validateTarget<$pkg.HeartbeatResult>(target, 'HeartbeatResult').abortFlag,
      'ledgerExists': (visitor, target) => D4.validateTarget<$pkg.HeartbeatResult>(target, 'HeartbeatResult').ledgerExists,
      'heartbeatUpdated': (visitor, target) => D4.validateTarget<$pkg.HeartbeatResult>(target, 'HeartbeatResult').heartbeatUpdated,
      'callFrameCount': (visitor, target) => D4.validateTarget<$pkg.HeartbeatResult>(target, 'HeartbeatResult').callFrameCount,
      'tempResourceCount': (visitor, target) => D4.validateTarget<$pkg.HeartbeatResult>(target, 'HeartbeatResult').tempResourceCount,
      'heartbeatAgeMs': (visitor, target) => D4.validateTarget<$pkg.HeartbeatResult>(target, 'HeartbeatResult').heartbeatAgeMs,
      'isStale': (visitor, target) => D4.validateTarget<$pkg.HeartbeatResult>(target, 'HeartbeatResult').isStale,
      'participants': (visitor, target) => D4.validateTarget<$pkg.HeartbeatResult>(target, 'HeartbeatResult').participants,
      'participantHeartbeatAges': (visitor, target) => D4.validateTarget<$pkg.HeartbeatResult>(target, 'HeartbeatResult').participantHeartbeatAges,
      'staleParticipants': (visitor, target) => D4.validateTarget<$pkg.HeartbeatResult>(target, 'HeartbeatResult').staleParticipants,
      'dataBefore': (visitor, target) => D4.validateTarget<$pkg.HeartbeatResult>(target, 'HeartbeatResult').dataBefore,
      'dataAfter': (visitor, target) => D4.validateTarget<$pkg.HeartbeatResult>(target, 'HeartbeatResult').dataAfter,
      'hasStaleChildren': (visitor, target) => D4.validateTarget<$pkg.HeartbeatResult>(target, 'HeartbeatResult').hasStaleChildren,
    },
  );
}

// =============================================================================
// HeartbeatError Bridge
// =============================================================================

BridgedClass _createHeartbeatErrorBridge() {
  return BridgedClass(
    nativeType: $pkg.HeartbeatError,
    name: 'HeartbeatError',
    constructors: {
      '': (visitor, positional, named) {
        final type = D4.getRequiredNamedArg<dynamic>(named, 'type', 'HeartbeatError');
        final message = D4.getRequiredNamedArg<String>(named, 'message', 'HeartbeatError');
        final cause = D4.getOptionalNamedArg<Object?>(named, 'cause');
        return $pkg.HeartbeatError(type: type, message: message, cause: cause);
      },
    },
    getters: {
      'type': (visitor, target) => D4.validateTarget<$pkg.HeartbeatError>(target, 'HeartbeatError').type,
      'message': (visitor, target) => D4.validateTarget<$pkg.HeartbeatError>(target, 'HeartbeatError').message,
      'cause': (visitor, target) => D4.validateTarget<$pkg.HeartbeatError>(target, 'HeartbeatError').cause,
    },
    methods: {
      'toString': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.HeartbeatError>(target, 'HeartbeatError');
        return t.toString();
      },
    },
  );
}

// =============================================================================
// Ledger Bridge
// =============================================================================

BridgedClass _createLedgerBridge() {
  return BridgedClass(
    nativeType: $pkg.Ledger,
    name: 'Ledger',
    constructors: {
    },
    getters: {
      'participantId': (visitor, target) => D4.validateTarget<$pkg.Ledger>(target, 'Ledger').participantId,
      'participantPid': (visitor, target) => D4.validateTarget<$pkg.Ledger>(target, 'Ledger').participantPid,
      'maxBackups': (visitor, target) => D4.validateTarget<$pkg.Ledger>(target, 'Ledger').maxBackups,
      'heartbeatInterval': (visitor, target) => D4.validateTarget<$pkg.Ledger>(target, 'Ledger').heartbeatInterval,
      'staleThreshold': (visitor, target) => D4.validateTarget<$pkg.Ledger>(target, 'Ledger').staleThreshold,
    },
    methods: {
      'createOperation': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.Ledger>(target, 'Ledger');
        final description = D4.getOptionalNamedArg<String?>(named, 'description');
        final callback = D4.getOptionalNamedArg<$pkg.OperationCallback?>(named, 'callback');
        return t.createOperation(description: description, callback: callback);
      },
      'joinOperation': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.Ledger>(target, 'Ledger');
        final operationId = D4.getRequiredNamedArg<String>(named, 'operationId', 'joinOperation');
        final callback = D4.getOptionalNamedArg<$pkg.OperationCallback?>(named, 'callback');
        return t.joinOperation(operationId: operationId, callback: callback);
      },
      'dispose': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.Ledger>(target, 'Ledger');
        t.dispose();
        return null;
      },
    },
    staticMethods: {
      'connect': (visitor, positional, named, typeArgs) {
        final participantId = D4.getRequiredNamedArg<String>(named, 'participantId', 'connect');
        final basePath = D4.getOptionalNamedArg<String?>(named, 'basePath');
        final serverUrl = D4.getOptionalNamedArg<String?>(named, 'serverUrl');
        final participantPid = D4.getOptionalNamedArg<int?>(named, 'participantPid');
        final callback = D4.getOptionalNamedArg<$pkg.LedgerCallback?>(named, 'callback');
        final maxBackups = D4.getNamedArgWithDefault<int>(named, 'maxBackups', 20);
        final heartbeatInterval = D4.getNamedArgWithDefault<Duration>(named, 'heartbeatInterval', const Duration(seconds: 5));
        final staleThreshold = D4.getNamedArgWithDefault<Duration>(named, 'staleThreshold', const Duration(seconds: 15));
        return $pkg.Ledger.connect(participantId: participantId, basePath: basePath, serverUrl: serverUrl, participantPid: participantPid, callback: callback, maxBackups: maxBackups, heartbeatInterval: heartbeatInterval, staleThreshold: staleThreshold);
      },
    },
  );
}

// =============================================================================
// LocalOperation Bridge
// =============================================================================

BridgedClass _createLocalOperationBridge() {
  return BridgedClass(
    nativeType: $pkg.LocalOperation,
    name: 'LocalOperation',
    constructors: {
    },
    getters: {
      'sessionId': (visitor, target) => D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation').sessionId,
      'operationId': (visitor, target) => D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation').operationId,
      'participantId': (visitor, target) => D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation').participantId,
      'pid': (visitor, target) => D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation').pid,
      'isInitiator': (visitor, target) => D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation').isInitiator,
      'startTime': (visitor, target) => D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation').startTime,
      'cachedData': (visitor, target) => D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation').cachedData,
      'lastChangeTimestamp': (visitor, target) => D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation').lastChangeTimestamp,
      'isAborted': (visitor, target) => D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation').isAborted,
      'onAbort': (visitor, target) => D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation').onAbort,
      'onFailure': (visitor, target) => D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation').onFailure,
      'elapsedFormatted': (visitor, target) => D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation').elapsedFormatted,
      'elapsedDuration': (visitor, target) => D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation').elapsedDuration,
      'startTimeIso': (visitor, target) => D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation').startTimeIso,
      'startTimeMs': (visitor, target) => D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation').startTimeMs,
      'stalenessThresholdMs': (visitor, target) => D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation').stalenessThresholdMs,
      'pendingCallCount': (visitor, target) => D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation').pendingCallCount,
    },
    setters: {
      'stalenessThresholdMs': (visitor, target, value) => 
        D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation').stalenessThresholdMs = value as dynamic,
    },
    methods: {
      'startCall': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        final callback = D4.getOptionalNamedArg<$pkg.CallCallback<dynamic>>(named, 'callback');
        final description = D4.getOptionalNamedArg<String?>(named, 'description');
        final failOnCrash = D4.getNamedArgWithDefault<bool>(named, 'failOnCrash', true);
        return t.startCall(callback: callback, description: description, failOnCrash: failOnCrash);
      },
      'spawnCall': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        if (!named.containsKey('work') || named['work'] == null) {
          throw ArgumentError('spawnCall: Missing required named argument "work"');
        }
        final work_raw = named['work'];
        final callback = D4.getOptionalNamedArg<$pkg.CallCallback<dynamic>>(named, 'callback');
        final description = D4.getOptionalNamedArg<String?>(named, 'description');
        final failOnCrash = D4.getNamedArgWithDefault<bool>(named, 'failOnCrash', true);
        return t.spawnCall(work: ($pkg.SpawnedCall<dynamic> p0, $pkg.Operation p1) { return (work_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0, p1]) as Future<dynamic>; }, callback: callback, description: description, failOnCrash: failOnCrash);
      },
      'hasPendingCalls': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        return t.hasPendingCalls();
      },
      'getPendingSpawnedCalls': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        return t.getPendingSpawnedCalls();
      },
      'getPendingCalls': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        return t.getPendingCalls();
      },
      'leave': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        final cancelPendingCalls = D4.getNamedArgWithDefault<bool>(named, 'cancelPendingCalls', false);
        t.leave(cancelPendingCalls: cancelPendingCalls);
        return null;
      },
      'log': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        D4.requireMinArgs(positional, 1, 'log');
        final message = D4.getRequiredArg<String>(positional, 0, 'message', 'log');
        final level = D4.getNamedArgWithDefault<dynamic>(named, 'level', $pkg.DLLogLevel.info);
        return t.log(message, level: level);
      },
      'complete': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        return t.complete();
      },
      'setAbortFlag': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        D4.requireMinArgs(positional, 1, 'setAbortFlag');
        final value = D4.getRequiredArg<bool>(positional, 0, 'value', 'setAbortFlag');
        return t.setAbortFlag(value);
      },
      'checkAbort': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        return t.checkAbort();
      },
      'triggerAbort': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        t.triggerAbort();
        return null;
      },
      'waitForCompletion': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        D4.requireMinArgs(positional, 1, 'waitForCompletion');
        if (positional.length <= 0) {
          throw ArgumentError('waitForCompletion: Missing required argument "work" at position 0');
        }
        final work_raw = positional[0];
        final onOperationFailed_raw = named['onOperationFailed'];
        final onError_raw = named['onError'];
        return t.waitForCompletion(() { return (work_raw as InterpretedFunction).call(visitor as InterpreterVisitor, []) as Future<dynamic>; }, onOperationFailed: onOperationFailed_raw == null ? null : ($pkg.OperationFailedInfo p0) { return (onOperationFailed_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]) as Future<void>; }, onError: onError_raw == null ? null : (Object p0, StackTrace p1) { return (onError_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0, p1]) as Future<dynamic>; });
      },
      'startHeartbeat': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        final interval = D4.getNamedArgWithDefault<Duration>(named, 'interval', const Duration(milliseconds: 4500));
        final jitterMs = D4.getNamedArgWithDefault<int>(named, 'jitterMs', 500);
        final onError_raw = named['onError'];
        final onSuccess_raw = named['onSuccess'];
        t.startHeartbeat(interval: interval, jitterMs: jitterMs, onError: onError_raw == null ? null : ($pkg.Operation p0, $pkg.HeartbeatError p1) { (onError_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0, p1]); }, onSuccess: onSuccess_raw == null ? null : ($pkg.Operation p0, $pkg.HeartbeatResult p1) { (onSuccess_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0, p1]); });
        return null;
      },
      'stopHeartbeat': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        t.stopHeartbeat();
        return null;
      },
      'sync': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        D4.requireMinArgs(positional, 1, 'sync');
        if (positional.length <= 0) {
          throw ArgumentError('sync: Missing required argument "calls" at position 0');
        }
        final calls = D4.coerceList<$pkg.SpawnedCall>(positional[0], 'calls');
        final onOperationFailed_raw = named['onOperationFailed'];
        final onCompletion_raw = named['onCompletion'];
        return t.sync(calls, onOperationFailed: onOperationFailed_raw == null ? null : ($pkg.OperationFailedInfo p0) { return (onOperationFailed_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]) as Future<void>; }, onCompletion: onCompletion_raw == null ? null : () { return (onCompletion_raw as InterpretedFunction).call(visitor as InterpreterVisitor, []) as Future<void>; });
      },
      'execFileResultWorker': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        final executable = D4.getRequiredNamedArg<String>(named, 'executable', 'execFileResultWorker');
        if (!named.containsKey('arguments') || named['arguments'] == null) {
          throw ArgumentError('execFileResultWorker: Missing required named argument "arguments"');
        }
        final arguments = D4.coerceList<String>(named['arguments'], 'arguments');
        final resultFilePath = D4.getRequiredNamedArg<String>(named, 'resultFilePath', 'execFileResultWorker');
        final workingDirectory = D4.getOptionalNamedArg<String?>(named, 'workingDirectory');
        final description = D4.getOptionalNamedArg<String?>(named, 'description');
        final deserializer_raw = named['deserializer'];
        final deleteResultFile = D4.getNamedArgWithDefault<bool>(named, 'deleteResultFile', true);
        final pollInterval = D4.getNamedArgWithDefault<Duration>(named, 'pollInterval', const Duration(milliseconds: 100));
        final timeout = D4.getOptionalNamedArg<Duration?>(named, 'timeout');
        final onStdout_raw = named['onStdout'];
        final onStderr_raw = named['onStderr'];
        final onExit_raw = named['onExit'];
        final failOnCrash = D4.getNamedArgWithDefault<bool>(named, 'failOnCrash', true);
        final callback = D4.getOptionalNamedArg<$pkg.CallCallback<dynamic>>(named, 'callback');
        return t.execFileResultWorker(executable: executable, arguments: arguments, resultFilePath: resultFilePath, workingDirectory: workingDirectory, description: description, deserializer: deserializer_raw == null ? null : (String p0) { return (deserializer_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]) as dynamic; }, deleteResultFile: deleteResultFile, pollInterval: pollInterval, timeout: timeout, onStdout: onStdout_raw == null ? null : (String p0) { (onStdout_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]); }, onStderr: onStderr_raw == null ? null : (String p0) { (onStderr_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]); }, onExit: onExit_raw == null ? null : (int p0) { (onExit_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]); }, failOnCrash: failOnCrash, callback: callback);
      },
      'execStdioWorker': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        final executable = D4.getRequiredNamedArg<String>(named, 'executable', 'execStdioWorker');
        if (!named.containsKey('arguments') || named['arguments'] == null) {
          throw ArgumentError('execStdioWorker: Missing required named argument "arguments"');
        }
        final arguments = D4.coerceList<String>(named['arguments'], 'arguments');
        final workingDirectory = D4.getOptionalNamedArg<String?>(named, 'workingDirectory');
        final description = D4.getOptionalNamedArg<String?>(named, 'description');
        final deserializer_raw = named['deserializer'];
        final onStderr_raw = named['onStderr'];
        final onExit_raw = named['onExit'];
        final timeout = D4.getOptionalNamedArg<Duration?>(named, 'timeout');
        final failOnCrash = D4.getNamedArgWithDefault<bool>(named, 'failOnCrash', true);
        final callback = D4.getOptionalNamedArg<$pkg.CallCallback<dynamic>>(named, 'callback');
        return t.execStdioWorker(executable: executable, arguments: arguments, workingDirectory: workingDirectory, description: description, deserializer: deserializer_raw == null ? null : (String p0) { return (deserializer_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]) as dynamic; }, onStderr: onStderr_raw == null ? null : (String p0) { (onStderr_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]); }, onExit: onExit_raw == null ? null : (int p0) { (onExit_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]); }, timeout: timeout, failOnCrash: failOnCrash, callback: callback);
      },
      'awaitCall': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        D4.requireMinArgs(positional, 1, 'awaitCall');
        final call = D4.getRequiredArg<$pkg.SpawnedCall<dynamic>>(positional, 0, 'call', 'awaitCall');
        final onOperationFailed_raw = named['onOperationFailed'];
        final onCompletion_raw = named['onCompletion'];
        return t.awaitCall(call, onOperationFailed: onOperationFailed_raw == null ? null : ($pkg.OperationFailedInfo p0) { return (onOperationFailed_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]) as Future<void>; }, onCompletion: onCompletion_raw == null ? null : () { return (onCompletion_raw as InterpretedFunction).call(visitor as InterpreterVisitor, []) as Future<void>; });
      },
      'debugLog': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        D4.requireMinArgs(positional, 1, 'debugLog');
        final message = D4.getRequiredArg<String>(positional, 0, 'message', 'debugLog');
        return t.debugLog(message);
      },
      'getOperationState': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        return t.getOperationState();
      },
      'setOperationState': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        D4.requireMinArgs(positional, 1, 'setOperationState');
        final state = D4.getRequiredArg<dynamic>(positional, 0, 'state', 'setOperationState');
        return t.setOperationState(state);
      },
      'heartbeat': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        return t.heartbeat();
      },
      'logMessage': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        final depth = D4.getRequiredNamedArg<int>(named, 'depth', 'logMessage');
        final message = D4.getRequiredNamedArg<String>(named, 'message', 'logMessage');
        return t.logMessage(depth: depth, message: message);
      },
      'createCallFrame': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        final callId = D4.getRequiredNamedArg<String>(named, 'callId', 'createCallFrame');
        return t.createCallFrame(callId: callId);
      },
      'deleteCallFrame': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        final callId = D4.getRequiredNamedArg<String>(named, 'callId', 'deleteCallFrame');
        return t.deleteCallFrame(callId: callId);
      },
      'registerTempResource': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        final path = D4.getRequiredNamedArg<String>(named, 'path', 'registerTempResource');
        return t.registerTempResource(path: path);
      },
      'unregisterTempResource': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        final path = D4.getRequiredNamedArg<String>(named, 'path', 'unregisterTempResource');
        return t.unregisterTempResource(path: path);
      },
      'retrieveAndLockOperation': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        return t.retrieveAndLockOperation();
      },
      'unlockOperation': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        return t.unlockOperation();
      },
      'writeAndUnlockOperation': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        D4.requireMinArgs(positional, 1, 'writeAndUnlockOperation');
        final data = D4.getRequiredArg<$pkg.LedgerData>(positional, 0, 'data', 'writeAndUnlockOperation');
        return t.writeAndUnlockOperation(data);
      },
      'execServerRequest': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalOperation>(target, 'LocalOperation');
        if (!named.containsKey('work') || named['work'] == null) {
          throw ArgumentError('execServerRequest: Missing required named argument "work"');
        }
        final work_raw = named['work'];
        final description = D4.getOptionalNamedArg<String?>(named, 'description');
        final timeout = D4.getOptionalNamedArg<Duration?>(named, 'timeout');
        final failOnCrash = D4.getNamedArgWithDefault<bool>(named, 'failOnCrash', true);
        final callback = D4.getOptionalNamedArg<$pkg.CallCallback<dynamic>>(named, 'callback');
        return t.execServerRequest(work: () { return (work_raw as InterpretedFunction).call(visitor as InterpreterVisitor, []) as Future<dynamic>; }, description: description, timeout: timeout, failOnCrash: failOnCrash, callback: callback);
      },
    },
  );
}

// =============================================================================
// LocalLedger Bridge
// =============================================================================

BridgedClass _createLocalLedgerBridge() {
  return BridgedClass(
    nativeType: $pkg.LocalLedger,
    name: 'LocalLedger',
    constructors: {
      '': (visitor, positional, named) {
        final basePath = D4.getRequiredNamedArg<String>(named, 'basePath', 'LocalLedger');
        final participantId = D4.getRequiredNamedArg<String>(named, 'participantId', 'LocalLedger');
        final participantPid = D4.getOptionalNamedArg<int?>(named, 'participantPid');
        final callback = D4.getOptionalNamedArg<$pkg.LedgerCallback?>(named, 'callback');
        final maxBackups = D4.getNamedArgWithDefault<int>(named, 'maxBackups', 20);
        final heartbeatInterval = D4.getNamedArgWithDefault<Duration>(named, 'heartbeatInterval', const Duration(seconds: 5));
        final staleThreshold = D4.getNamedArgWithDefault<Duration>(named, 'staleThreshold', const Duration(seconds: 15));
        final lockTimeout = D4.getNamedArgWithDefault<Duration>(named, 'lockTimeout', const Duration(seconds: 2));
        final lockRetryInterval = D4.getNamedArgWithDefault<Duration>(named, 'lockRetryInterval', const Duration(milliseconds: 50));
        final maxLockRetryInterval = D4.getNamedArgWithDefault<Duration>(named, 'maxLockRetryInterval', const Duration(milliseconds: 500));
        return $pkg.LocalLedger(basePath: basePath, participantId: participantId, participantPid: participantPid, callback: callback, maxBackups: maxBackups, heartbeatInterval: heartbeatInterval, staleThreshold: staleThreshold, lockTimeout: lockTimeout, lockRetryInterval: lockRetryInterval, maxLockRetryInterval: maxLockRetryInterval);
      },
    },
    getters: {
      'participantId': (visitor, target) => D4.validateTarget<$pkg.LocalLedger>(target, 'LocalLedger').participantId,
      'participantPid': (visitor, target) => D4.validateTarget<$pkg.LocalLedger>(target, 'LocalLedger').participantPid,
      'maxBackups': (visitor, target) => D4.validateTarget<$pkg.LocalLedger>(target, 'LocalLedger').maxBackups,
      'heartbeatInterval': (visitor, target) => D4.validateTarget<$pkg.LocalLedger>(target, 'LocalLedger').heartbeatInterval,
      'staleThreshold': (visitor, target) => D4.validateTarget<$pkg.LocalLedger>(target, 'LocalLedger').staleThreshold,
      'basePath': (visitor, target) => D4.validateTarget<$pkg.LocalLedger>(target, 'LocalLedger').basePath,
      'callback': (visitor, target) => D4.validateTarget<$pkg.LocalLedger>(target, 'LocalLedger').callback,
      'lockTimeout': (visitor, target) => D4.validateTarget<$pkg.LocalLedger>(target, 'LocalLedger').lockTimeout,
      'lockRetryInterval': (visitor, target) => D4.validateTarget<$pkg.LocalLedger>(target, 'LocalLedger').lockRetryInterval,
      'maxLockRetryInterval': (visitor, target) => D4.validateTarget<$pkg.LocalLedger>(target, 'LocalLedger').maxLockRetryInterval,
    },
    methods: {
      'createOperation': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalLedger>(target, 'LocalLedger');
        final description = D4.getOptionalNamedArg<String?>(named, 'description');
        final callback = D4.getOptionalNamedArg<$pkg.OperationCallback?>(named, 'callback');
        return t.createOperation(description: description, callback: callback);
      },
      'joinOperation': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalLedger>(target, 'LocalLedger');
        final operationId = D4.getRequiredNamedArg<String>(named, 'operationId', 'joinOperation');
        final callback = D4.getOptionalNamedArg<$pkg.OperationCallback?>(named, 'callback');
        return t.joinOperation(operationId: operationId, callback: callback);
      },
      'dispose': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.LocalLedger>(target, 'LocalLedger');
        t.dispose();
        return null;
      },
    },
  );
}

// =============================================================================
// LedgerCallback Bridge
// =============================================================================

BridgedClass _createLedgerCallbackBridge() {
  return BridgedClass(
    nativeType: $pkg.LedgerCallback,
    name: 'LedgerCallback',
    constructors: {
      '': (visitor, positional, named) {
        final onBackupCreated_raw = named['onBackupCreated'];
        final onLogLine_raw = named['onLogLine'];
        final onGlobalHeartbeatError_raw = named['onGlobalHeartbeatError'];
        return $pkg.LedgerCallback(onBackupCreated: onBackupCreated_raw == null ? null : (String p0) { (onBackupCreated_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]); }, onLogLine: onLogLine_raw == null ? null : (String p0) { (onLogLine_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]); }, onGlobalHeartbeatError: onGlobalHeartbeatError_raw == null ? null : ($pkg.Operation p0, $pkg.HeartbeatError p1) { (onGlobalHeartbeatError_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0, p1]); });
      },
      'onBackup': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'LedgerCallback');
        if (positional.length <= 0) {
          throw ArgumentError('LedgerCallback: Missing required argument "onBackup" at position 0');
        }
        final onBackup_raw = positional[0];
        return $pkg.LedgerCallback.onBackup((String p0) { (onBackup_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]); });
      },
    },
    getters: {
      'onBackupCreated': (visitor, target) => D4.validateTarget<$pkg.LedgerCallback>(target, 'LedgerCallback').onBackupCreated,
      'onLogLine': (visitor, target) => D4.validateTarget<$pkg.LedgerCallback>(target, 'LedgerCallback').onLogLine,
      'onGlobalHeartbeatError': (visitor, target) => D4.validateTarget<$pkg.LedgerCallback>(target, 'LedgerCallback').onGlobalHeartbeatError,
    },
  );
}

// =============================================================================
// OperationCallback Bridge
// =============================================================================

BridgedClass _createOperationCallbackBridge() {
  return BridgedClass(
    nativeType: $pkg.OperationCallback,
    name: 'OperationCallback',
    constructors: {
      '': (visitor, positional, named) {
        final onHeartbeatSuccess_raw = named['onHeartbeatSuccess'];
        final onHeartbeatError_raw = named['onHeartbeatError'];
        final onAbort_raw = named['onAbort'];
        final onFailure_raw = named['onFailure'];
        return $pkg.OperationCallback(onHeartbeatSuccess: onHeartbeatSuccess_raw == null ? null : ($pkg.Operation p0, $pkg.HeartbeatResult p1) { (onHeartbeatSuccess_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0, p1]); }, onHeartbeatError: onHeartbeatError_raw == null ? null : ($pkg.Operation p0, $pkg.HeartbeatError p1) { (onHeartbeatError_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0, p1]); }, onAbort: onAbort_raw == null ? null : ($pkg.Operation p0) { (onAbort_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]); }, onFailure: onFailure_raw == null ? null : ($pkg.Operation p0, $pkg.OperationFailedInfo p1) { (onFailure_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0, p1]); });
      },
      'onError': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'OperationCallback');
        if (positional.length <= 0) {
          throw ArgumentError('OperationCallback: Missing required argument "onError" at position 0');
        }
        final onError_raw = positional[0];
        return $pkg.OperationCallback.onError(($pkg.Operation p0, $pkg.HeartbeatError p1) { (onError_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0, p1]); });
      },
      'onFailure': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'OperationCallback');
        if (positional.length <= 0) {
          throw ArgumentError('OperationCallback: Missing required argument "onFailure" at position 0');
        }
        final onFailure_raw = positional[0];
        return $pkg.OperationCallback.onFailure(($pkg.Operation p0, $pkg.OperationFailedInfo p1) { (onFailure_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0, p1]); });
      },
    },
    getters: {
      'onHeartbeatSuccess': (visitor, target) => D4.validateTarget<$pkg.OperationCallback>(target, 'OperationCallback').onHeartbeatSuccess,
      'onHeartbeatError': (visitor, target) => D4.validateTarget<$pkg.OperationCallback>(target, 'OperationCallback').onHeartbeatError,
      'onAbort': (visitor, target) => D4.validateTarget<$pkg.OperationCallback>(target, 'OperationCallback').onAbort,
      'onFailure': (visitor, target) => D4.validateTarget<$pkg.OperationCallback>(target, 'OperationCallback').onFailure,
    },
  );
}

// =============================================================================
// CallCallback Bridge
// =============================================================================

BridgedClass _createCallCallbackBridge() {
  return BridgedClass(
    nativeType: $pkg.CallCallback,
    name: 'CallCallback',
    constructors: {
      '': (visitor, positional, named) {
        final onCleanup_raw = named['onCleanup'];
        final onCompletion_raw = named['onCompletion'];
        final onCallCrashed_raw = named['onCallCrashed'];
        final onOperationFailed_raw = named['onOperationFailed'];
        return $pkg.CallCallback(onCleanup: onCleanup_raw == null ? null : () { return (onCleanup_raw as InterpretedFunction).call(visitor as InterpreterVisitor, []) as Future<void>; }, onCompletion: onCompletion_raw == null ? null : (dynamic p0) { return (onCompletion_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]) as Future<void>; }, onCallCrashed: onCallCrashed_raw == null ? null : () { return (onCallCrashed_raw as InterpretedFunction).call(visitor as InterpreterVisitor, []) as Future<dynamic>; }, onOperationFailed: onOperationFailed_raw == null ? null : ($pkg.OperationFailedInfo p0) { return (onOperationFailed_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]) as Future<void>; });
      },
      'cleanup': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'CallCallback');
        if (positional.length <= 0) {
          throw ArgumentError('CallCallback: Missing required argument "onCleanup" at position 0');
        }
        final onCleanup_raw = positional[0];
        return $pkg.CallCallback.cleanup(() { return (onCleanup_raw as InterpretedFunction).call(visitor as InterpreterVisitor, []) as Future<void>; });
      },
    },
    getters: {
      'onCleanup': (visitor, target) => D4.validateTarget<$pkg.CallCallback>(target, 'CallCallback').onCleanup,
      'onCompletion': (visitor, target) => D4.validateTarget<$pkg.CallCallback>(target, 'CallCallback').onCompletion,
      'onCallCrashed': (visitor, target) => D4.validateTarget<$pkg.CallCallback>(target, 'CallCallback').onCallCrashed,
      'onOperationFailed': (visitor, target) => D4.validateTarget<$pkg.CallCallback>(target, 'CallCallback').onOperationFailed,
    },
  );
}

// =============================================================================
// OperationFailedInfo Bridge
// =============================================================================

BridgedClass _createOperationFailedInfoBridge() {
  return BridgedClass(
    nativeType: $pkg.OperationFailedInfo,
    name: 'OperationFailedInfo',
    constructors: {
      '': (visitor, positional, named) {
        final operationId = D4.getRequiredNamedArg<String>(named, 'operationId', 'OperationFailedInfo');
        final failedAt = D4.getRequiredNamedArg<DateTime>(named, 'failedAt', 'OperationFailedInfo');
        final reason = D4.getOptionalNamedArg<String?>(named, 'reason');
        final crashedCallIds = named.containsKey('crashedCallIds') && named['crashedCallIds'] != null
            ? D4.coerceList<String>(named['crashedCallIds'], 'crashedCallIds')
            : const <String>[];
        return $pkg.OperationFailedInfo(operationId: operationId, failedAt: failedAt, reason: reason, crashedCallIds: crashedCallIds);
      },
    },
    getters: {
      'operationId': (visitor, target) => D4.validateTarget<$pkg.OperationFailedInfo>(target, 'OperationFailedInfo').operationId,
      'failedAt': (visitor, target) => D4.validateTarget<$pkg.OperationFailedInfo>(target, 'OperationFailedInfo').failedAt,
      'reason': (visitor, target) => D4.validateTarget<$pkg.OperationFailedInfo>(target, 'OperationFailedInfo').reason,
      'crashedCallIds': (visitor, target) => D4.validateTarget<$pkg.OperationFailedInfo>(target, 'OperationFailedInfo').crashedCallIds,
    },
    methods: {
      'toString': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.OperationFailedInfo>(target, 'OperationFailedInfo');
        return t.toString();
      },
    },
  );
}

// =============================================================================
// OperationFailedException Bridge
// =============================================================================

BridgedClass _createOperationFailedExceptionBridge() {
  return BridgedClass(
    nativeType: $pkg.OperationFailedException,
    name: 'OperationFailedException',
    constructors: {
      '': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'OperationFailedException');
        final info = D4.getRequiredArg<$pkg.OperationFailedInfo>(positional, 0, 'info', 'OperationFailedException');
        return $pkg.OperationFailedException(info);
      },
    },
    getters: {
      'info': (visitor, target) => D4.validateTarget<$pkg.OperationFailedException>(target, 'OperationFailedException').info,
    },
    methods: {
      'toString': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.OperationFailedException>(target, 'OperationFailedException');
        return t.toString();
      },
    },
  );
}

// =============================================================================
// Call Bridge
// =============================================================================

BridgedClass _createCallBridge() {
  return BridgedClass(
    nativeType: $pkg.Call,
    name: 'Call',
    constructors: {
      'internal': (visitor, positional, named) {
        final callId = D4.getRequiredNamedArg<String>(named, 'callId', 'Call');
        final operation = D4.getRequiredNamedArg<$pkg.CallLifecycle>(named, 'operation', 'Call');
        final startedAt = D4.getRequiredNamedArg<DateTime>(named, 'startedAt', 'Call');
        final description = D4.getOptionalNamedArg<String?>(named, 'description');
        return $pkg.Call.internal(callId: callId, operation: operation, startedAt: startedAt, description: description);
      },
    },
    getters: {
      'callId': (visitor, target) => D4.validateTarget<$pkg.Call>(target, 'Call').callId,
      'description': (visitor, target) => D4.validateTarget<$pkg.Call>(target, 'Call').description,
      'startedAt': (visitor, target) => D4.validateTarget<$pkg.Call>(target, 'Call').startedAt,
      'isCompleted': (visitor, target) => D4.validateTarget<$pkg.Call>(target, 'Call').isCompleted,
    },
    methods: {
      'end': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.Call>(target, 'Call');
        final result = D4.getOptionalArg<dynamic>(positional, 0, 'result');
        return t.end(result);
      },
      'fail': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.Call>(target, 'Call');
        D4.requireMinArgs(positional, 1, 'fail');
        final error = D4.getRequiredArg<Object>(positional, 0, 'error', 'fail');
        final stackTrace = D4.getOptionalArg<StackTrace?>(positional, 1, 'stackTrace');
        return t.fail(error, stackTrace);
      },
      'toString': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.Call>(target, 'Call');
        return t.toString();
      },
    },
  );
}

// =============================================================================
// SpawnedCall Bridge
// =============================================================================

BridgedClass _createSpawnedCallBridge() {
  return BridgedClass(
    nativeType: $pkg.SpawnedCall,
    name: 'SpawnedCall',
    constructors: {
      '': (visitor, positional, named) {
        final callId = D4.getRequiredNamedArg<String>(named, 'callId', 'SpawnedCall');
        final description = D4.getOptionalNamedArg<String?>(named, 'description');
        return $pkg.SpawnedCall(callId: callId, description: description);
      },
    },
    getters: {
      'callId': (visitor, target) => D4.validateTarget<$pkg.SpawnedCall>(target, 'SpawnedCall').callId,
      'description': (visitor, target) => D4.validateTarget<$pkg.SpawnedCall>(target, 'SpawnedCall').description,
      'isCompleted': (visitor, target) => D4.validateTarget<$pkg.SpawnedCall>(target, 'SpawnedCall').isCompleted,
      'isSuccess': (visitor, target) => D4.validateTarget<$pkg.SpawnedCall>(target, 'SpawnedCall').isSuccess,
      'isFailed': (visitor, target) => D4.validateTarget<$pkg.SpawnedCall>(target, 'SpawnedCall').isFailed,
      'isCancelled': (visitor, target) => D4.validateTarget<$pkg.SpawnedCall>(target, 'SpawnedCall').isCancelled,
      'result': (visitor, target) => D4.validateTarget<$pkg.SpawnedCall>(target, 'SpawnedCall').result,
      'resultOrNull': (visitor, target) => D4.validateTarget<$pkg.SpawnedCall>(target, 'SpawnedCall').resultOrNull,
      'future': (visitor, target) => D4.validateTarget<$pkg.SpawnedCall>(target, 'SpawnedCall').future,
      'error': (visitor, target) => D4.validateTarget<$pkg.SpawnedCall>(target, 'SpawnedCall').error,
      'stackTrace': (visitor, target) => D4.validateTarget<$pkg.SpawnedCall>(target, 'SpawnedCall').stackTrace,
    },
    methods: {
      'resultOr': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.SpawnedCall>(target, 'SpawnedCall');
        D4.requireMinArgs(positional, 1, 'resultOr');
        final defaultValue = D4.getRequiredArg<dynamic>(positional, 0, 'defaultValue', 'resultOr');
        return t.resultOr(defaultValue);
      },
      'cancel': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.SpawnedCall>(target, 'SpawnedCall');
        return t.cancel();
      },
      'kill': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.SpawnedCall>(target, 'SpawnedCall');
        final signal = D4.getOptionalArgWithDefault<ProcessSignal>(positional, 0, 'signal', ProcessSignal.sigterm);
        return t.kill(signal);
      },
      'await': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.SpawnedCall>(target, 'SpawnedCall');
        return t.await();
      },
      'complete': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.SpawnedCall>(target, 'SpawnedCall');
        D4.requireMinArgs(positional, 1, 'complete');
        final result = D4.getRequiredArg<dynamic>(positional, 0, 'result', 'complete');
        t.complete(result);
        return null;
      },
      'fail': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.SpawnedCall>(target, 'SpawnedCall');
        D4.requireMinArgs(positional, 1, 'fail');
        final error = D4.getRequiredArg<Object>(positional, 0, 'error', 'fail');
        final stackTrace = D4.getOptionalArg<StackTrace?>(positional, 1, 'stackTrace');
        t.fail(error, stackTrace);
        return null;
      },
      'toString': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.SpawnedCall>(target, 'SpawnedCall');
        return t.toString();
      },
    },
  );
}

// =============================================================================
// SyncResult Bridge
// =============================================================================

BridgedClass _createSyncResultBridge() {
  return BridgedClass(
    nativeType: $pkg.SyncResult,
    name: 'SyncResult',
    constructors: {
      '': (visitor, positional, named) {
        final successfulCalls = named.containsKey('successfulCalls') && named['successfulCalls'] != null
            ? D4.coerceList<$pkg.SpawnedCall<dynamic>>(named['successfulCalls'], 'successfulCalls')
            : const <$pkg.SpawnedCall<dynamic>>[];
        final failedCalls = named.containsKey('failedCalls') && named['failedCalls'] != null
            ? D4.coerceList<$pkg.SpawnedCall<dynamic>>(named['failedCalls'], 'failedCalls')
            : const <$pkg.SpawnedCall<dynamic>>[];
        final unknownCalls = named.containsKey('unknownCalls') && named['unknownCalls'] != null
            ? D4.coerceList<$pkg.SpawnedCall<dynamic>>(named['unknownCalls'], 'unknownCalls')
            : const <$pkg.SpawnedCall<dynamic>>[];
        final operationFailed = D4.getNamedArgWithDefault<bool>(named, 'operationFailed', false);
        return $pkg.SyncResult(successfulCalls: successfulCalls, failedCalls: failedCalls, unknownCalls: unknownCalls, operationFailed: operationFailed);
      },
    },
    getters: {
      'successfulCalls': (visitor, target) => D4.validateTarget<$pkg.SyncResult>(target, 'SyncResult').successfulCalls,
      'failedCalls': (visitor, target) => D4.validateTarget<$pkg.SyncResult>(target, 'SyncResult').failedCalls,
      'unknownCalls': (visitor, target) => D4.validateTarget<$pkg.SyncResult>(target, 'SyncResult').unknownCalls,
      'operationFailed': (visitor, target) => D4.validateTarget<$pkg.SyncResult>(target, 'SyncResult').operationFailed,
      'allSucceeded': (visitor, target) => D4.validateTarget<$pkg.SyncResult>(target, 'SyncResult').allSucceeded,
      'hasFailed': (visitor, target) => D4.validateTarget<$pkg.SyncResult>(target, 'SyncResult').hasFailed,
      'allResolved': (visitor, target) => D4.validateTarget<$pkg.SyncResult>(target, 'SyncResult').allResolved,
    },
    methods: {
      'toString': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.SyncResult>(target, 'SyncResult');
        return t.toString();
      },
    },
  );
}

// =============================================================================
// OperationHelper Bridge
// =============================================================================

BridgedClass _createOperationHelperBridge() {
  return BridgedClass(
    nativeType: $pkg.OperationHelper,
    name: 'OperationHelper',
    constructors: {
    },
    staticMethods: {
      'pollFile': (visitor, positional, named, typeArgs) {
        final path = D4.getRequiredNamedArg<String>(named, 'path', 'pollFile');
        final delete = D4.getNamedArgWithDefault<bool>(named, 'delete', false);
        final deserializer_raw = named['deserializer'];
        final deserializer = deserializer_raw == null ? null : (String p0) { return (deserializer_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]) as dynamic; };
        final pollInterval = D4.getNamedArgWithDefault<Duration>(named, 'pollInterval', const Duration(milliseconds: 100));
        final timeout = D4.getOptionalNamedArg<Duration?>(named, 'timeout');
        return $pkg.OperationHelper.pollFile(path: path, delete: delete, deserializer: deserializer, pollInterval: pollInterval, timeout: timeout);
      },
      'pollUntil': (visitor, positional, named, typeArgs) {
        if (!named.containsKey('check') || named['check'] == null) {
          throw ArgumentError('pollUntil: Missing required named argument "check"');
        }
        final check_raw = named['check'];
        final check = () { return (check_raw as InterpretedFunction).call(visitor as InterpreterVisitor, []) as Future<dynamic>; };
        final pollInterval = D4.getNamedArgWithDefault<Duration>(named, 'pollInterval', const Duration(milliseconds: 100));
        final timeout = D4.getOptionalNamedArg<Duration?>(named, 'timeout');
        return $pkg.OperationHelper.pollUntil(check: check, pollInterval: pollInterval, timeout: timeout);
      },
      'pollFiles': (visitor, positional, named, typeArgs) {
        if (!named.containsKey('paths') || named['paths'] == null) {
          throw ArgumentError('pollFiles: Missing required named argument "paths"');
        }
        final paths = D4.coerceList<String>(named['paths'], 'paths');
        final delete = D4.getNamedArgWithDefault<bool>(named, 'delete', false);
        final deserializer_raw = named['deserializer'];
        final deserializer = deserializer_raw == null ? null : (String p0) { return (deserializer_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]) as dynamic; };
        final pollInterval = D4.getNamedArgWithDefault<Duration>(named, 'pollInterval', const Duration(milliseconds: 100));
        final timeout = D4.getOptionalNamedArg<Duration?>(named, 'timeout');
        return $pkg.OperationHelper.pollFiles(paths: paths, delete: delete, deserializer: deserializer, pollInterval: pollInterval, timeout: timeout);
      },
    },
  );
}

// =============================================================================
// RemoteLedgerException Bridge
// =============================================================================

BridgedClass _createRemoteLedgerExceptionBridge() {
  return BridgedClass(
    nativeType: $pkg.RemoteLedgerException,
    name: 'RemoteLedgerException',
    constructors: {
      '': (visitor, positional, named) {
        D4.requireMinArgs(positional, 1, 'RemoteLedgerException');
        final message = D4.getRequiredArg<String>(positional, 0, 'message', 'RemoteLedgerException');
        final statusCode = D4.getOptionalNamedArg<int?>(named, 'statusCode');
        return $pkg.RemoteLedgerException(message, statusCode: statusCode);
      },
    },
    getters: {
      'message': (visitor, target) => D4.validateTarget<$pkg.RemoteLedgerException>(target, 'RemoteLedgerException').message,
      'statusCode': (visitor, target) => D4.validateTarget<$pkg.RemoteLedgerException>(target, 'RemoteLedgerException').statusCode,
    },
    methods: {
      'toString': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteLedgerException>(target, 'RemoteLedgerException');
        return t.toString();
      },
    },
  );
}

// =============================================================================
// RemoteOperation Bridge
// =============================================================================

BridgedClass _createRemoteOperationBridge() {
  return BridgedClass(
    nativeType: $pkg.RemoteOperation,
    name: 'RemoteOperation',
    constructors: {
    },
    getters: {
      'sessionId': (visitor, target) => D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation').sessionId,
      'operationId': (visitor, target) => D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation').operationId,
      'participantId': (visitor, target) => D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation').participantId,
      'pid': (visitor, target) => D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation').pid,
      'isInitiator': (visitor, target) => D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation').isInitiator,
      'startTime': (visitor, target) => D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation').startTime,
      'isAborted': (visitor, target) => D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation').isAborted,
      'onAbort': (visitor, target) => D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation').onAbort,
      'onFailure': (visitor, target) => D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation').onFailure,
      'elapsedFormatted': (visitor, target) => D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation').elapsedFormatted,
      'elapsedDuration': (visitor, target) => D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation').elapsedDuration,
      'startTimeIso': (visitor, target) => D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation').startTimeIso,
      'startTimeMs': (visitor, target) => D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation').startTimeMs,
      'pendingCallCount': (visitor, target) => D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation').pendingCallCount,
      'cachedData': (visitor, target) => D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation').cachedData,
      'localTempResources': (visitor, target) => D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation').localTempResources,
    },
    methods: {
      'startCall': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        final callback = D4.getOptionalNamedArg<$pkg.CallCallback<dynamic>>(named, 'callback');
        final description = D4.getOptionalNamedArg<String?>(named, 'description');
        final failOnCrash = D4.getNamedArgWithDefault<bool>(named, 'failOnCrash', true);
        return t.startCall(callback: callback, description: description, failOnCrash: failOnCrash);
      },
      'spawnCall': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        if (!named.containsKey('work') || named['work'] == null) {
          throw ArgumentError('spawnCall: Missing required named argument "work"');
        }
        final work_raw = named['work'];
        final callback = D4.getOptionalNamedArg<$pkg.CallCallback<dynamic>>(named, 'callback');
        final description = D4.getOptionalNamedArg<String?>(named, 'description');
        final failOnCrash = D4.getNamedArgWithDefault<bool>(named, 'failOnCrash', true);
        return t.spawnCall(work: ($pkg.SpawnedCall<dynamic> p0, $pkg.Operation p1) { return (work_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0, p1]) as Future<dynamic>; }, callback: callback, description: description, failOnCrash: failOnCrash);
      },
      'endCallInternal': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        final callId = D4.getRequiredNamedArg<String>(named, 'callId', 'endCallInternal');
        final result = D4.getOptionalNamedArg<dynamic>(named, 'result');
        return t.endCallInternal(callId: callId, result: result);
      },
      'failCallInternal': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        final callId = D4.getRequiredNamedArg<String>(named, 'callId', 'failCallInternal');
        final error = D4.getRequiredNamedArg<Object>(named, 'error', 'failCallInternal');
        final stackTrace = D4.getOptionalNamedArg<StackTrace?>(named, 'stackTrace');
        return t.failCallInternal(callId: callId, error: error, stackTrace: stackTrace);
      },
      'hasPendingCalls': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        return t.hasPendingCalls();
      },
      'getPendingSpawnedCalls': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        return t.getPendingSpawnedCalls();
      },
      'getPendingCalls': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        return t.getPendingCalls();
      },
      'sync': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        D4.requireMinArgs(positional, 1, 'sync');
        if (positional.length <= 0) {
          throw ArgumentError('sync: Missing required argument "calls" at position 0');
        }
        final calls = D4.coerceList<$pkg.SpawnedCall>(positional[0], 'calls');
        final onOperationFailed_raw = named['onOperationFailed'];
        final onCompletion_raw = named['onCompletion'];
        return t.sync(calls, onOperationFailed: onOperationFailed_raw == null ? null : ($pkg.OperationFailedInfo p0) { return (onOperationFailed_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]) as Future<void>; }, onCompletion: onCompletion_raw == null ? null : () { return (onCompletion_raw as InterpretedFunction).call(visitor as InterpreterVisitor, []) as Future<void>; });
      },
      'awaitCall': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        D4.requireMinArgs(positional, 1, 'awaitCall');
        final call = D4.getRequiredArg<$pkg.SpawnedCall<dynamic>>(positional, 0, 'call', 'awaitCall');
        final onOperationFailed_raw = named['onOperationFailed'];
        final onCompletion_raw = named['onCompletion'];
        return t.awaitCall(call, onOperationFailed: onOperationFailed_raw == null ? null : ($pkg.OperationFailedInfo p0) { return (onOperationFailed_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]) as Future<void>; }, onCompletion: onCompletion_raw == null ? null : () { return (onCompletion_raw as InterpretedFunction).call(visitor as InterpreterVisitor, []) as Future<void>; });
      },
      'waitForCompletion': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        D4.requireMinArgs(positional, 1, 'waitForCompletion');
        if (positional.length <= 0) {
          throw ArgumentError('waitForCompletion: Missing required argument "work" at position 0');
        }
        final work_raw = positional[0];
        final onOperationFailed_raw = named['onOperationFailed'];
        final onError_raw = named['onError'];
        return t.waitForCompletion(() { return (work_raw as InterpretedFunction).call(visitor as InterpreterVisitor, []) as Future<dynamic>; }, onOperationFailed: onOperationFailed_raw == null ? null : ($pkg.OperationFailedInfo p0) { return (onOperationFailed_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]) as Future<void>; }, onError: onError_raw == null ? null : (Object p0, StackTrace p1) { return (onError_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0, p1]) as Future<dynamic>; });
      },
      'leave': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        final cancelPendingCalls = D4.getNamedArgWithDefault<bool>(named, 'cancelPendingCalls', false);
        return t.leave(cancelPendingCalls: cancelPendingCalls);
      },
      'log': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        D4.requireMinArgs(positional, 1, 'log');
        final message = D4.getRequiredArg<String>(positional, 0, 'message', 'log');
        final level = D4.getNamedArgWithDefault<dynamic>(named, 'level', $pkg.DLLogLevel.info);
        return t.log(message, level: level);
      },
      'complete': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        return t.complete();
      },
      'setAbortFlag': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        D4.requireMinArgs(positional, 1, 'setAbortFlag');
        final value = D4.getRequiredArg<bool>(positional, 0, 'value', 'setAbortFlag');
        return t.setAbortFlag(value);
      },
      'checkAbort': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        return t.checkAbort();
      },
      'triggerAbort': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        t.triggerAbort();
        return null;
      },
      'createCallFrame': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        final callId = D4.getRequiredNamedArg<String>(named, 'callId', 'createCallFrame');
        return t.createCallFrame(callId: callId);
      },
      'deleteCallFrame': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        final callId = D4.getRequiredNamedArg<String>(named, 'callId', 'deleteCallFrame');
        return t.deleteCallFrame(callId: callId);
      },
      'registerTempResource': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        final path = D4.getRequiredNamedArg<String>(named, 'path', 'registerTempResource');
        return t.registerTempResource(path: path);
      },
      'unregisterTempResource': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        final path = D4.getRequiredNamedArg<String>(named, 'path', 'unregisterTempResource');
        return t.unregisterTempResource(path: path);
      },
      'cleanupLocalTempResources': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        return t.cleanupLocalTempResources();
      },
      'startHeartbeat': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        final interval = D4.getNamedArgWithDefault<Duration>(named, 'interval', const Duration(milliseconds: 4500));
        final jitterMs = D4.getNamedArgWithDefault<int>(named, 'jitterMs', 500);
        final onError_raw = named['onError'];
        final onSuccess_raw = named['onSuccess'];
        t.startHeartbeat(interval: interval, jitterMs: jitterMs, onError: onError_raw == null ? null : ($pkg.Operation p0, $pkg.HeartbeatError p1) { (onError_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0, p1]); }, onSuccess: onSuccess_raw == null ? null : ($pkg.Operation p0, $pkg.HeartbeatResult p1) { (onSuccess_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0, p1]); });
        return null;
      },
      'stopHeartbeat': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        t.stopHeartbeat();
        return null;
      },
      'heartbeat': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.RemoteOperation>(target, 'RemoteOperation');
        return t.heartbeat();
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
// DiscoveredServer Bridge
// =============================================================================

BridgedClass _createDiscoveredServerBridge() {
  return BridgedClass(
    nativeType: $pkg.DiscoveredServer,
    name: 'DiscoveredServer',
    constructors: {
      '': (visitor, positional, named) {
        final serverUrl = D4.getRequiredNamedArg<String>(named, 'serverUrl', 'DiscoveredServer');
        if (!named.containsKey('status') || named['status'] == null) {
          throw ArgumentError('DiscoveredServer: Missing required named argument "status"');
        }
        final status = D4.coerceMap<String, dynamic>(named['status'], 'status');
        return $pkg.DiscoveredServer(serverUrl: serverUrl, status: status);
      },
    },
    getters: {
      'serverUrl': (visitor, target) => D4.validateTarget<$pkg.DiscoveredServer>(target, 'DiscoveredServer').serverUrl,
      'status': (visitor, target) => D4.validateTarget<$pkg.DiscoveredServer>(target, 'DiscoveredServer').status,
      'service': (visitor, target) => D4.validateTarget<$pkg.DiscoveredServer>(target, 'DiscoveredServer').service,
      'version': (visitor, target) => D4.validateTarget<$pkg.DiscoveredServer>(target, 'DiscoveredServer').version,
      'port': (visitor, target) => D4.validateTarget<$pkg.DiscoveredServer>(target, 'DiscoveredServer').port,
    },
    methods: {
      'toString': (visitor, target, positional, named, typeArgs) {
        final t = D4.validateTarget<$pkg.DiscoveredServer>(target, 'DiscoveredServer');
        return t.toString();
      },
    },
  );
}

// =============================================================================
// DiscoveryOptions Bridge
// =============================================================================

BridgedClass _createDiscoveryOptionsBridge() {
  return BridgedClass(
    nativeType: $pkg.DiscoveryOptions,
    name: 'DiscoveryOptions',
    constructors: {
      '': (visitor, positional, named) {
        final port = D4.getNamedArgWithDefault<int>(named, 'port', 19880);
        final timeout = D4.getNamedArgWithDefault<Duration>(named, 'timeout', const Duration(milliseconds: 500));
        final scanSubnet = D4.getNamedArgWithDefault<bool>(named, 'scanSubnet', true);
        final maxConcurrent = D4.getNamedArgWithDefault<int>(named, 'maxConcurrent', 20);
        final logger_raw = named['logger'];
        return $pkg.DiscoveryOptions(port: port, timeout: timeout, scanSubnet: scanSubnet, maxConcurrent: maxConcurrent, logger: logger_raw == null ? null : (String p0) { (logger_raw as InterpretedFunction).call(visitor as InterpreterVisitor, [p0]); });
      },
    },
    getters: {
      'port': (visitor, target) => D4.validateTarget<$pkg.DiscoveryOptions>(target, 'DiscoveryOptions').port,
      'timeout': (visitor, target) => D4.validateTarget<$pkg.DiscoveryOptions>(target, 'DiscoveryOptions').timeout,
      'scanSubnet': (visitor, target) => D4.validateTarget<$pkg.DiscoveryOptions>(target, 'DiscoveryOptions').scanSubnet,
      'maxConcurrent': (visitor, target) => D4.validateTarget<$pkg.DiscoveryOptions>(target, 'DiscoveryOptions').maxConcurrent,
      'logger': (visitor, target) => D4.validateTarget<$pkg.DiscoveryOptions>(target, 'DiscoveryOptions').logger,
    },
  );
}

// =============================================================================
// ServerDiscovery Bridge
// =============================================================================

BridgedClass _createServerDiscoveryBridge() {
  return BridgedClass(
    nativeType: $pkg.ServerDiscovery,
    name: 'ServerDiscovery',
    constructors: {
    },
    staticMethods: {
      'discover': (visitor, positional, named, typeArgs) {
        if (positional.length == 1) {
          final options = D4.getRequiredArg<$pkg.DiscoveryOptions>(positional, 0, 'options', 'discover');
          return $pkg.ServerDiscovery.discover(options);
        }
        if (positional.length == 0) {
          return $pkg.ServerDiscovery.discover();
        }
      },
      'discoverAll': (visitor, positional, named, typeArgs) {
        if (positional.length == 1) {
          final options = D4.getRequiredArg<$pkg.DiscoveryOptions>(positional, 0, 'options', 'discoverAll');
          return $pkg.ServerDiscovery.discoverAll(options);
        }
        if (positional.length == 0) {
          return $pkg.ServerDiscovery.discoverAll();
        }
      },
    },
  );
}

