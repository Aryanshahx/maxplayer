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
  const AiResult(
      {this.text = '', this.error = '', this.local = false, this.reason = ''});

  final String text;
  final String error;

  /// True when the answer came from the offline rule-based engine
  /// ([smartLocalMovieAnswer]) rather than an OpenRouter model.
  final bool local;

  /// v1.0.2: WHY the online chain was skipped/failed when [local] is true
  /// ('no-key' | 'offline' | 'http-401' | 'http-402' | 'http-429' | ...).
  /// The sheet turns this into a HONEST one-line diagnosis instead of the
  /// old everything-is-"no key or no internet" lie.
  final String reason;
  bool get ok => error.isEmpty && text.isNotEmpty;
}

/// Pure diagnosis of why the OpenRouter chain produced no answer
/// (unit-tested). [httpStatuses] = status codes collected across models.
String aiFallbackReason({
  required bool keyEmpty,
  required List<int> httpStatuses,
  required int exceptionCount,
}) {
  if (keyEmpty) return 'no-key';
  // Not a single server answer: DNS/socket/timeout everywhere -> offline.
  if (httpStatuses.isEmpty) return 'offline';
  // An answered status beats guesswork; common cases first.
  if (httpStatuses.contains(401)) return 'http-401';
  if (httpStatuses.contains(402)) return 'http-402';
  if (httpStatuses.contains(429)) return 'http-429';
  return 'http-${httpStatuses.first}';
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
///
/// When there is no key, or the network/models are all down, this falls back
/// to a rule-based local answer built from the movie's own TMDB data
/// ([smartLocalMovieAnswer]) — the old app's exact behaviour — so offline /
/// keyless users always get a real answer instead of
/// "No internet or AI service unavailable".
Future<AiResult> askMovieAi({
  required String systemPrompt,
  required String question,
  String movieTitle = '',
  int? movieYear,
  double movieRating = 0,
  String movieOverview = '',
}) async {
  final keyEmpty = AppConfig.openRouterKey.isEmpty;
  if (keyEmpty) {
    CrashLog.crumb('ai.skipped_no_key');
    return AiResult(
      local: true,
      reason: aiFallbackReason(
          keyEmpty: true, httpStatuses: const [], exceptionCount: 0),
      text: smartLocalMovieAnswer(
        title: movieTitle,
        year: movieYear,
        rating: movieRating,
        overview: movieOverview,
        question: question,
      ),
    );
  }
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);
  final httpStatuses = <int>[];
  var exceptionCount = 0;

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
        httpStatuses.add(res.statusCode);
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
      exceptionCount++;
      CrashLog.error('ai.model_failed', {'model': model, 'error': '$e'});
      // network blip for this model -> try the next one
    }
  }
  // Every model failed or the phone is offline -> rule-based local answer.
  final reason = aiFallbackReason(
      keyEmpty: false,
      httpStatuses: httpStatuses,
      exceptionCount: exceptionCount);
  CrashLog.crumb('ai.fallback_local', {
    'reason': reason,
    'statuses': httpStatuses,
    'exceptions': exceptionCount,
  });
  return AiResult(
    local: true,
    reason: reason,
    text: smartLocalMovieAnswer(
      title: movieTitle,
      year: movieYear,
      rating: movieRating,
      overview: movieOverview,
      question: question,
    ),
  );
}

/// Rule-based, fully-offline movie answer built from the movie's own TMDB
/// fields — ported from the old app's `_smartLocalMovieAnswer`. Covers the
/// template chips and common free-text phrasings (worth-watching, plot,
/// similar, facts, ending, cast, rating) and always returns something
/// sensible.
String smartLocalMovieAnswer({
  required String title,
  required int? year,
  required double rating,
  required String overview,
  required String question,
}) {
  final q = question.toLowerCase().trim();
  final titleYear = year != null ? ' ($year)' : '';
  final shown = '$title$titleYear';
  final score = rating > 0 ? rating.toStringAsFixed(1) : '7.5';
  final story = overview.trim();

  if (q.contains('worth watching') ||
      q.contains('good') ||
      q.contains('review') ||
      q.contains('recommend') ||
      q.contains('should i watch')) {
    if (rating >= 7.5) {
      return '$shown is definitely worth watching! It holds a strong '
          '$score/10 rating on TMDB, with praise for its engaging '
          'storytelling, standout performances, and high production value.'
          '${story.isNotEmpty ? "\n\nStory premise: $story" : ""}';
    } else if (rating >= 6.0) {
      return '$shown is an enjoyable watch with a $score/10 rating on TMDB. '
          'It delivers fun moments and great scenes for fans of the genre.'
          '${story.isNotEmpty ? "\n\nPremise: $story" : ""}';
    } else {
      return '$shown has a $score/10 score on TMDB. It offers casual '
          'entertainment with memorable highlights.'
          '${story.isNotEmpty ? "\n\nStory: $story" : ""}';
    }
  }

  if (q.contains('3 lines') ||
      q.contains('explain') ||
      q.contains('story') ||
      q.contains('plot') ||
      q.contains('summary') ||
      q.contains('about')) {
    if (story.isNotEmpty) {
      final sentences = story.split(RegExp(r'(?<=[.!?])\s+'));
      if (sentences.length >= 3) return sentences.take(3).join(' ');
      return story;
    }
    return '$shown follows an engaging storyline filled with dramatic '
        'moments and character conflicts. The narrative explores compelling '
        'themes and keeps viewers hooked until the climax.';
  }

  if (q.contains('like this') ||
      q.contains('similar') ||
      q.contains('recommendation') ||
      q.contains('suggestion')) {
    return 'If you enjoyed $shown, check out acclaimed titles in the same '
        'genre that share its visual style, tone, and pacing. You can browse '
        'hand-picked related titles right under the details section!';
  }

  if (q.contains('fact') ||
      q.contains('trivia') ||
      q.contains('behind the scene')) {
    return 'Key facts about $shown:\n'
        '• Community Rating: ⭐ $score/10 on TMDB.\n'
        '• Released: ${year ?? "International distribution"}.\n'
        '• Celebrated for its unique narrative style and dedicated fanbase.';
  }

  if (q.contains('ending') ||
      q.contains('climax') ||
      q.contains('twist') ||
      q.contains('spoiler')) {
    return 'Without spoiling major plot twists: $shown builds towards a '
        'dramatic climax where central conflicts reach a decisive '
        'resolution, delivering emotional closure for the main characters.';
  }

  if (q.contains('director') ||
      q.contains('cast') ||
      q.contains('actor') ||
      q.contains('star') ||
      q.contains('who is in')) {
    return '$shown features a talented ensemble cast and creative direction. '
        'Check the Top Cast slider in the detail sheet to view all actor '
        'profile photos and character names!';
  }

  if (q.contains('rating') ||
      q.contains('score') ||
      q.contains('imdb') ||
      q.contains('tmdb')) {
    return '$shown has an audience rating of ⭐ $score/10 based on TMDB user '
        'reviews.';
  }

  if (story.isNotEmpty) {
    return '$shown ($score/10):\n\n$story\n\nFor more specific questions '
        'about characters, ending, or trivia, tap one of the template chips '
        'above!';
  }
  return '$shown is featured on TMDB with a community rating of '
      '⭐ $score/10.';
}
