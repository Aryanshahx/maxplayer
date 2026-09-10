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

/// One-shot chat completion against OpenRouter. Never throws; an
/// [AiResult.error] starting with 'config' means the API key isn't set
/// (add OPENROUTER_API_KEY to GitHub secrets).
Future<AiResult> askMovieAi(
    {required String systemPrompt, required String question}) async {
  if (AppConfig.openRouterKey.isEmpty) {
    return const AiResult(error: 'config:no-key');
  }
  try {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    final req = await client
        .postUrl(Uri.parse('https://openrouter.ai/api/v1/chat/completions'))
        .timeout(const Duration(seconds: 20));
    req.headers
      ..set('Authorization', 'Bearer ${AppConfig.openRouterKey}')
      ..set('Content-Type', 'application/json')
      ..set('HTTP-Referer', 'https://github.com/Aryanshahx/maxplayer')
      ..set('X-Title', 'Max Player');
    req.write(jsonEncode({
      'model': aiModel,
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
      return AiResult(error: 'Request failed (HTTP ${res.statusCode})');
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
    return const AiResult(error: 'Empty reply from the model');
  } catch (e) {
    CrashLog.error('ai.failed', e);
    return const AiResult(error: 'No internet or AI service unavailable');
  }
}
