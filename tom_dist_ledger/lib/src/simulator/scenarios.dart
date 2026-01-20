import 'scenario.dart';
import 'simulation_config.dart';

/// Predefined simulation scenarios for testing the DPL system.
/// 
/// These scenarios cover various failure modes and edge cases to verify
/// that the distributed operation ledger handles all situations correctly.
class Scenarios {
  /// Fast test configuration with short delays.
  static const _testConfig = SimulationConfig(
    callDelayMs: 20,
    externalCallResponseMs: 100,
    copilotProcessingIntervalMs: 30,
    copilotPollingIntervalMs: 30,
  );

  // ═══════════════════════════════════════════════════════════════════
  // SUCCESS SCENARIOS
  // ═══════════════════════════════════════════════════════════════════

  /// Scenario 1: Happy path - all participants complete successfully.
  static final happyPath = SimulationScenario(
    name: 'happy_path',
    description: 'All participants complete successfully without any failures',
    expectedOutcome: 'Operation completes with exit code 0',
    config: _testConfig,
    callTree: const [
      ScenarioCall(
        callId: 'cli-main',
        caller: FailingParticipant.cli,
        processingMs: 50,
        nestedCalls: [
          ScenarioCall(
            callId: 'bridge-process',
            caller: FailingParticipant.bridge,
            spawnsProcess: true,
            processingMs: 50,
            nestedCalls: [
              ScenarioCall(
                callId: 'vscode-copilot',
                caller: FailingParticipant.vscode,
                callee: FailingParticipant.copilot,
                isExternal: true,
                processingMs: 100,
              ),
            ],
          ),
        ],
      ),
    ],
  );

  // ═══════════════════════════════════════════════════════════════════
  // INITIATOR (CLI) FAILURE SCENARIOS
  // ═══════════════════════════════════════════════════════════════════

  /// Scenario 2: CLI crashes during initialization.
  static final cliCrashDuringInit = SimulationScenario(
    name: 'cli_crash_during_init',
    description: 'CLI crashes while starting the operation before any calls',
    expectedOutcome: 'Operation never starts, no cleanup needed',
    config: _testConfig,
    callTree: const [
      ScenarioCall(
        callId: 'cli-main',
        caller: FailingParticipant.cli,
        processingMs: 100,
      ),
    ],
    failures: const [
      FailureInjection(
        participant: FailingParticipant.cli,
        type: FailureType.crash,
        phase: FailurePhase.initialization,
        delayMs: 30,
      ),
    ],
  );

  /// Scenario 3: CLI crashes while Bridge is processing.
  static final cliCrashDuringBridgeProcessing = SimulationScenario(
    name: 'cli_crash_during_bridge',
    description: 'CLI dies unexpectedly while Bridge subprocess is working',
    expectedOutcome:
        'Bridge detects stale CLI heartbeat, initiates cleanup, operation aborted',
    config: _testConfig,
    callTree: const [
      ScenarioCall(
        callId: 'cli-main',
        caller: FailingParticipant.cli,
        processingMs: 50,
        nestedCalls: [
          ScenarioCall(
            callId: 'bridge-process',
            caller: FailingParticipant.bridge,
            spawnsProcess: true,
            processingMs: 200,
          ),
        ],
      ),
    ],
    failures: const [
      FailureInjection(
        participant: FailingParticipant.cli,
        type: FailureType.crash,
        phase: FailurePhase.processing,
        delayMs: 100,
      ),
    ],
  );

  /// Scenario 4: CLI crashes while Copilot is processing.
  static final cliCrashDuringCopilot = SimulationScenario(
    name: 'cli_crash_during_copilot',
    description: 'CLI dies while waiting for Copilot response (deep stack)',
    expectedOutcome:
        'All participants detect stale initiator, unwind stack in order',
    config: _testConfig,
    callTree: const [
      ScenarioCall(
        callId: 'cli-main',
        caller: FailingParticipant.cli,
        processingMs: 30,
        nestedCalls: [
          ScenarioCall(
            callId: 'bridge-process',
            caller: FailingParticipant.bridge,
            spawnsProcess: true,
            processingMs: 30,
            nestedCalls: [
              ScenarioCall(
                callId: 'vscode-copilot',
                caller: FailingParticipant.vscode,
                callee: FailingParticipant.copilot,
                isExternal: true,
                processingMs: 300,
              ),
            ],
          ),
        ],
      ),
    ],
    failures: const [
      FailureInjection(
        participant: FailingParticipant.cli,
        type: FailureType.crash,
        phase: FailurePhase.processing,
        delayMs: 150,
      ),
    ],
  );

  // ═══════════════════════════════════════════════════════════════════
  // BRIDGE (SUPERVISOR) FAILURE SCENARIOS
  // ═══════════════════════════════════════════════════════════════════

  /// Scenario 5: Bridge crashes during initialization.
  static final bridgeCrashDuringInit = SimulationScenario(
    name: 'bridge_crash_during_init',
    description: 'Bridge subprocess crashes immediately after spawn',
    expectedOutcome: 'CLI detects child death, logs error, continues or aborts',
    config: _testConfig,
    callTree: const [
      ScenarioCall(
        callId: 'cli-main',
        caller: FailingParticipant.cli,
        processingMs: 50,
        nestedCalls: [
          ScenarioCall(
            callId: 'bridge-process',
            caller: FailingParticipant.bridge,
            spawnsProcess: true,
            processingMs: 200,
          ),
        ],
      ),
    ],
    failures: const [
      FailureInjection(
        participant: FailingParticipant.bridge,
        type: FailureType.crash,
        phase: FailurePhase.initialization,
        delayMs: 80,
      ),
    ],
  );

  /// Scenario 6: Bridge crashes during Copilot call.
  static final bridgeCrashDuringCopilot = SimulationScenario(
    name: 'bridge_crash_during_copilot',
    description: 'Bridge supervisor dies while VSCode waits for Copilot',
    expectedOutcome:
        'VSCode detects stale Bridge, aborts Copilot call, CLI detects cascade',
    config: _testConfig,
    callTree: const [
      ScenarioCall(
        callId: 'cli-main',
        caller: FailingParticipant.cli,
        processingMs: 30,
        nestedCalls: [
          ScenarioCall(
            callId: 'bridge-process',
            caller: FailingParticipant.bridge,
            spawnsProcess: true,
            processingMs: 30,
            nestedCalls: [
              ScenarioCall(
                callId: 'vscode-copilot',
                caller: FailingParticipant.vscode,
                callee: FailingParticipant.copilot,
                isExternal: true,
                processingMs: 300,
              ),
            ],
          ),
        ],
      ),
    ],
    failures: const [
      FailureInjection(
        participant: FailingParticipant.bridge,
        type: FailureType.crash,
        phase: FailurePhase.processing,
        delayMs: 120,
      ),
    ],
  );

  /// Scenario 7: Bridge hangs indefinitely (no response).
  static final bridgeHang = SimulationScenario(
    name: 'bridge_hang',
    description: 'Bridge process stops responding but does not crash',
    expectedOutcome:
        'CLI detects stale Bridge heartbeat, sets abort flag, cleans up',
    config: _testConfig,
    callTree: const [
      ScenarioCall(
        callId: 'cli-main',
        caller: FailingParticipant.cli,
        processingMs: 50,
        nestedCalls: [
          ScenarioCall(
            callId: 'bridge-process',
            caller: FailingParticipant.bridge,
            spawnsProcess: true,
            processingMs: 500, // Long processing simulates hang
          ),
        ],
      ),
    ],
    failures: const [
      FailureInjection(
        participant: FailingParticipant.bridge,
        type: FailureType.staleHeartbeat,
        phase: FailurePhase.processing,
        delayMs: 150,
      ),
    ],
  );

  // ═══════════════════════════════════════════════════════════════════
  // EXTERNAL CALL FAILURE SCENARIOS
  // ═══════════════════════════════════════════════════════════════════

  /// Scenario 8: Copilot times out (no response within timeout).
  static final copilotTimeout = SimulationScenario(
    name: 'copilot_timeout',
    description: 'Copilot Chat never responds within the timeout period',
    expectedOutcome:
        'VSCode catches timeout, propagates error up stack, operation fails',
    config: const SimulationConfig(
      callDelayMs: 20,
      externalCallResponseMs: 500, // Will time out
      externalCallTimeoutMs: 100, // Short timeout
      copilotProcessingIntervalMs: 30,
      copilotPollingIntervalMs: 30,
      externalCallFails: true,
    ),
    callTree: const [
      ScenarioCall(
        callId: 'cli-main',
        caller: FailingParticipant.cli,
        processingMs: 30,
        nestedCalls: [
          ScenarioCall(
            callId: 'bridge-process',
            caller: FailingParticipant.bridge,
            spawnsProcess: true,
            processingMs: 30,
            nestedCalls: [
              ScenarioCall(
                callId: 'vscode-copilot',
                caller: FailingParticipant.vscode,
                callee: FailingParticipant.copilot,
                isExternal: true,
                processingMs: 200,
              ),
            ],
          ),
        ],
      ),
    ],
  );

  /// Scenario 9: Copilot returns error response.
  static final copilotError = SimulationScenario(
    name: 'copilot_error',
    description: 'Copilot Chat returns an error instead of valid response',
    expectedOutcome:
        'VSCode receives error, logs issue, may retry or propagate failure',
    config: _testConfig,
    callTree: const [
      ScenarioCall(
        callId: 'cli-main',
        caller: FailingParticipant.cli,
        processingMs: 30,
        nestedCalls: [
          ScenarioCall(
            callId: 'bridge-process',
            caller: FailingParticipant.bridge,
            spawnsProcess: true,
            processingMs: 30,
            nestedCalls: [
              ScenarioCall(
                callId: 'vscode-copilot',
                caller: FailingParticipant.vscode,
                callee: FailingParticipant.copilot,
                isExternal: true,
                processingMs: 100,
              ),
            ],
          ),
        ],
      ),
    ],
    failures: const [
      FailureInjection(
        participant: FailingParticipant.copilot,
        type: FailureType.error,
        phase: FailurePhase.processing,
        errorMessage: 'Copilot API error: rate limited',
      ),
    ],
  );

  // ═══════════════════════════════════════════════════════════════════
  // USER ABORT SCENARIOS
  // ═══════════════════════════════════════════════════════════════════

  /// Scenario 10: User aborts during Bridge processing.
  static final userAbortDuringBridge = SimulationScenario(
    name: 'user_abort_during_bridge',
    description: 'User presses Ctrl+C while Bridge is processing',
    expectedOutcome:
        'CLI sets abort flag, Bridge detects on heartbeat, cleans temp resources',
    config: _testConfig,
    callTree: const [
      ScenarioCall(
        callId: 'cli-main',
        caller: FailingParticipant.cli,
        processingMs: 30,
        nestedCalls: [
          ScenarioCall(
            callId: 'bridge-process',
            caller: FailingParticipant.bridge,
            spawnsProcess: true,
            processingMs: 200,
          ),
        ],
      ),
    ],
    failures: const [
      FailureInjection(
        participant: FailingParticipant.cli,
        type: FailureType.userAbort,
        phase: FailurePhase.processing,
        delayMs: 80,
      ),
    ],
  );

  /// Scenario 11: User aborts during Copilot call (deep stack).
  static final userAbortDuringCopilot = SimulationScenario(
    name: 'user_abort_during_copilot',
    description: 'User presses Ctrl+C during long Copilot processing',
    expectedOutcome:
        'Abort propagates down stack, Copilot call cancelled, orderly cleanup',
    config: _testConfig,
    callTree: const [
      ScenarioCall(
        callId: 'cli-main',
        caller: FailingParticipant.cli,
        processingMs: 30,
        nestedCalls: [
          ScenarioCall(
            callId: 'bridge-process',
            caller: FailingParticipant.bridge,
            spawnsProcess: true,
            processingMs: 30,
            nestedCalls: [
              ScenarioCall(
                callId: 'vscode-copilot',
                caller: FailingParticipant.vscode,
                callee: FailingParticipant.copilot,
                isExternal: true,
                processingMs: 300,
              ),
            ],
          ),
        ],
      ),
    ],
    failures: const [
      FailureInjection(
        participant: FailingParticipant.cli,
        type: FailureType.userAbort,
        phase: FailurePhase.processing,
        delayMs: 120,
      ),
    ],
  );

  // ═══════════════════════════════════════════════════════════════════
  // COMPLEX MULTI-FAILURE SCENARIOS
  // ═══════════════════════════════════════════════════════════════════

  /// Scenario 12: Nested calls without supervisor - direct CLI to VSCode.
  static final directCallNoSupervisor = SimulationScenario(
    name: 'direct_call_no_supervisor',
    description: 'CLI makes direct call to VSCode without Bridge in between',
    expectedOutcome: 'Simplified stack, direct abort propagation works',
    config: _testConfig,
    callTree: const [
      ScenarioCall(
        callId: 'cli-main',
        caller: FailingParticipant.cli,
        processingMs: 30,
        nestedCalls: [
          ScenarioCall(
            callId: 'vscode-direct',
            caller: FailingParticipant.vscode,
            callee: FailingParticipant.copilot,
            isExternal: true,
            processingMs: 100,
          ),
        ],
      ),
    ],
  );

  /// Scenario 13: Multiple parallel calls from Bridge.
  static final parallelCallsFromBridge = SimulationScenario(
    name: 'parallel_calls_from_bridge',
    description: 'Bridge spawns multiple parallel calls to different services',
    expectedOutcome: 'All parallel calls complete, proper tracking in ledger',
    config: _testConfig,
    callTree: const [
      ScenarioCall(
        callId: 'cli-main',
        caller: FailingParticipant.cli,
        processingMs: 30,
        nestedCalls: [
          ScenarioCall(
            callId: 'bridge-process',
            caller: FailingParticipant.bridge,
            spawnsProcess: true,
            processingMs: 30,
            nestedCalls: [
              // Simulated parallel calls (will run sequentially in test)
              ScenarioCall(
                callId: 'vscode-call-1',
                caller: FailingParticipant.vscode,
                processingMs: 50,
              ),
              ScenarioCall(
                callId: 'vscode-call-2',
                caller: FailingParticipant.vscode,
                processingMs: 50,
              ),
            ],
          ),
        ],
      ),
    ],
  );

  /// Scenario 14: Deeply nested call stack (5 levels).
  static final deeplyNestedStack = SimulationScenario(
    name: 'deeply_nested_stack',
    description: 'Call stack with 5 levels of nesting',
    expectedOutcome: 'Deep stack tracks correctly, abort unwinds all levels',
    config: _testConfig,
    callTree: const [
      ScenarioCall(
        callId: 'level-1',
        caller: FailingParticipant.cli,
        processingMs: 20,
        nestedCalls: [
          ScenarioCall(
            callId: 'level-2',
            caller: FailingParticipant.bridge,
            spawnsProcess: true,
            processingMs: 20,
            nestedCalls: [
              ScenarioCall(
                callId: 'level-3',
                caller: FailingParticipant.vscode,
                processingMs: 20,
                nestedCalls: [
                  ScenarioCall(
                    callId: 'level-4',
                    caller: FailingParticipant.bridge,
                    processingMs: 20,
                    nestedCalls: [
                      ScenarioCall(
                        callId: 'level-5',
                        caller: FailingParticipant.vscode,
                        callee: FailingParticipant.copilot,
                        isExternal: true,
                        processingMs: 50,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  /// Scenario 15: Crash during cleanup phase.
  static final crashDuringCleanup = SimulationScenario(
    name: 'crash_during_cleanup',
    description: 'Participant crashes while cleaning up temp resources',
    expectedOutcome: 'Remaining cleanup handled by ledger garbage collection',
    config: _testConfig,
    callTree: const [
      ScenarioCall(
        callId: 'cli-main',
        caller: FailingParticipant.cli,
        processingMs: 30,
        nestedCalls: [
          ScenarioCall(
            callId: 'bridge-process',
            caller: FailingParticipant.bridge,
            spawnsProcess: true,
            processingMs: 100,
          ),
        ],
      ),
    ],
    failures: const [
      FailureInjection(
        participant: FailingParticipant.bridge,
        type: FailureType.crash,
        phase: FailurePhase.completion,
        delayMs: 120,
      ),
    ],
  );

  /// Get all predefined scenarios.
  static List<SimulationScenario> get all => [
        happyPath,
        cliCrashDuringInit,
        cliCrashDuringBridgeProcessing,
        cliCrashDuringCopilot,
        bridgeCrashDuringInit,
        bridgeCrashDuringCopilot,
        bridgeHang,
        copilotTimeout,
        copilotError,
        userAbortDuringBridge,
        userAbortDuringCopilot,
        directCallNoSupervisor,
        parallelCallsFromBridge,
        deeplyNestedStack,
        crashDuringCleanup,
      ];

  /// Get scenarios by category.
  static List<SimulationScenario> get successScenarios => [happyPath];

  static List<SimulationScenario> get initiatorFailures => [
        cliCrashDuringInit,
        cliCrashDuringBridgeProcessing,
        cliCrashDuringCopilot,
      ];

  static List<SimulationScenario> get supervisorFailures => [
        bridgeCrashDuringInit,
        bridgeCrashDuringCopilot,
        bridgeHang,
      ];

  static List<SimulationScenario> get externalCallFailures => [
        copilotTimeout,
        copilotError,
      ];

  static List<SimulationScenario> get userAbortScenarios => [
        userAbortDuringBridge,
        userAbortDuringCopilot,
      ];

  static List<SimulationScenario> get complexScenarios => [
        directCallNoSupervisor,
        parallelCallsFromBridge,
        deeplyNestedStack,
        crashDuringCleanup,
      ];
}
