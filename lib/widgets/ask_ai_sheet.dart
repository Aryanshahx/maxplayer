import 'package:flutter/material.dart';

import '../services/movie_ai.dart';
import '../services/tmdb_client.dart';
import '../state/theme_state.dart';

/// v45: "Ask with AI" - a movie-restricted chat sheet powered by free
/// OpenRouter models (fallback chain, see MovieAiClient). The AI answers
/// ONLY movie questions; the sheet says so up front.
///
/// Uses the same DraggableScrollableSheet pattern as every other sheet
/// since v35, so it is landscape-safe and keyboard-safe.
class AskAiSheet extends StatefulWidget {
  final TmdbMovie movie;

  const AskAiSheet({super.key, required this.movie});

  static Future<void> show(BuildContext context, {required TmdbMovie movie}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        // keyboard pushes the sheet up instead of covering the field
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (_, controller) => SingleChildScrollView(
            controller: controller,
            child: AskAiSheet(movie: movie),
          ),
        ),
      ),
    );
  }

  @override
  State<AskAiSheet> createState() => _AskAiSheetState();
}

class _AskAiSheetState extends State<AskAiSheet> {
  final _client = MovieAiClient();
  final _questionCtrl = TextEditingController();

  bool _asking = false;
  String? _answer;
  String? _answerModel;
  String? _error;
  int _askToken = 0;

  @override
  void dispose() {
    _questionCtrl.dispose();
    super.dispose();
  }

  Future<void> _ask(String question) async {
    final q = question.trim();
    if (q.isEmpty || _asking) return;
    final token = ++_askToken;
    setState(() {
      _asking = true;
      _answer = null;
      _answerModel = null;
      _error = null;
    });
    final result = await _client.ask(movie: widget.movie, question: q);
    if (!mounted || token != _askToken) return;
    setState(() {
      _asking = false;
      if (result == null) {
        _error = kOpenRouterApiKey.isEmpty
            ? null // setup note is shown instead
            : 'No answer came back - the free AI models are busy right now. '
                'Please try again in a few seconds.';
      } else {
        _answer = result.text;
        _answerModel = result.model;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kOpenRouterApiKey.isEmpty) {
      return const _AiSetupNote();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.auto_awesome, color: themeState.accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ask AI about "${widget.movie.title}"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Movie questions only - the AI politely refuses anything else.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          // Preset templates: tap = ask instantly.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in kMovieAiTemplates)
                GestureDetector(
                  onTap: _asking ? null : () => _ask(t),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: themeState.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: themeState.accent.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      t,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _questionCtrl,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _ask,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Your own movie question...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: themeState.accent,
                  foregroundColor: themeState.onAccent,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
                onPressed: _asking ? null : () => _ask(_questionCtrl.text),
                child: _asking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Ask'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_asking)
            const Text(
              'Thinking... (tries up to 4 free AI models one by one)',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          if (_error != null)
            Text(
              _error!,
              style: const TextStyle(
                  color: Colors.orangeAccent, fontSize: 12, height: 1.4),
            ),
          if (_answer != null) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: SelectableText(
                  _answer!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Answer by ${_answerModel!.split('/').last.split(':').first} '
              'via OpenRouter',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shown when the OpenRouter key is not compiled in (local/dev builds).
class _AiSetupNote extends StatelessWidget {
  const _AiSetupNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome,
              size: 40, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          const Text(
            'Ask with AI starts in the store build.\n\n'
            '(Developer note: pass the OpenRouter key via\n'
            '--dart-define=OPENROUTER_API_KEY=... - a FREE key\n'
            'from openrouter.ai/keys, set as a Codemagic env var.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, height: 1.5),
          ),
        ],
      ),
    );
  }
}
