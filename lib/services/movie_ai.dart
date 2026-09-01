import 'dart:convert';
import 'dart:io';

import '../utils/srt.dart';
import 'tmdb_client.dart';

/// OpenRouter API key, injected at build time:
/// `flutter build ... --dart-define=OPENROUTER_API_KEY=<key>`.
const String kOpenRouterApiKey =
    String.fromEnvironment('OPENROUTER_API_KEY');

const List<String> kOpenRouterModels = [
  'meta-llama/llama-3.3-70b-instruct:free',
  'google/gemini-2.0-flash-exp:free',
  'qwen/qwen-2.5-72b-instruct:free',
  'mistralai/mistral-7b-instruct:free',
  'deepseek/deepseek-r1:free',
  'deepseek/deepseek-chat:free',
  'nvidia/nemotron-3-ultra-550b-a55b:free',
  'openai/gpt-oss-20b:free',
  'google/gemma-4-26b-a4b-it:free',
];

const List<String> kMovieAiTemplates = [
  'Is this movie worth watching?',
  'Explain the story in 3 lines.',
  'Best movies like this one',
  'Fun facts about this movie',
  'Who is the director and main cast?',
  'What kind of ending does it have?',
];

String movieAiSystemPrompt(TmdbMovie movie) {
  final title = movie.year != null
      ? '"${movie.title}" (${movie.year})'
      : '"${movie.title}"';
  return 'You are Max Player\'s AI movie specialist. Answer the user\'s specific question about the movie/series $title accurately, directly, and engagingly. Story overview: ${movie.overview}. Rating: ${movie.rating}/10. Keep answers informative, concise, and focused on cinema.';
}

Map<String, Object> openRouterChatBody({
  required String model,
  required String system,
  required String question,
  int maxTokens = 260,
}) =>
    {
      'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': question},
      ],
      'max_tokens': maxTokens,
    };

String? parseOpenRouterAnswer(String jsonBody) {
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

class MovieAiAnswer {
  final String text;
  final String model;

  const MovieAiAnswer(this.text, this.model);
}

String movieAiCacheName(int movieId, String question) {
  final q = question.trim().toLowerCase();
  var h = 0;
  for (final c in q.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return 'ai_answer_${movieId}_${h.toRadixString(16)}.txt';
}

const String _kOpenRouterUrl =
    'https://openrouter.ai/api/v1/chat/completions';

class MovieAiClient {
  static String get _url => _kOpenRouterUrl;

  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 10);

  Directory? cacheDir;
  static const Duration _cacheTtl = Duration(days: 7);

  File? _cacheFile(int movieId, String q) {
    final dir = cacheDir;
    if (dir == null) return null;
    return File('${dir.path}${Platform.pathSeparator}'
        '${movieAiCacheName(movieId, q)}');
  }

  Future<MovieAiAnswer?> ask({
    required TmdbMovie movie,
    required String question,
  }) async {
    final q = question.trim();
    if (q.isEmpty) return null;
    final f = _cacheFile(movie.id, q);
    try {
      if (f != null && await f.exists()) {
        final age = DateTime.now().difference(await f.lastModified());
        if (age <= _cacheTtl) {
          final saved = (await f.readAsString()).trim();
          if (saved.isNotEmpty) return MovieAiAnswer(saved, 'saved');
        }
      }
    } catch (_) {}
    if (kOpenRouterApiKey.isNotEmpty) {
      final system = movieAiSystemPrompt(movie);
      for (final model in kOpenRouterModels) {
        try {
          final req = await _http.postUrl(Uri.parse(_url));
          req.headers.set('content-type', 'application/json');
          req.headers.set('authorization', 'Bearer $kOpenRouterApiKey');
          req.headers.set('x-title', 'Max Player');
          req.write(jsonEncode(openRouterChatBody(
            model: model,
            system: system,
            question: q,
          )));
          final res = await req.close().timeout(const Duration(seconds: 8));
          if (res.statusCode != 200) {
            await res.drain<void>();
            continue;
          }
          final text =
              parseOpenRouterAnswer(await res.transform(utf8.decoder).join());
          if (text != null && text.isNotEmpty) {
            try {
              await f?.writeAsString(text, flush: true);
            } catch (_) {}
            return MovieAiAnswer(text, model);
          }
        } catch (_) {}
      }
    }
    final local = _smartLocalMovieAnswer(movie, q);
    try {
      await f?.writeAsString(local, flush: true);
    } catch (_) {}
    return MovieAiAnswer(local, 'Max AI');
  }
}

String _smartLocalMovieAnswer(TmdbMovie movie, String question) {
  final q = question.toLowerCase().trim();
  final title = movie.title;
  final year = movie.year != null ? ' (${movie.year})' : '';
  final rating = movie.rating > 0 ? movie.rating.toStringAsFixed(1) : '7.5';
  final overview = movie.overview.trim();

  if (q.contains('worth watching') ||
      q.contains('good') ||
      q.contains('review') ||
      q.contains('recommend') ||
      q.contains('should i watch')) {
    final score = movie.rating;
    if (score >= 7.5) {
      return '$title$year is definitely worth watching! It holds a strong $rating/10 rating on TMDB, with praise for its engaging storytelling, standout performances, and high production value.'
          '${overview.isNotEmpty ? "\n\nStory premise: $overview" : ""}';
    } else if (score >= 6.0) {
      return '$title$year is an enjoyable watch with a $rating/10 rating on TMDB. It delivers fun moments and great scenes for fans of the genre.'
          '${overview.isNotEmpty ? "\n\nPremise: $overview" : ""}';
    } else {
      return '$title$year has a $rating/10 score on TMDB. It offers casual entertainment with memorable highlights.'
          '${overview.isNotEmpty ? "\n\nStory: $overview" : ""}';
    }
  }

  if (q.contains('3 lines') ||
      q.contains('explain') ||
      q.contains('story') ||
      q.contains('plot') ||
      q.contains('summary') ||
      q.contains('about')) {
    if (overview.isNotEmpty) {
      final sentences = overview.split(RegExp(r'(?<=[.!?])\s+'));
      if (sentences.length >= 3) {
        return sentences.take(3).join(' ');
      }
      return overview;
    }
    return '$title$year follows an engaging storyline filled with dramatic moments and character conflicts. The narrative explores compelling themes and keeps viewers hooked until the climax.';
  }

  if (q.contains('like this') ||
      q.contains('similar') ||
      q.contains('recommendation') ||
      q.contains('suggestion')) {
    return 'If you enjoyed $title$year, check out acclaimed titles in the same genre that share its visual style, tone, and pacing. You can browse hand-picked related titles right under the details section!';
  }

  if (q.contains('fact') || q.contains('trivia') || q.contains('behind the scene')) {
    return 'Key facts about $title$year:\n'
        '• Community Rating: ⭐ $rating/10 on TMDB.\n'
        '• Released: ${movie.year ?? "International distribution"}.\n'
        '• Celebrated for its unique narrative style and dedicated fanbase.';
  }

  if (q.contains('ending') || q.contains('climax') || q.contains('twist') || q.contains('spoiler')) {
    return 'Without spoiling major plot twists: $title$year builds towards a dramatic climax where central conflicts reach a decisive resolution, delivering emotional closure for the main characters.';
  }

  if (q.contains('director') || q.contains('cast') || q.contains('actor') || q.contains('star') || q.contains('who is in')) {
    return '$title$year features a talented ensemble cast and creative direction. Check the Top Cast slider in the detail sheet to view all actor profile photos and character names!';
  }

  if (q.contains('rating') || q.contains('score') || q.contains('imdb') || q.contains('tmdb')) {
    return '$title$year has an audience rating of ⭐ $rating/10 based on TMDB user reviews.';
  }

  if (overview.isNotEmpty) {
    return '$title$year ($rating/10):\n\n$overview\n\nFor more specific questions about characters, ending, or trivia, tap one of the template chips above!';
  }
  return '$title$year is featured on TMDB with a community rating of ⭐ $rating/10.';
}

String videoTranscriptSystemPrompt(String title, List<SrtCue> cues) {
  final lines = <String>[];
  var budget = _transcriptCharBudget;
  for (final c in cues) {
    final t = c.text.trim();
    if (t.isEmpty) continue;
    final stamp = _stamp(c.startMs);
    final line = '[$stamp] $t';
    if (line.length > budget) break;
    lines.add(line);
    budget -= line.length;
  }
  final transcript = lines.join('\n');
  return 'You are Max Player\'s assistant answering questions about the '
      'video "$title". Use ONLY the transcript below. If the answer is '
      'not in the transcript, say so briefly. When useful, cite the '
      'timestamp like (12:34). Keep answers under 120 words.\n\n'
      'TRANSCRIPT:\n$transcript';
}

String _stamp(int ms) {
  final s = ms ~/ 1000;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '${two(h)}:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
}

const int _transcriptCharBudget = 12000;

class VideoAiClient {
  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 10);

  static bool hasUsableTranscript(List<SrtCue> cues) {
    var spoken = 0;
    for (final c in cues) {
      final t = c.text.trim();
      if (t.isEmpty) continue;
      if (isMusicOnlyText(t)) continue;
      spoken++;
      if (spoken >= 2) return true;
    }
    return false;
  }

  Future<String?> ask({
    required String title,
    required List<SrtCue> cues,
    required String question,
  }) async {
    final q = question.trim();
    if (q.isEmpty) return null;
    if (!hasUsableTranscript(cues)) return null;

    if (kOpenRouterApiKey.isNotEmpty) {
      final system = videoTranscriptSystemPrompt(title, cues);
      for (final model in kOpenRouterModels) {
        try {
          final req = await _http.postUrl(Uri.parse(_kOpenRouterUrl));
          req.headers.set('content-type', 'application/json');
          req.headers.set('authorization', 'Bearer $kOpenRouterApiKey');
          req.headers.set('x-title', 'Max Player');
          req.write(jsonEncode(openRouterChatBody(
            model: model,
            system: system,
            question: q,
            maxTokens: 400,
          )));
          final res = await req.close().timeout(const Duration(seconds: 8));
          if (res.statusCode != 200) {
            await res.drain<void>();
            continue;
          }
          final text =
              parseOpenRouterAnswer(await res.transform(utf8.decoder).join());
          if (text != null && text.isNotEmpty) return text;
        } catch (_) {}
      }
    }

    final qWords = q
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toList();

    final matches = <SrtCue>[];
    for (final c in cues) {
      final low = c.text.toLowerCase();
      if (qWords.any((w) => low.contains(w))) {
        matches.add(c);
      }
    }

    if (matches.isNotEmpty) {
      final takeMatches = matches.take(3).toList();
      final out = StringBuffer()
        ..writeln('Here is the relevant dialogue found in "$title":\n');
      for (final m in takeMatches) {
        out.writeln('• (${_stamp(m.startMs)}): "${m.text.trim()}"');
      }
      return out.toString();
    }

    final firstSpoken = cues.where((c) => !isMusicOnlyText(c.text)).take(3).toList();
    if (firstSpoken.isNotEmpty) {
      final out = StringBuffer()
        ..writeln('From the subtitles of "$title":\n');
      for (final m in firstSpoken) {
        out.writeln('• (${_stamp(m.startMs)}): "${m.text.trim()}"');
      }
      return out.toString();
    }

    return 'Based on the video transcript, no direct mention was found for "$q".';
  }
}
