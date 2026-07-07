import 'dart:io';

Future<void> main() async {
  final testResult = await _run(
    'flutter',
    [
      'test',
      'test/user_learning_test.dart',
      'test/companion_agent_test.dart',
      'test/memory_insights_test.dart',
    ],
  );
  if (testResult != 0) {
    stderr.writeln('user learning tests failed with exit code $testResult');
    exitCode = testResult;
    return;
  }

  final scenarioResult = await _run(
    'dart',
    ['run', 'tool/evaluate_user_learning_scenarios.dart'],
  );
  if (scenarioResult != 0) {
    stderr.writeln(
      'user learning scenarios failed with exit code $scenarioResult',
    );
    exitCode = scenarioResult;
    return;
  }

  stdout.writeln('user learning verification passed');
}

Future<int> _run(String executable, List<String> arguments) async {
  final result = await Process.start(
    executable,
    arguments,
    runInShell: Platform.isWindows,
  );
  await Future.wait([
    stdout.addStream(result.stdout),
    stderr.addStream(result.stderr),
  ]);
  return result.exitCode;
}
