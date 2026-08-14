import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import '../services/native_bridge.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import 'srt.dart';

/// True when a whisper segment is caption decoration rather than speech -
/// e.g. "♪", "♪ ♪", "[Music]", "(music playing)". Whisper emits these over
/// music-only stretches; dropping them keeps the .srt clean (v18).
///
/// Deliberately conservative: anything that might be real speech (even
/// speech ABOUT music, like "I love music") is kept - we only drop the
/// exact decoration phrases whisper hallucinates.
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

/// Lowercase, letters-only forms of whisper's music/SFX-only captions.
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

/// Runs the offline AI subtitle flow end to end and shows a progress dialog:
///
///   download model once (~142 MB) -> extract audio -> whisper.cpp ->
///   write "<video>.maxai.srt" next to the video -> load it into the player
///
/// Everything after the one-time model download is 100% offline & free.
class AiSubtitleRunner {
  AiSubtitleRunner._();

  /// Persisted picker defaults (native settings store).
  static const String _kModelKey = 'ai.model';
  static const String _kLanguageKey = 'ai.language';
  static const String _kTranslateKey = 'ai.translate';

  /// Model choices: id -> (label, detail with size). v25: tiny is gone for
  /// good (user call: keep only the accurate models). The SPEED upgrade now
  /// comes from the engine using every CPU core (threads), which makes even
  /// "Best" markedly faster without accuracy loss.
  static const Map<String, (String, String)> modelChoices = {
    'base': ('Balanced', '~142 MB · good for most videos'),
    'small': ('Best', '~466 MB · strongest on music & noise'),
  };

  /// Anything unknown (including a "tiny" id saved by v22-v24 builds)
  /// falls back to the default model.
  static String normalizeModelId(String? id) => id == 'small' ? 'small' : 'base';

  /// Language choices: whisper code -> label; 'auto' = detect.
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

    /// Approximate download size label per model (for the progress dialog).
  static String modelSizeLabel(String model) => switch (model) {
        'small' => '~466 MB',
        _ => '~142 MB',
      };

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

    // One active job at a time; hook up the event callbacks first.
    final progress = ValueNotifier<(String, int)>(('starting', 0));
    var dialogOpen = false;
    List<AiSegment>? segments;
    String? error;

    void closeDialog() {
      if (dialogOpen && context.mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: false).pop();
      }
    }

    NativeBridge.configureCallbacks(
      onAiProgress: (stage, percent) => progress.value = (stage, percent),
      onAiDone: (s) {
        segments = s;
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
      _snack(context, 'AI engine is not available in this build');
      return;
    }

    if (!context.mounted) return;
    dialogOpen = true;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _AiProgressDialog(
        progress: progress,
        model: options.model,
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
    if (error == 'cancelled' || segments == null) return;

    if (segments!.isEmpty) {
      _snack(context,
          'No speech was detected in this video - nothing to write');
      return;
    }

    // (mounted was checked right after the dialog closed above)

    // Build the .srt (pure function) and save it next to the video.
    // Music-only decoration captions ("♪", "[Music]") are filtered out.
    final cues = [
      for (final s in segments!)
        if (!isMusicOnlyCaption(s.text)) SrtCue(s.startMs, s.endMs, s.text),
    ];
    if (cues.isEmpty) {
      _snack(context,
          'Only background music was detected - no subtitles to write');
      return;
    }
    final srtPath = _srtPathFor(track.path);
    try {
      await File(srtPath).writeAsString(buildSrt(cues));
    } catch (_) {
      if (context.mounted) {
        _snack(context, 'Subtitles generated, but saving the file failed');
      }
      return;
    }
    if (!context.mounted) return;

    // Hand it to mpv so the subtitle picker lists it immediately, and let the
    // karaoke overlay / skip-intro chip pick up the fresh cues.
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

  static String _srtPathFor(String videoPath) {
    final dir = p.dirname(videoPath);
    final base = p.basenameWithoutExtension(videoPath);
    return p.join(dir, '$base.maxai.srt');
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

class _AiProgressDialog extends StatelessWidget {
  final ValueNotifier<(String, int)> progress;
  final String model;
  final VoidCallback onCancel;

  const _AiProgressDialog({
    required this.progress,
    required this.model,
    required this.onCancel,
  });

  static String _stageLabel(String stage, String model) {
    switch (stage) {
      case 'downloading':
        return 'Downloading the AI model (one time, '
            '${AiSubtitleRunner.modelSizeLabel(model)})…';
      case 'extracting':
        return 'Extracting audio from the video…';
      case 'transcribing':
        return 'Listening to the speech in this video…\n'
            '(silent parts are skipped automatically for speed)';
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
          const Text('AI subtitles', style: TextStyle(color: Colors.white)),
        ],
      ),
      content: ValueListenableBuilder<(String, int)>(
        valueListenable: progress,
        builder: (context, value, _) {
          final (stage, percent) = value;
          // "transcribing" became determinate in v18: Kotlin reports real
          // progress as speech spans finish.
          final determinate = stage == 'downloading' ||
              stage == 'extracting' ||
              stage == 'transcribing';
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _stageLabel(stage, model),
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

/// "Generate with AI" options: which whisper model (speed vs accuracy) and
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
          const Text('AI subtitles', style: TextStyle(color: Colors.white)),
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
            'AI model (quality)',
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
            onChanged: (v) => setState(() => _model = v ?? 'base'),
          ),
          const SizedBox(height: 16),
          const Text(
            'Output',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _modeChip(
                  label: 'Same language',
                  icon: Icons.record_voice_over_outlined,
                  selected: !_translate,
                  onTap: () => setState(() => _translate = false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _modeChip(
                  label: '→ English',
                  icon: Icons.translate,
                  selected: _translate,
                  onTap: () => setState(() => _translate = true),
                ),
              ),
            ],
          ),
          if (_translate)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Foreign speech becomes ENGLISH subtitles (AI translate).',
                style: TextStyle(color: Colors.white38, fontSize: 11.5),
              ),
            ),
          const SizedBox(height: 10),
          const Text(
            'Runs 100% offline after a one-time model download.',
            style: TextStyle(color: Colors.white38, fontSize: 11.5),
          ),
          const SizedBox(height: 4),
          const Text(
            'v25: the engine now uses all CPU cores - much faster than '
            'before. Tip: pinning the spoken language above (instead of '
            'Auto-detect) is quicker AND more accurate.',
            style: TextStyle(color: Colors.white38, fontSize: 11.5),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(
              (model: _model, language: _language, translate: _translate)),
          icon: const Icon(Icons.auto_awesome, size: 16),
          label: Text(_translate ? 'Translate' : 'Generate'),
        ),
      ],
    );
  }

  Widget _modeChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: selected
              ? themeState.accent.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? themeState.accent : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16, color: selected ? themeState.accent : Colors.white54),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          dropdownColor: const Color(0xFF26262f),
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ),
    );
  }
}
