/// v98: tap-to-talk voice commands for the player.
///
/// The speech itself comes from the existing in-app recognizer
/// (VoiceSearchSheet + the native `startVoiceSearch` channel that search
/// already uses) - this file is only the TEXT -> ACTION parser, kept pure
/// (no Flutter imports) so `flutter test` can pin it without a device.
///
/// Understood (English, case-insensitive):
///   play / resume / start ................. play
///   pause / stop .......................... pause
///   replay / start over / from beginning .. jump to 0:00
///   go back / rewind (N seconds/minutes) .. rewind (default: seek step)
///   skip ahead / forward (N ...) .......... forward jump
///   go to / jump to / seek to N ........... absolute jump
///
/// Anything else (including "go back to when the speaker mentioned the
/// budget" - semantic search needs a transcript, and transcript Q&A was
/// removed in v95) returns null so the UI shows a hint instead of
/// guessing wrong.
enum VoicePlaybackAction { play, pause, back, forward, jumpTo }

class VoiceCommand {
  final VoicePlaybackAction action;

  /// back/forward: relative seconds. jumpTo: absolute seconds. Null when
  /// the user gave no number - the caller falls back to the seek-step
  /// setting (relative) or 0:00 (absolute).
  final int? seconds;

  const VoiceCommand(this.action, [this.seconds]);
}

/// Number words the parser understands next to a time unit.
const Map<String, int> _voiceNumbers = {
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
  'fifteen': 15,
  'twenty': 20,
  'thirty': 30,
  'forty': 40,
  'fifty': 50,
  'sixty': 60,
  'ninety': 90,
};

int _voiceNumberValue(String w) {
  final d = int.tryParse(w);
  if (d != null) return d;
  return _voiceNumbers[w] ?? -1;
}

final RegExp _voiceAmount = RegExp(
  r'(\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|'
  r'fifteen|twenty|thirty|forty|fifty|sixty|ninety)'
  r'\s*(hours?|hrs?|minutes?|mins?|seconds?|secs?|[hms])\b',
);

final RegExp _voiceBareNumber = RegExp(r'\b(\d{1,5})\b');

int _voiceUnitMultiplier(String unit) {
  final u = unit.toLowerCase();
  if (u.startsWith('h')) return 3600;
  if (u.startsWith('m')) return 60;
  return 1;
}

/// Seconds mentioned in [t], or null when there is no number at all.
/// A bare number ("back 10") counts as seconds.
int? _extractVoiceSeconds(String t) {
  final m = _voiceAmount.firstMatch(t);
  if (m != null) {
    final n = _voiceNumberValue(m.group(1)!);
    if (n < 0) return null;
    return n * _voiceUnitMultiplier(m.group(2)!);
  }
  final b = _voiceBareNumber.firstMatch(t);
  if (b != null) return int.tryParse(b.group(1)!);
  return null;
}

bool _hasVoiceWord(String t, String w) =>
    RegExp('\\b' + RegExp.escape(w) + '\\b').hasMatch(t);

/// Parses a recognized voice string into a player action, or null when the
/// text is not a command this player can execute.
VoiceCommand? parseVoiceCommand(String raw) {
  final t = raw.toLowerCase().trim();
  if (t.isEmpty) return null;

  // Absolute jumps first ("go to 12 minutes").
  if (t.contains('go to') ||
      t.contains('jump to') ||
      t.contains('seek to') ||
      t.contains('skip to')) {
    final s = _extractVoiceSeconds(t);
    if (s != null) return VoiceCommand(VoicePlaybackAction.jumpTo, s);
    if (t.contains('start') || t.contains('beginning')) {
      return const VoiceCommand(VoicePlaybackAction.jumpTo, 0);
    }
    return null;
  }
  // Restart from the top.
  if (t.contains('start over') ||
      t.contains('from the beginning') ||
      t.contains('from beginning') ||
      _hasVoiceWord(t, 'replay') ||
      _hasVoiceWord(t, 'restart')) {
    return const VoiceCommand(VoicePlaybackAction.jumpTo, 0);
  }
  // Transport.
  if (_hasVoiceWord(t, 'pause') ||
      _hasVoiceWord(t, 'stop') ||
      t.contains('stop playing') ||
      t.contains('stop the video')) {
    return const VoiceCommand(VoicePlaybackAction.pause);
  }
  if (_hasVoiceWord(t, 'play') ||
      t.contains('resume') ||
      t.contains('continue') ||
      _hasVoiceWord(t, 'start')) {
    return const VoiceCommand(VoicePlaybackAction.play);
  }
  // Relative rewind.
  if (t.contains('go back') ||
      t.contains('come back') ||
      t.contains('rewind') ||
      t.contains('backward') ||
      _hasVoiceWord(t, 'back')) {
    return VoiceCommand(VoicePlaybackAction.back, _extractVoiceSeconds(t));
  }
  // Relative forward.
  if (t.contains('forward') ||
      t.contains('ahead') ||
      _hasVoiceWord(t, 'skip')) {
    return VoiceCommand(VoicePlaybackAction.forward, _extractVoiceSeconds(t));
  }
  return null;
}
