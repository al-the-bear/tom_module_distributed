import 'package:tom_process_monitor/tom_process_monitor.dart';

/// Example demonstrating ProcessMonitor usage.
void main() async {
  // Create a ProcessMonitor client using the factory method
  final client = ProcessMonitorClient.connect(
    directory: '~/.tom/process_monitor',
  );

  // Register a new process with monitoring
  final config = ProcessConfig(
    id: 'my-server',
    name: 'My Server',
    command: 'dart',
    args: ['run', 'bin/server.dart'],
    alivenessCheck: AlivenessCheck(
      enabled: true,
      url: 'http://localhost:8080/health',
    ),
    restartPolicy: RestartPolicy(
      maxAttempts: 3,
    ),
  );

  print('Registering process: ${config.name}');
  await client.register(config);

  // Start the process
  print('Starting process...');
  await client.start(config.id);

  // Get process status
  final status = await client.getStatus(config.id);
  print('Process status: ${status.state}');

  // Get all process statuses
  final allStatuses = await client.getAllStatus();
  print('Registered processes: ${allStatuses.keys.join(', ')}');

  // Remote API example
  print('\nUsing Remote API:');
  final remoteClient = RemoteProcessMonitorClient(
    baseUrl: 'http://localhost:19881',
  );

  try {
    final monitorStatus = await remoteClient.getMonitorStatus();
    print('Monitor status: ${monitorStatus.state}');
  } catch (e) {
    print('Remote API not available: $e');
  }

  remoteClient.dispose();

  // Cleanup
  await client.stop(config.id);
  await client.deregister(config.id);
  print('Process unregistered.');
}
