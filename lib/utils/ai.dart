import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'config.dart';
import 'crash_log.dart';

/// Free-tier chat model on OpenRouter; overridable via dart-define.
const aiModel = String.fromEnvironment(
  'OPENROUTER_MODEL',
  defaultValue: 'meta-llama/llama-3.3-70b-instruct:free',
);

/// Builds the system prompt for the Ask AI sheet about one movie.
String buildMovieSystemPrompt({
  required String title,
  required String year,
  required double rating,
  required String overview,
}) =>
    'You are the Ask-AI expert inside Max Player, a video app. '
    'Be concise, factual and friendly; keep answers under 150 words. '
    'Movie in question: "$title" ($year), TMDB rating '
    '${rating.toStringAsFixed(1)}/10. '
    'Synopsis: $overview';

class AiResult {
  const AiResult({this.text = '', this.error = ''});

  final String text;
  final String error;
  bool get ok => error.isEmpty && text.isNotEmpty;
}

/// Free-tier OpenRouter models, tried in order — the first one that answers
/// wins. This is what makes Ask AI resilient when a single free model is
/// down or rate-limited (the old app's exact failover chain).
const List<String> kAskAiModels = [
  'meta-llama/llama-3.3-70b-instruct:free',
  'google/gemini-2.0-flash-exp:free',
  'qwen/qwen-2.5-72b-instruct:free',
  'mistralai/mistral-7b-instruct:free',
  'deepseek/deepseek-r1:free',
  'deepseek/deepseek-chat:free',
  'openai/gpt-oss-20b:free',
  'google/gemma-4-26b-a4b-it:free',
];

/// One-shot chat completion against OpenRouter, walking the free-model
/// fallback chain. Never throws; an [AiResult.error] starting with 'config'
/// means the API key isn't set (add OPENROUTER_API_KEY to GitHub secrets).
Future<AiResult> askMovieAi(
    {required String systemPrompt, required String question}) async {
  if (AppConfig.openRouterKey.isEmpty) {
    return const AiResult(error: 'config:no-key');
  }
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);

  for (final model in kAskAiModels) {
    try {
      final req = await client
          .postUrl(Uri.parse('https://openrouter.ai/api/v1/chat/completions'))
          .timeout(const Duration(seconds: 20));
      req.headers
        ..set('Authorization', 'Bearer ${AppConfig.openRouterKey}')
        ..set('Content-Type', 'application/json')
        ..set('Referer', 'https://github.com/Aryanshahx/maxplayer')
        ..set('X-Title', 'Max Player');
      req.write(jsonEncode({
        'model': model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': question},
        ],
        'max_tokens': 400,
      }));
      final res = await req.close().timeout(const Duration(seconds: 30));
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        CrashLog.error('ai.http_${res.statusCode}', body.length);
        continue; // rate-limited / model down -> next in the chain
      }
      final decoded = jsonDecode(body);
      final choices = decoded is Map ? decoded['choices'] : null;
      if (choices is List && choices.isNotEmpty) {
        final msg = choices.first['message'];
        final content = msg is Map ? msg['content'] : null;
        if (content is String && content.trim().isNotEmpty) {
          return AiResult(text: content.trim());
        }
      }
    } catch (e) {
      CrashLog.error('ai.model_failed', {'model': model, 'error': '$e'});
      // network blip for this model -> try the next one
    }
  }
  return const AiResult(error: 'No internet or AI service unavailable');
}
