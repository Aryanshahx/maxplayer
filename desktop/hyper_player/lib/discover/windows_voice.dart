import 'dart:convert';
import 'dart:io';

/// Windows offline recognizer; uses installed speech language and OS microphone
/// permission, never sends audio to a service. Fails visibly when unavailable.
Future<String> recognizeWindowsSpeech() async {
  if (!Platform.isWindows) {
    throw UnsupportedError('Voice search requires Windows speech recognition');
  }
  const script = r'''
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
$r = New-Object System.Speech.Recognition.SpeechRecognitionEngine
try {
  $r.LoadGrammar((New-Object System.Speech.Recognition.DictationGrammar))
  $r.SetInputToDefaultAudioDevice()
  $result = $r.Recognize([TimeSpan]::FromSeconds(10))
  if ($null -eq $result) { throw 'No speech recognized in ten seconds' }
  [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
  [Console]::Write($result.Text)
} finally { $r.Dispose() }
''';
  final encoded =
      base64Encode(script.codeUnits.expand((c) => [c & 255, c >> 8]).toList());
  final process = await Process.start('powershell.exe',
      ['-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', encoded]);
  final output = process.stdout.transform(utf8.decoder).join();
  final errors = process.stderr.drain<void>();
  final code = await process.exitCode.timeout(const Duration(seconds: 18),
      onTimeout: () {
    process.kill();
    return -1;
  });
  final text = (await output).trim();
  await errors;
  if (code != 0 || text.isEmpty) {
    throw StateError(
        'Speech unavailable. Check Windows microphone permission, default input device and installed speech language.');
  }
  return text;
}
