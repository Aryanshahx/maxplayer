/// v1.0.1+18: media_kit forwards every mpv error-level log line to
/// `Player.stream.error` — including harmless command/property/filter
/// noise. The player treated ALL of them as fatal playback failures,
/// running the software-decode / UA-fallback ladder and finally showing
/// "This video can't be played by MPV". v16's volume boost used mpv `af`
/// commands, so ANY filter hiccup at >100% volume detonated playback.
/// This pure filter decides which errors deserve the recovery ladder.
bool looksLikeFatalMpvError(String message) {
  final m = message.toLowerCase();

  // Explicitly benign: client-command / property / filter-chain noise.
  // Never a playback failure — never worth a "recovery" that re-opens
  // (and restarts) the file.
  const benignNeedles = <String>[
    'filter',
    'lavfi',
    'alimiter',
    'acompressor',
    'af add',
    'af del',
    'af toggle',
    'option',
    'property',
    'command',
    'volume',
    'sub-add',
    'screenshot',
    'cycle',
    'set async',
  ];
  for (final b in benignNeedles) {
    if (m.contains(b)) return false;
  }

  const fatalNeedles = <String>[
    'failed',
    'error',
    'invalid',
    'unsupported',
    'cannot',
    'could not',
    'unreachable',
    'denied',
    'tcp:',
    'http',
    'forbidden',
    'not found',
    'no video',
    'no audio',
    'corrupt',
  ];
  for (final f in fatalNeedles) {
    if (m.contains(f)) return true;
  }

  // Unknown shape: keep the OLD behaviour (treat as fatal) so genuine,
  // oddly-worded engine failures still get the recovery ladder.
  return true;
}
