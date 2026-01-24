import 'package:test/test.dart';
import 'package:tom_process_monitor_tool/tom_process_monitor_tool.dart';

void main() {
  group('CliRunner', () {
    late CliRunner runner;

    setUp(() {
      runner = CliRunner();
    });

    test('creates process_monitor parser', () {
      final parser = runner.createProcessMonitorParser();

      expect(parser.options.containsKey('help'), isTrue);
      expect(parser.options.containsKey('version'), isTrue);
      expect(parser.options.containsKey('directory'), isTrue);
      expect(parser.options.containsKey('foreground'), isTrue);
      expect(parser.options.containsKey('stop'), isTrue);
      expect(parser.options.containsKey('status'), isTrue);
      expect(parser.options.containsKey('restart'), isTrue);
    });

    test('creates watcher parser', () {
      final parser = runner.createWatcherParser();

      expect(parser.options.containsKey('help'), isTrue);
      expect(parser.options.containsKey('version'), isTrue);
      expect(parser.options.containsKey('directory'), isTrue);
      expect(parser.options.containsKey('foreground'), isTrue);
      expect(parser.options.containsKey('stop'), isTrue);
      expect(parser.options.containsKey('status'), isTrue);
      expect(parser.options.containsKey('restart'), isTrue);
    });

    test('parses help flag correctly', () {
      final parser = runner.createProcessMonitorParser();
      final results = parser.parse(['--help']);

      expect(results['help'], isTrue);
    });

    test('parses directory option correctly', () {
      final parser = runner.createProcessMonitorParser();
      final results = parser.parse(['--directory=/custom/path']);

      expect(results['directory'], equals('/custom/path'));
    });

    test('parses foreground flag correctly', () {
      final parser = runner.createProcessMonitorParser();
      final results = parser.parse(['-f']);

      expect(results['foreground'], isTrue);
    });
  });

  group('ProcessMonitorCommand', () {
    test('creates command', () {
      final command = ProcessMonitorCommand();
      expect(command, isNotNull);
    });
  });

  group('MonitorWatcherCommand', () {
    test('creates command', () {
      final command = MonitorWatcherCommand();
      expect(command, isNotNull);
    });
  });
}
