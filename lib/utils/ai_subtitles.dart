import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

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

/// Runs the CLOUD AI subtitle flow end to end (v48) and shows a progress
/// dialog:
///
///   one-time free Puter sign-in (silent temp account when possible) ->
///   native audio extraction + speech gating (on device) -> Puter cloud
///   transcription per speech slice -> merge slices -> write
///   "<video>.maxai.srt" next to the video -> load it into the player
///
/// vs the old on-device engine (v25-v47): NO 142-466 MB model download, NO
/// 64-bit restriction, and noticeably better CJK/Hinglish handling - the
/// only speech audio travels to the user's own (free) Puter account.
class AiSubtitleRunner {
  AiSubtitleRunner._();

  /// Persisted picker defaults (native settings store).
  static const String _kModelKey = 'ai.model';
  static const String _kLanguageKey = 'ai.language';
  static const String _kTranslateKey = 'ai.translate';

  /// Cloud model choices: id -> (label, detail). v48: the ids changed from
  /// on-device builds (base/small) to cloud tiers; old saved ids map onto
  /// the new ones via [normalizeModelId].
  static const Map<String, (String, String)> modelChoices = {
    'fast': ('Fast · gpt-4o-mini', 'quick - great for clear speech'),
    'best': ('Best · gpt-4o', 'strongest on music & noise'),
  };

  /// Anything unknown (including "base"/"tiny" ids saved by older builds)
  /// falls back to the fast model; an old "small" maps to "best".
  static String normalizeModelId(String? id) => switch (id) {
        'best' || 'small' => 'best',
        _ => 'fast',
      };

  /// Maps a picker id to the actual Puter speech2txt model name.
  static String cloudModelFor(String id) =>
      id == 'best' ? 'gpt-4o-transcribe' : 'gpt-4o-mini-transcribe';

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

    // v48: one-time Puter sign-in. The bridge loads lazily here; a silent
    // temp account covers most users, otherwise Puter's popup shows once
    // and the session persists afterwards.
    var status = await NativeBridge.puterStatus();
    if (!context.mounted) return;
    if (status['signedIn'] != true) {
      final go = await showDialog<bool>(
        context: context,
        builder: (_) => const _PuterIntroDialog(),
      );
      if (go != true || !context.mounted) return;
      final res = await NativeBridge.puterSignIn();
      if (!context.mounted) return;
      if (res['signedIn'] != true) {
        _snack(
          context,
          'Sign-in was cancelled - AI subtitles need the free Puter '
          'account (one time only)',
        );
        return;
      }
    }

    // One active job at a time; hook up the event callbacks first.
    final progress = ValueNotifier<(String, int)>(('starting', 0));
    final chunks = <(int, String)>[];
    var dialogOpen = false;
    var done = false;
    String? error;

    void closeDialog() {
      if (dialogOpen && context.mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: false).pop();
      }
    }

    NativeBridge.configureCallbacks(
      onAiProgress: (stage, percent) => progress.value = (stage, percent),
      onAiChunk: (offsetMs, srt) {
        if (srt.trim().isNotEmpty) chunks.add((offsetMs, srt));
      },
      onAiDone: (_) {
        done = true;
        closeDialog();
      },
      onAiFailed: (e) {
        error = e;
        closeDialog();
      },
    );

    final jobId = await NativeBridge.aiSubtitleGenerate(
      videoPath: track.path,
      model: options.model,
      language: options.language,
      translate: options.translate,
    );
    if (!context.mounted) return;
    if (jobId == null) {
      _snack(
        context,
        'AI subtitles could not start on this phone - they need internet '
        'and Android System WebView',
      );
      return;
    }

    if (!context.mounted) return;
    dialogOpen = true;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _AiProgressDialog(
        progress: progress,
        onCancel: () {
          error = 'cancelled';
          NativeBridge.aiSubtitleCancel();
          closeDialog();
        },
      ),
    );
    dialogOpen = false;

    if (!context.mounted) return;

    if (error != null && error != 'cancelled') {
      _snack(context, 'AI subtitles failed: $error');
      return;
    }
    if (error == 'cancelled' || !done) return;

    final cues = mergeChunkCues(chunks);
    if (cues.isEmpty) {
      _snack(context,
          'No speech was detected in this video - nothing to write');
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

/// Shown the FIRST time someone taps Generate (when no Puter session exists
/// yet). Explains the switch to the cloud honestly: what leaves the phone
/// (speech audio only) and who pays (the user's own free Puter account).
class _PuterIntroDialog extends StatelessWidget {
  const _PuterIntroDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1a1a24),
      title: Row(
        children: [
          Icon(Icons.cloud_outlined, color: themeState.accent, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('One-time free setup',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      content: const Text(
        'AI subtitles now run in the Puter cloud - nothing to download and '
        'every phone is supported (32-bit too).\n\n'
        'First use needs a quick Puter sign-in. A temporary account is '
        'created automatically - no email, no password, no card. Your usage '
        'is covered by your own free Puter account.\n\n'
        'Only the speech parts of the audio leave your phone, straight to '
        'your Puter session. You can sign out any time from Settings.',
        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(backgroundColor: themeState.accent),
          child: Text('Continue',
              style: TextStyle(color: themeState.onAccent)),
        ),
      ],
    );
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
      case 'transcribing':
        return 'Listening in the Puter cloud - only speech is uploaded…\n'
            '(silent parts are skipped for speed)';
      case 'downloading':
        // Legacy stage id - nothing is downloaded in the cloud flow.
        return 'Contacting the Puter cloud…';
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
            child: Text('AI subtitles · Puter cloud',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
      content: ValueListenableBuilder<(String, int)>(
        valueListenable: progress,
        builder: (context, value, _) {
          final (stage, percent) = value;
          final determinate =
              stage == 'extracting' || stage == 'transcribing';
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
            child: Text('AI subtitles · Puter cloud',
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
