import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';
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

/// One whisper.cpp segment (start/end in ms + text).
class AiSegment {
  final int startMs;
  final int endMs;
  final String text;
  const AiSegment(this.startMs, this.endMs, this.text);
}

/// Runs the offline AI subtitle flow end to end and shows a progress dialog:
///
///   download model once (~142 MB) -> extract audio -> whisper.cpp ->
///   write "<video>.maxai.srt" next to the video -> load it into the player
///
/// Everything after the one-time model download is 100% offline & free.
/// The player screen's single native method-call handler forwards the
/// `onAiProgress` / `onAiSubtitleDone` / `onAiSubtitleFailed` events here
/// via [handleNativeEvent] (one job at a time).
class AiSubtitleRunner {
  AiSubtitleRunner._();

  static const MethodChannel _channel = MethodChannel('maxplayer/native');

  /// Persisted picker defaults.
  static const String _kModelKey = 'ai.model';
  static const String _kLanguageKey = 'ai.language';
  static const String _kTranslateKey = 'ai.translate';

  /// Model choices: id -> (label, detail with size). v25: tiny is gone for
  /// good (user call: keep only the accurate models). Speed comes from the
  /// engine using every CPU core (threads).
  static const Map<String, (String, String)> modelChoices = {
    'base': ('Balanced', '~142 MB · good for most videos'),
    'small': ('Best', '~466 MB · strongest on music & noise'),
  };

  /// Anything unknown (including a "tiny" id saved by older builds)
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

  // ---- active-job state (one job at a time) ----

  static ValueNotifier<(String, int)>? _progress;
  static List<AiSegment>? _segments;
  static String? _error;
  static void Function()? _onDone;
  static void Function()? _onFailed;

  /// Routes native whisper events from the player screen's method-call
  /// handler into the active job (no-op when nothing is running).
  static void handleNativeEvent(MethodCall call) {
    switch (call.method) {
      case 'onAiProgress':
        final m = _asMap(call.arguments);
        final stage = '${m['stage'] ?? 'transcribing'}';
        final percent = (m['percent'] as num?)?.toInt() ?? 0;
        _progress?.value = (stage, percent);
        break;
      case 'onAiSubtitleDone':
        final m = _asMap(call.arguments);
        final raw = m['segments'];
        final list = <AiSegment>[];
        if (raw is List) {
          for (final s in raw) {
            if (s is! Map) continue;
            final start = (s['start'] as num?)?.toInt() ?? 0;
            final end = (s['end'] as num?)?.toInt() ?? 0;
            final text = '${s['text'] ?? ''}'.trim();
            if (text.isEmpty) continue;
            list.add(AiSegment(start, end, text));
          }
        }
        _segments = list;
        _onDone?.call();
        break;
      case 'onAiSubtitleFailed':
        final m = _asMap(call.arguments);
        _error = '${m['message'] ?? 'AI subtitle generation failed'}';
        _onFailed?.call();
        break;
    }
  }

  static Map<Object?, Object?> _asMap(Object? a) =>
      a is Map ? a.cast<Object?, Object?>() : const {};

  /// Launches generation for the video at [path] (currently playing).
  static Future<void> start({
    required BuildContext context,
    required String path,
    required String title,
    required bool isStream,
    required Player player,
  }) async {
    if (isStream || path.contains('://')) {
      _snack(context,
          'AI subtitles work on local video files (not network streams)');
      return;
    }

    // Ask for quality + language + output mode first (choices remembered).
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;
    final options = await showDialog<({String model, String language, bool translate})>(
      context: context,
      builder: (_) => _AiOptionsDialog(
        initialModel: normalizeModelId(prefs.getString(_kModelKey)),
        initialLanguage: prefs.getString(_kLanguageKey) ?? 'auto',
        initialTranslate: prefs.getString(_kTranslateKey) == 'true',
      ),
    );
    if (options == null || !context.mounted) return;
    unawaited(prefs.setString(_kModelKey, options.model));
    unawaited(prefs.setString(_kLanguageKey, options.language));
    unawaited(prefs.setString(_kTranslateKey, '${options.translate}'));

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

    _progress = progress;
    _segments = null;
    _error = null;
    _onDone = () {
      segments = _segments;
      closeDialog();
    };
    _onFailed = () {
      error = _error;
      closeDialog();
    };

    try {
      final jobId = await _channel.invokeMethod<int>('aiSubtitleGenerate', {
        'videoPath': path,
        'model': options.model,
        'language': options.language,
        'translate': options.translate,
      });
      if (!context.mounted) return;
      if (jobId == null) {
        _snack(
          context,
          'AI subtitles are not available on this phone '
          '(they need a 64-bit chip)',
        );
        return;
      }

      dialogOpen = true;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _AiProgressDialog(
          progress: progress,
          model: options.model,
          onCancel: () {
            error = 'cancelled';
            unawaited(_channel.invokeMethod('aiSubtitleCancel'));
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
      if (error == 'cancelled') return;
      if (segments == null || segments!.isEmpty) {
        _snack(context,
            'No speech was detected in this video - nothing to write');
        return;
      }

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
      final srtPath = srtPathForVideo(path);
      try {
        await File(srtPath).writeAsString(buildSrt(cues));
      } catch (_) {
        if (context.mounted) {
          _snack(context, 'Subtitles generated, but saving the file failed');
        }
        return;
      }
      if (!context.mounted) return;

      // Hand it to mpv so the subtitle picker lists it immediately.
      try {
        final platform = player.platform;
        if (platform != null) {
          await (platform as dynamic).command(['sub-add', srtPath]);
        }
      } catch (_) {}
      if (context.mounted) {
        _snack(context, 'AI subtitles ready - pick them in the subtitle list');
      }
    } finally {
      _progress = null;
      _segments = null;
      _error = null;
      _onDone = null;
      _onFailed = null;
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
      scrollable: true,
      backgroundColor: const Color(0xFF1a1a24),
      title: Row(
        children: [
          Icon(Icons.auto_awesome, color: AppColors.accent, size: 20),
          const SizedBox(width: 8),
          const Text('AI subtitles', style: TextStyle(color: Colors.white)),
        ],
      ),
      content: ValueListenableBuilder<(String, int)>(
        valueListenable: progress,
        builder: (context, value, _) {
          final (stage, percent) = value;
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
                color: AppColors.accent,
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
/// which language the video is spoken in (auto-detect or pinned).
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
      scrollable: true,
      backgroundColor: const Color(0xFF1a1a24),
      title: Row(
        children: [
          Icon(Icons.auto_awesome, color: AppColors.accent, size: 20),
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
            'Tip: pinning the spoken language above (instead of '
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
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.onAccent,
          ),
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
              ? AppColors.accent.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: selected ? AppColors.accent : Colors.white54),
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
