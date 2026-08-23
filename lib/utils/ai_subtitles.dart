import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../services/movie_ai.dart' show kOpenRouterApiKey;
import '../services/native_bridge.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import 'srt.dart';

/// True when a transcription segment is caption decoration rather than
/// speech - e.g. "♪", "♪ ♪", "[Music]", "(music playing)". Whisper-class
/// engines emit these over music-only stretches; dropping them keeps the
/// .srt clean (v18).
///
/// Deliberately conservative: anything that might be real speech (even
/// speech ABOUT music, like "I love music") is kept - we only drop the
/// exact decoration phrases the engine hallucinates.
bool isMusicOnlyCaption(String text) {
  var t = text.toLowerCase().trim();
  if (t.isEmpty) return true;
  // Pure note decorations: "♪", "♪ ♫ ♪", ...
  t = t.replaceAll(RegExp(r'[♪♫𝄞𝄢]+'), ' ').trim();
  if (t.isEmpty) return true;
  // Reduce to letters only, then compare against known decorations.
  final core = t.replaceAll(RegExp(r'[^a-z]'), '');
  return _musicOnlyCores.contains(core);
}

/// Lowercase, letters-only forms of the engine's music/SFX-only captions.
const Set<String> _musicOnlyCores = {
  'music',
  'musicplaying',
  'playingmusic',
  'backgroundmusic',
  'upbeatmusic',
  'instrumentalmusic',
  'dramaticmusic',
  'intensemusic',
  'softmusic',
  'loudmusic',
  'slowmusic',
  'rockmusic',
  'popmusic',
  'classicalmusic',
  'sadmusic',
  'happymusic',
  'jazzmusic',
  'applause',
  'applauses',
  'clapping',
  'cheering',
  'laughter',
  'laughing',
  'crowdcheering',
  'silence',
};

/// Runs the CLOUD AI subtitle flow end to end and shows a progress dialog:
///
///   native audio extraction + speech gating (on device) -> speech-slice
///   WAV files on disk -> Dart uploads each slice to the OpenRouter cloud
///   (Gemini audio models, built-in key like the movie Q&A feature) ->
///   merge slices -> write "<video>.maxai.srt" next to the video -> load
///
/// v52 ROOT REBUILD: v48-v51 used a hidden WebView cloud whose sign-in
/// popup required a real user gesture and broke on real phones in five
/// different ways (overlay, transport, timeouts...). That whole
/// WebView/sign-in layer is DELETED. The new pipeline is pure HTTPS with
/// the same compile-time OPENROUTER_API_KEY that already powers the
/// movie-Q&A sheet - no sign-in, no popup, no WebView, nothing for the
/// viewer to set up. Only detected speech audio leaves the phone.
class AiSubtitleRunner {
  AiSubtitleRunner._();

  /// Persisted picker defaults (native settings store).
  static const String _kModelKey = 'ai.model';
  static const String _kLanguageKey = 'ai.language';
  static const String _kTranslateKey = 'ai.translate';

  /// Cloud quality tiers: id -> (label, detail).
  static const Map<String, (String, String)> modelChoices = {
    'fast': ('Fast · Flash-Lite', 'quick - great for clear speech'),
    'best': ('Best · Flash', 'strongest on music & noise'),
  };

  /// Anything unknown (including legacy "base"/"small" ids saved by older
  /// builds) falls back to the fast tier; an old "small" maps to "best".
  static String normalizeModelId(String? id) => switch (id) {
        'best' || 'small' => 'best',
        _ => 'fast',
      };

  /// v52: picker id -> primary OpenRouter audio model.
  static String cloudModelFor(String id) => id == 'best'
      ? 'google/gemini-2.5-flash'
      : 'google/gemini-2.5-flash-lite';

  /// Fallback chain per tier, tried IN ORDER - the first model that
  /// answers wins (rate limits / a retired model just move to the next).
  static List<String> cloudModelChain(String id) => id == 'best'
      ? const [
          'google/gemini-2.5-flash',
          'google/gemini-2.5-flash-lite',
          'google/gemini-2.0-flash-001',
        ]
      : const [
          'google/gemini-2.5-flash-lite',
          'google/gemini-2.0-flash-001',
          'google/gemini-2.0-flash-exp:free',
        ];

  /// Language choices: ISO-639 code -> label; 'auto' = detect.
  static const Map<String, String> languageChoices = {
    'auto': 'Auto-detect',
    'en': 'English',
    'hi': 'Hindi',
    'ur': 'Urdu',
    'ar': 'Arabic',
    'bn': 'Bengali',
    'ta': 'Tamil',
    'te': 'Telugu',
    'pa': 'Punjabi',
    'mr': 'Marathi',
    'gu': 'Gujarati',
    'kn': 'Kannada',
    'ml': 'Malayalam',
    'ne': 'Nepali',
    'es': 'Spanish',
    'fr': 'French',
  };

  /// Normalizes caption text for duplicate comparison across slice
  /// boundaries (Latin + Devanagari survive; punctuation/case dropped).
  static String _normCaption(String t) => t
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9؀-ॿ]+'), '');

  /// Merges per-slice .srt documents into absolute-timeline cues (PURE,
  /// unit-tested):
  ///  - each slice's cue times shift by its absolute start offset
  ///  - cues are sorted by start time
  ///  - music-only decoration captions are dropped ([isMusicOnlyCaption])
  ///  - boundary duplicates (same caption re-emitted inside the 3 s guard
  ///    band where two slices overlap) are dropped once
  static List<SrtCue> mergeChunkCues(List<(int offsetMs, String srt)> chunks) {
    final all = <SrtCue>[];
    for (final (offsetMs, doc) in chunks) {
      for (final c in parseSrt(doc)) {
        all.add(SrtCue(c.startMs + offsetMs, c.endMs + offsetMs, c.text));
      }
    }
    all.sort((a, b) => a.startMs.compareTo(b.startMs));
    final kept = <SrtCue>[];
    for (final c in all) {
      final text = c.text.trim();
      if (text.isEmpty) continue;
      if (isMusicOnlyCaption(text)) continue;
      final prev = kept.isEmpty ? null : kept.last;
      if (prev != null &&
          _normCaption(prev.text) == _normCaption(text) &&
          c.startMs - prev.startMs < 12000) {
        continue; // same caption re-emitted at a slice boundary
      }
      kept.add(SrtCue(c.startMs, c.endMs, text));
    }
    return kept;
  }

  // ------------------------------------------------------------------
  // v52 OpenRouter cloud client (PURE helpers, unit-tested)
  // ------------------------------------------------------------------

  /// Prompt sent with every audio slice. SRT-only output, clip-relative
  /// timestamps, music stretches answered with an empty reply.
  static String transcriptionPrompt({
    required String languageLabel,
    required bool translate,
  }) {
    final b = StringBuffer()
      ..write('Transcribe the speech in this audio clip into SubRip (SRT) '
          'subtitles.\nRules:\n')
      ..write('- Output ONLY the SRT cues: no commentary, no markdown '
          'code fences.\n')
      ..write('- Number cues starting at 1 and use "HH:MM:SS,mmm --> '
          'HH:MM:SS,mmm" timestamps relative to the CLIP start '
          '(00:00:00,000).\n')
      ..write('- Keep every cue under two lines and split long speech into '
          'short cues.\n');
    if (languageLabel == 'Auto-detect') {
      b.write('- Detect the spoken language automatically (it may mix '
          'Hindi, English and others).\n');
    } else {
      b.write('- The spoken language is $languageLabel.\n');
    }
    if (translate) {
      b.write('- Translate everything into natural English subtitle text '
          'instead of the original language.\n');
    } else {
      b.write('- Write the subtitles in the ORIGINAL spoken language and '
          'script.\n');
    }
    b.write('- For stretches of pure music or silence output nothing at '
        'all (an empty reply is correct).');
    return b.toString();
  }

  /// One OpenRouter chat-completions body carrying the audio clip.
  static Map<String, Object?> audioChatBody({
    required String model,
    required String prompt,
    required String base64Wav,
  }) =>
      {
        'model': model,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': prompt},
              {
                'type': 'input_audio',
                'input_audio': {'data': base64Wav, 'format': 'wav'},
              },
            ],
          },
        ],
        'max_tokens': 4096,
        'temperature': 0.0,
      };

  /// Extracts the assistant's text from a chat-completion response.
  /// Never throws; junk -> null.
  static String? parseChatText(String jsonBody) {
    try {
      final decoded = jsonDecode(jsonBody);
      if (decoded is! Map) return null;
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final first = choices.first;
      if (first is! Map) return null;
      final message = first['message'];
      if (message is! Map) return null;
      final content = '${message['content'] ?? ''}'.trim();
      return content.isEmpty ? null : content;
    } catch (_) {
      return null;
    }
  }

  /// Strips wrapping ``` / ```srt code fences some models add despite the
  /// instructions. No fences -> input unchanged.
  static String stripSrtFences(String text) {
    var t = text.trim();
    if (t.startsWith('```')) {
      final nl = t.indexOf('\n');
      if (nl > 0) t = t.substring(nl + 1);
      if (t.trimRight().endsWith('```')) {
        t = t.trimRight().substring(0, t.trimRight().length - 3);
      }
      t = t.trim();
    }
    return t;
  }

  /// Numeric error code from an OpenRouter error body, or null.
  static int? chatErrorCode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final err = decoded['error'];
      if (err is! Map) return null;
      final code = err['code'];
      if (code is int) return code;
      if (code is String) return int.tryParse(code);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Maps a cloud failure to words the viewer understands.
  static String aiCloudErrorMessage(int? code) {
    if (code == 401 || code == 403) {
      return 'the built-in AI key was rejected - please report this build';
    }
    if (code == 402) {
      return 'the AI service balance is empty right now - '
          'please try again later';
    }
    if (code == 404) {
      return 'this AI model is unavailable - try the other quality tier';
    }
    if (code == 408 || code == 429) {
      return 'the AI cloud is busy - please try again in a minute';
    }
    if (code != null && code >= 500) {
      return 'the AI cloud had a hiccup - please try again';
    }
    return 'check your internet connection and try again';
  }

  /// Launches generation for the video currently loaded in [player].
  /// [context] must be a context that outlives the subtitle sheet (the
  /// caller closes the sheet first).
  static Future<void> start(
    BuildContext context,
    MediaPlayerState player,
  ) async {
    final track = player.currentTrack;
    if (track == null || track.path.contains('://')) {
      _snack(context,
          'AI subtitles work on local video files (not network streams)');
      return;
    }
    if (kOpenRouterApiKey.isEmpty) {
      _snack(context, 'AI subtitles are not configured in this build');
      return;
    }

    // Ask for quality + language + output mode first (choices are remembered).
    final stored = await NativeBridge.loadSettings();
    if (!context.mounted) return;
    final options =
        await showDialog<({String model, String language, bool translate})>(
      context: context,
      builder: (_) => _AiOptionsDialog(
        initialModel: normalizeModelId(stored[_kModelKey]),
        initialLanguage: stored[_kLanguageKey] ?? 'auto',
        initialTranslate: stored[_kTranslateKey] == 'true',
      ),
    );
    if (options == null || !context.mounted) return;
    unawaited(NativeBridge.saveSetting(_kModelKey, options.model));
    unawaited(NativeBridge.saveSetting(_kLanguageKey, options.language));
    unawaited(NativeBridge.saveSetting(_kTranslateKey, '${options.translate}'));

    // v52: NO sign-in step - the key is compiled in, like movie Q&A.
    final progress = ValueNotifier<(String, int)>(('starting', 0));
    final chunks = <(int, String)>[];
    var dialogOpen = false;
    var cancelled = false;
    String? error;

    void closeDialog() {
      if (dialogOpen && context.mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: false).pop();
      }
    }

    NativeBridge.configureCallbacks(
      onAiProgress: (stage, percent) => progress.value = (stage, percent),
    );

    dialogOpen = true;
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _AiProgressDialog(
        progress: progress,
        onCancel: () {
          cancelled = true;
          unawaited(NativeBridge.aiSubtitleCancel());
          closeDialog();
        },
      ),
    ));

    var jobId = -1;
    try {
      // 1) on-device: extract + speech-gate + slice into ~3 min WAVs.
      final prep = await NativeBridge.aiPrepareSlices(track.path);
      jobId = prep.jobId;
      if (!context.mounted) return;
      if (prep.error != null) {
        if (prep.error == 'cancelled') {
          cancelled = true;
        } else {
          error = prep.error;
        }
      } else if (prep.slices.isEmpty) {
        closeDialog();
        _snack(context,
            'No speech was detected in this video - nothing to write');
        return;
      } else {
        // 2) upload each speech slice; the first model that answers wins.
        final prompt = transcriptionPrompt(
          languageLabel: languageChoices[options.language] ?? 'Auto-detect',
          translate: options.translate,
        );
        final total = prep.slices.length;
        for (var i = 0; i < total; i++) {
          if (cancelled) break;
          final slice = prep.slices[i];
          progress.value = ('transcribing', i * 100 ~/ total);
          try {
            final b64 = base64Encode(await File(slice.path).readAsBytes());
            String? srt;
            int? lastCode;
            for (final model in cloudModelChain(options.model)) {
              var moveOn = false;
              for (var attempt = 0; attempt < 2 && !moveOn; attempt++) {
                if (cancelled) break;
                try {
                  final (code, body) = await _CloudSpeech.transcribeOnce(
                    model: model,
                    prompt: prompt,
                    base64Wav: b64,
                  );
                  if (code == 200) {
                    final t = parseChatText(body);
                    if (t != null) {
                      srt = stripSrtFences(t);
                      moveOn = true;
                    }
                  } else {
                    lastCode = chatErrorCode(body) ?? code;
                    // Busy/server hiccup -> wait and retry once; anything
                    // else -> try the next model in the chain.
                    if (code == 429 || code >= 500) {
                      await Future<void>.delayed(const Duration(seconds: 3));
                    } else {
                      moveOn = true;
                    }
                  }
                } catch (_) {
                  await Future<void>.delayed(const Duration(seconds: 2));
                }
              }
              if (srt != null || cancelled) break;
            }
            if (cancelled) break;
            if (srt == null) {
              error = aiCloudErrorMessage(lastCode);
              break;
            }
            if (srt.trim().isNotEmpty) chunks.add((slice.offsetMs, srt));
          } finally {
            try {
              await File(slice.path).delete();
            } catch (_) {}
          }
        }
        progress.value = ('transcribing', 100);
      }
    } finally {
      unawaited(NativeBridge.aiSliceDiscard(jobId));
    }

    if (!context.mounted) return;
    closeDialog();

    if (cancelled) return;
    if (error != null) {
      _snack(context, 'AI subtitles failed: $error');
      return;
    }

    final cues = mergeChunkCues(chunks);
    if (cues.isEmpty) {
      _snack(context, 'The cloud heard no speech in this video');
      return;
    }

    // Build the .srt (pure function) and save it next to the video.
    final srtPath = srtPathForVideo(track.path);
    try {
      await File(srtPath).writeAsString(buildSrt(cues));
    } catch (_) {
      if (context.mounted) {
        _snack(context, 'Subtitles generated, but saving the file failed');
      }
      return;
    }
    if (!context.mounted) return;

    // Hand it to mpv so the subtitle picker lists it immediately, and let
    // the karaoke overlay / skip-intro chip pick up the fresh cues.
    final platform = player.player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.command(['sub-add', srtPath]);
      } catch (_) {}
    }
    await player.refreshAiCues(track.path);
    if (context.mounted) {
      _snack(context, '✨ AI subtitles ready - pick them in the subtitle list');
    }
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Tiny OpenRouter uploader: plain dart:io, one keep-alive connection,
/// generous read timeout for long audio clips (v52).
class _CloudSpeech {
  static const String _url = 'https://openrouter.ai/api/v1/chat/completions';

  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 25)
    ..idleTimeout = const Duration(seconds: 30);

  /// One upload attempt -> (HTTP status, response body).
  static Future<(int, String)> transcribeOnce({
    required String model,
    required String prompt,
    required String base64Wav,
  }) async {
    final req = await _http.postUrl(Uri.parse(_url));
    req.headers.set('content-type', 'application/json');
    req.headers.set('authorization', 'Bearer $kOpenRouterApiKey');
    req.headers.set('x-title', 'Max Player');
    req.write(jsonEncode(AiSubtitleRunner.audioChatBody(
      model: model,
      prompt: prompt,
      base64Wav: base64Wav,
    )));
    final res = await req.close().timeout(const Duration(seconds: 180));
    final body = await res.transform(utf8.decoder).join();
    return (res.statusCode, body);
  }
}

class _AiProgressDialog extends StatelessWidget {
  final ValueNotifier<(String, int)> progress;
  final VoidCallback onCancel;

  const _AiProgressDialog({
    required this.progress,
    required this.onCancel,
  });

  static String _stageLabel(String stage) {
    switch (stage) {
      case 'extracting':
        return 'Extracting audio from the video (on device)…';
      case 'slicing':
        return 'Keeping only the speech parts (silent parts are skipped)…';
      case 'transcribing':
        return 'Listening in the AI cloud - only speech is uploaded…';
      default:
        return 'Preparing…';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1a1a24),
      title: Row(
        children: [
          Icon(Icons.auto_awesome, color: themeState.accent, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('AI subtitles · cloud',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
      content: ValueListenableBuilder<(String, int)>(
        valueListenable: progress,
        builder: (context, value, _) {
          final (stage, percent) = value;
          final determinate = stage != 'starting';
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _stageLabel(stage),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: determinate ? percent / 100 : null,
                color: themeState.accent,
                backgroundColor: Colors.white10,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 8),
              Text(
                determinate ? '$percent%' : ' ',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// "Generate with AI" options: cloud quality tier (speed vs accuracy) and
/// which language the video is spoken in (auto-detect or pinned). Choosing
/// the right language is the single biggest accuracy boost on short clips.
class _AiOptionsDialog extends StatefulWidget {
  final String initialModel;
  final String initialLanguage;
  final bool initialTranslate;

  const _AiOptionsDialog({
    required this.initialModel,
    required this.initialLanguage,
    required this.initialTranslate,
  });

  @override
  State<_AiOptionsDialog> createState() => _AiOptionsDialogState();
}

class _AiOptionsDialogState extends State<_AiOptionsDialog> {
  late String _model = widget.initialModel;
  late String _language = widget.initialLanguage;
  late bool _translate = widget.initialTranslate;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1a1a24),
      title: Row(
        children: [
          Icon(Icons.auto_awesome, color: themeState.accent, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('AI subtitles · cloud',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Spoken language',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          _dropdown<String>(
            value: _language,
            items: [
              for (final e in AiSubtitleRunner.languageChoices.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _language = v ?? 'auto'),
          ),
          const SizedBox(height: 16),
          const Text(
            'Quality (cloud AI)',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          _dropdown<String>(
            value: _model,
            items: [
              for (final e in AiSubtitleRunner.modelChoices.entries)
                DropdownMenuItem(
                  value: e.key,
                  child: Text('${e.value.$1}  ·  ${e.value.$2}'),
                ),
            ],
            onChanged: (v) =>
                setState(() => _model = AiSubtitleRunner.normalizeModelId(v)),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            value: _translate,
            onChanged: (v) => setState(() => _translate = v),
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeThumbColor: themeState.accent,
            title: const Text('Translate to English',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            subtitle: const Text('Any spoken language -> English subtitles',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(
            context,
            (model: _model, language: _language, translate: _translate),
          ),
          style: FilledButton.styleFrom(backgroundColor: themeState.accent),
          icon: Icon(Icons.cloud_done_outlined,
              size: 16, color: themeState.onAccent),
          label: Text('Generate',
              style: TextStyle(color: themeState.onAccent)),
        ),
      ],
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          dropdownColor: const Color(0xFF26262f),
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
    );
  }
}
