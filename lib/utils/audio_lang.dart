/// Preferred-audio-language support (v1.0.1+18).
///
/// Player Settings lets the user pick a preferred audio language; when a
/// multi-audio video opens, the matching track is selected automatically
/// (matching by ISO 639-2 language tag, ISO 639-1 tag, or a language-name
/// substring inside the track title). Manual switching stays available in
/// the player's Audio-track picker.
class AudioLangOption {
  const AudioLangOption(this.code, this.label, this.aliases);

  /// Stored preference value: `auto` or an ISO 639-1 code (hi, en, ...).
  final String code;

  /// Human label shown in settings and the player.
  final String label;

  /// ISO 639-2/T codes + lowercase language-name fragments matched
  /// against the track's `language` tag and `title`.
  final List<String> aliases;
}

/// Preference choices — India-first order, then common international.
const kAudioLangOptions = <AudioLangOption>[
  AudioLangOption('auto', 'Auto (file default)', []),
  AudioLangOption('hi', 'Hindi', ['hin', 'hindi']),
  AudioLangOption('en', 'English', ['eng', 'english']),
  AudioLangOption('ta', 'Tamil', ['tam', 'tamil']),
  AudioLangOption('te', 'Telugu', ['tel', 'telugu']),
  AudioLangOption('ml', 'Malayalam', ['mal', 'malayalam']),
  AudioLangOption('kn', 'Kannada', ['kan', 'kannada']),
  AudioLangOption('bn', 'Bengali', ['ben', 'bengali', 'bangla']),
  AudioLangOption('mr', 'Marathi', ['mar', 'marathi']),
  AudioLangOption('pa', 'Punjabi', ['pan', 'punjabi']),
  AudioLangOption('gu', 'Gujarati', ['guj', 'gujarati']),
  AudioLangOption('ur', 'Urdu', ['urd', 'urdu']),
  AudioLangOption('ja', 'Japanese', ['jpn', 'japanese']),
  AudioLangOption('ko', 'Korean', ['kor', 'korean']),
  AudioLangOption('zh', 'Chinese', ['zho', 'chi', 'chinese', 'mandarin']),
  AudioLangOption('es', 'Spanish', ['spa', 'spanish']),
  AudioLangOption('fr', 'French', ['fra', 'fre', 'french']),
  AudioLangOption('de', 'German', ['deu', 'ger', 'german', 'deutsch']),
  AudioLangOption('ru', 'Russian', ['rus', 'russian']),
];

AudioLangOption audioLangOptionFor(String code) {
  for (final o in kAudioLangOptions) {
    if (o.code == code) return o;
  }
  return kAudioLangOptions.first; // 'auto'
}

/// Index of the first track matching [prefCode] — by ISO tag, ISO 639-1
/// tag, or label substring in title/language. -1 = no match (or `auto`).
int matchAudioTrackIndex(
  List<({String? title, String? language})> tracks,
  String prefCode,
) {
  final opt = audioLangOptionFor(prefCode);
  if (opt.code == 'auto') return -1;
  for (var i = 0; i < tracks.length; i++) {
    final lang = (tracks[i].language ?? '').toLowerCase().trim();
    final title = (tracks[i].title ?? '').toLowerCase();
    if (lang == opt.code) return i;
    for (final alias in opt.aliases) {
      if (lang == alias || lang.startsWith(alias) || title.contains(alias)) {
        return i;
      }
    }
  }
  return -1;
}
