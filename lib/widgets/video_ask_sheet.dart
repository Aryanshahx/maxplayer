import 'dart:convert';
import 'package:flutter/material.dart';

import '../services/movie_ai.dart';
import '../services/native_bridge.dart';
import '../state/theme_state.dart';
import '../utils/srt.dart';

/// v65 A2: "Ask anything about THIS video". A chat sheet that answers
/// questions over the currently loaded video's OWN subtitles/AI captions
/// (the transcript), with timestamp citations. Tapping a cited (mm:ss)
/// seeks the player to that moment.
///
/// Different from the Discover "Ask with AI" sheet (which answers about a
/// TMDB movie's metadata): here the AI only knows what was said in the
/// video. If the video has no usable transcript, the sheet says so and
/// offers to generate AI subtitles first.
class VideoAskSheet extends StatefulWidget {
  final String title;
  final List<SrtCue> cues;

  /// Called when the user taps a "(mm:ss)" citation; seeks the player.
  final void Function(Duration at)? onSeek;

  const VideoAskSheet({
    super.key,
    required this.title,
    required this.cues,
    this.onSeek,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required List<SrtCue> cues,
    void Function(Duration at)? onSeek,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141c),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (_, controller) => VideoAskSheet(
            title: title,
            cues: cues,
            onSeek: onSeek,
          ),
        ),
      ),
    );
  }

  @override
  State<VideoAskSheet> createState() => _VideoAskSheetState();
}

class _VideoAskSheetState extends State<VideoAskSheet> {
  final _client = VideoAiClient();
  final _questionCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_Msg> _messages = [];
  bool _asking = false;
  int _askToken = 0;

  bool get _hasTranscript => VideoAiClient.hasUsableTranscript(widget.cues);

  @override
  void initState() {
    super.initState();
    _restoreHistory();
  }

  Future<void> _restoreHistory() async {
    final s = await NativeBridge.loadSettings();
    final jsonStr = s['video_ai_history_${widget.title.hashCode}'];
    if (jsonStr != null && jsonStr.isNotEmpty && mounted) {
      try {
        final list = jsonDecode(jsonStr) as List;
        setState(() {
          _messages.addAll(list.map((e) => _Msg._(
                e['who'] == 'user' ? _Who.user : _Who.ai,
                '${e['text']}',
              )));
        });
      } catch (_) {}
    }
  }

  void _persistHistory() {
    final jsonStr = jsonEncode(_messages
        .map((m) => {
              'who': m.who == _Who.user ? 'user' : 'ai',
              'text': m.text,
            })
        .toList());
    NativeBridge.saveSetting(
        'video_ai_history_${widget.title.hashCode}', jsonStr);
  }

  @override
  void dispose() {
    _questionCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _ask(String question) async {
    final q = question.trim();
    if (q.isEmpty || _asking) return;
    final token = ++_askToken;
    setState(() {
      _messages.add(_Msg.user(q));
      _asking = true;
    });
    _questionCtrl.clear();
    _scrollToBottom();
    final answer = await _client.ask(
      title: widget.title,
      cues: widget.cues,
      question: q,
    );
    if (!mounted || token != _askToken) return;
    setState(() {
      _asking = false;
      _messages.add(_Msg.ai(answer ?? _failedMessage()));
    });
    _persistHistory();
    _scrollToBottom();
  }

  String _failedMessage() =>
      "I couldn't reach the AI right now. Check your internet and try again.";

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Parses "(mm:ss)" / "(hh:mm:ss)" citations so they're tappable.
  static final RegExp _stampRe =
      RegExp(r'\((\d{1,2}):(\d{2})(?::(\d{2}))?\)');

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return Column(
      children: [
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ask about "${widget.title}"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white12, height: 1),
        if (!_hasTranscript)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(Icons.subtitles_off_outlined,
                    color: Colors.white38, size: 40),
                SizedBox(height: 10),
                Text(
                  'No spoken subtitles found for this video yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                SizedBox(height: 6),
                Text(
                  'Generate AI subtitles from the tracks (tune) button '
                  'first, then come back to ask about it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          )
        else
          Expanded(
            child: ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              children: [
                for (final m in _messages) _bubble(m, accent),
                if (_asking)
                  const _ThinkingDots(),
              ],
            ),
          ),
        if (_hasTranscript)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _questionCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _asking ? null : _ask,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Ask what happened, who said what…',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  onPressed: _asking
                      ? null
                      : () => _ask(_questionCtrl.text),
                  icon: const Icon(Icons.send, size: 18),
                  style: IconButton.styleFrom(backgroundColor: accent),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _bubble(_Msg m, Color accent) {
    final isUser = m.who == _Who.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? accent.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: isUser ? const Radius.circular(14) : Radius.zero,
            bottomRight: isUser ? Radius.zero : const Radius.circular(14),
          ),
        ),
        child: isUser
            ? SelectableText(
                m.text,
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
              )
            : _richAnswer(m.text, accent),
      ),
    );
  }

  /// Renders the AI answer with any "(mm:ss)" / "(hh:mm:ss)" timestamp
  /// turned into a tappable chip that seeks the player.
  Widget _richAnswer(String text, Color accent) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in _stampRe.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start)));
      }
      final g1 = int.parse(match.group(1)!);
      final g2 = int.parse(match.group(2)!);
      final g3 = match.group(3);
      final at = g3 == null
          ? Duration(minutes: g1, seconds: g2)
          : Duration(hours: g1, minutes: g2, seconds: int.parse(g3));
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: GestureDetector(
          onTap: widget.onSeek == null ? null : () => widget.onSeek!(at),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              match.group(0)!,
              style: TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ));
      last = match.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return SelectableText.rich(
      TextSpan(
        style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.35),
        children: spans,
      ),
    );
  }
}

enum _Who { user, ai }

class _Msg {
  final _Who who;
  final String text;
  _Msg._(this.who, this.text);
  factory _Msg.user(String t) => _Msg._(_Who.user, t);
  factory _Msg.ai(String t) => _Msg._(_Who.ai, t);
}

class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: accent, size: 16),
          const SizedBox(width: 8),
          Text(
            'Thinking…',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 10),
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final delay = i * 0.25;
                  final val = (_ctrl.value - delay) % 1.0;
                  final scale =
                      0.5 + 0.5 * (val < 0.5 ? val * 2 : (1 - val) * 2);
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 7,
                    height: 7,
                    transform: Matrix4.diagonal3Values(scale, scale, 1.0),
                    transformAlignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.3 + 0.7 * scale),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }
}
