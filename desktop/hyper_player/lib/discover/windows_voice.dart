import 'dart:convert';
import 'dart:io';

/// Windows offline recognizer; uses installed speech language and OS microphone
/// permission, never sends audio to a service. Fails visibly when unavailable.
Future<String> recognizeWindowsSpeech({List<String> hints = const []}) async {
  if (!Platform.isWindows) {
    throw UnsupportedError('Voice search requires Windows speech recognition');
  }
  const script = r'''
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
$r = New-Object System.Speech.Recognition.SpeechRecognitionEngine
try {
  $dictation = New-Object System.Speech.Recognition.DictationGrammar
  $dictation.Weight = 0.35
  $r.LoadGrammar($dictation)
  $titles = @($env:HYPER_SPEECH_HINTS | ConvertFrom-Json)
  if ($titles.Count -gt 0) {
    $choices = New-Object System.Speech.Recognition.Choices
    $choices.Add([string[]]$titles)
    $builder = New-Object System.Speech.Recognition.GrammarBuilder
    $builder.Culture = $r.RecognizerInfo.Culture
    $builder.Append($choices)
    $grammar = New-Object System.Speech.Recognition.Grammar($builder)
    $grammar.Weight = 1.0
    $r.LoadGrammar($grammar)
  }
  $r.SetInputToDefaultAudioDevice()
  $result = $r.Recognize([TimeSpan]::FromSeconds(10))
  if ($null -eq $result) { throw 'No speech recognized in ten seconds' }
  [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
  [Console]::Write($result.Text)
} finally { $r.Dispose() }
''';
  final encoded =
      base64Encode(script.codeUnits.expand((c) => [c & 255, c >> 8]).toList());
  final process = await Process.start('powershell.exe', [
    '-NoLogo',
    '-NoProfile',
    '-NonInteractive',
    '-EncodedCommand',
    encoded
  ], environment: {
    'HYPER_SPEECH_HINTS':
        jsonEncode(hints.where((h) => h.isNotEmpty).take(200).toList())
  });
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
