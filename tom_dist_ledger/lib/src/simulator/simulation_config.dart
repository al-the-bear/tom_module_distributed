/// Configuration for error injection in DPL simulations.
class SimulationConfig {
  /// Participant crashes at specified elapsed time (ms).
  /// Key: participant name (e.g., 'cli', 'bridge')
  final Map<String, int> crashAt;

  /// Call hangs indefinitely (never returns).
  /// Format: 'participant:callId' (e.g., 'bridge:exec1')
  final Set<String> hangOnCall;

  /// Call takes longer than expected (ms).
  /// Key: 'participant:callId', Value: delay in ms
  final Map<String, int> delayCall;

  /// User abort (Ctrl+C) at specified elapsed time (ms).
  final int? userAbortAt;

  /// External call (e.g., Copilot Chat) fails.
  final bool externalCallFails;

  /// External call timeout in ms.
  final int externalCallTimeoutMs;

  /// External call response time in ms (if not failing).
  final int externalCallResponseMs;

  /// Path to ledger directory for file-based ledger.
  ///
  /// Default is '_ai/operation_ledger' relative to workspace root.
  /// This should be changed to an absolute path based on the workspace
  /// when the simulation is configured.
  final String ledgerPath;

  /// Default delay per call in ms (simulates realistic call duration).
  final int callDelayMs;

  /// Copilot processing output interval in ms.
  final int copilotProcessingIntervalMs;

  /// Interval for polling Copilot response file in ms.
  final int copilotPollingIntervalMs;

  const SimulationConfig({
    this.crashAt = const {},
    this.hangOnCall = const {},
    this.delayCall = const {},
    this.userAbortAt,
    this.externalCallFails = false,
    this.externalCallTimeoutMs = 120000,
    this.externalCallResponseMs = 10000,
    this.ledgerPath = '_ai/operation_ledger',
    this.callDelayMs = 5000,
    this.copilotProcessingIntervalMs = 2000,
    this.copilotPollingIntervalMs = 3000,
  });

  /// Happy path configuration.
  static const happyPath = SimulationConfig();

  /// User aborts at T+10s.
  static const userAbort = SimulationConfig(userAbortAt: 10000);

  /// CLI crashes at T+5s.
  static const cliCrash = SimulationConfig(crashAt: {'cli': 5000});

  /// Bridge crashes at T+15s.
  static const bridgeCrash = SimulationConfig(crashAt: {'bridge': 15000});

  /// External call times out.
  static const externalTimeout = SimulationConfig(
    externalCallFails: true,
    externalCallTimeoutMs: 120000,
  );
}
