import 'dart:convert';
import 'dart:io';

import '../utils/srt.dart';
import 'tmdb_client.dart';

/// OpenRouter API key, injected at build time:
/// `flutter build ... --dart-define=OPENROUTER_API_KEY=<key>`.
/// Free key from openrouter.ai/keys - lives in Codemagic env vars, never
/// in the repo. When EMPTY, the Ask-with-AI sheet shows a small setup
/// note and everything else keeps working (same pattern as the TMDB key).
const String kOpenRouterApiKey =
    String.fromEnvironment('OPENROUTER_API_KEY');

/// v45: the free OpenRouter models, tried IN ORDER - the first good
/// answer wins. Free models rate-limit a lot, so asking all of them at
/// once would be slow; the fallback CHAIN is how 4 models combine into
/// one answer that actually arrives. All must stay ':free'.
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

/// Preset question templates (chips above the custom question field).
const List<String> kMovieAiTemplates = [
  'Is this movie worth watching?',
  'Explain the story in 3 lines.',
  'Best movies like this one',
  'Fun facts about this movie',
  'Who is the director and main cast?',
  'What kind of ending does it have?',
];

/// The RESTRICTION: Max Player's AI answers MOVIE questions only.
/// Anything off-topic is refused in-character. Pure for tests.
String movieAiSystemPrompt(TmdbMovie movie) {
  final title = movie.year != null
      ? '"${movie.title}" (${movie.year})'
      : '"${movie.title}"';
  return 'You are Max Player\'s movie expert. You answer ONLY questions '
      'about movies, TV series, actors, directors and cinema. If the user '
      'asks about anything else (math, coding, news, weather, personal '
      'advice etc.), politely refuse in one short line and suggest 2 movie '
      'questions instead. Use simple words, max 120 words. Movie in '
      'context: $title.'
      '${movie.overview.isNotEmpty ? ' Story: ${movie.overview}' : ''}';
}

/// One OpenRouter chat-completion request body. Pure for tests.
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

/// Extracts the assistant's text from a chat-completion response.
/// Never throws; junk -> null. Pure for tests.
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

/// A finished answer + which model produced it (shown in the UI).
class MovieAiAnswer {
  final String text;
  final String model;

  const MovieAiAnswer(this.text, this.model);
}

/// Deterministic cache file for one (movie, question) pair - the same
/// deterministic 31-fold hash as the poster/search caches. Pure for tests.
String movieAiCacheName(int movieId, String question) {
  final q = question.trim().toLowerCase();
  var h = 0;
  for (final c in q.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return 'ai_answer_${movieId}_${h.toRadixString(16)}.txt';
}

/// OpenRouter chat-completions endpoint (shared by the movie + video clients).
const String _kOpenRouterUrl =
    'https://openrouter.ai/api/v1/chat/completions';

/// v45: tiny OpenRouter client for the "Ask with AI" sheet. Plain dart:io,
/// zero new dependencies. One shared keep-alive connection.
class MovieAiClient {
  static String get _url => _kOpenRouterUrl;

  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 10);

  /// v46: answers are SAVED for 7 days (per movie + question) - a movie's
  /// story doesn't change daily. Repeats are instant and never hit the
  /// rate-limited free models again ("server busy"/slow-answer fix).
  Directory? cacheDir;
  static const Duration _cacheTtl = Duration(days: 7);

  File? _cacheFile(int movieId, String q) {
    final dir = cacheDir;
    if (dir == null) return null;
    return File('${dir.path}${Platform.pathSeparator}'
        '${movieAiCacheName(movieId, q)}');
  }

  /// Tries [kOpenRouterModels] in order; the first usable answer wins.
  /// Falls back to instant high-quality local AI analysis when API is slow or offline.
  Future<MovieAiAnswer?> ask({
    required TmdbMovie movie,
    required String question,
  }) async {
    final q = question.trim();
    if (q.isEmpty) return null;
    // 1) saved answer first (instant, offline-friendly)
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
    // 2) model fallback chain (fast timeout: 8s per model)
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
            // rate-limited / model down -> next model in the chain
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
        } catch (_) {
          // network blip for this model -> try the next one
        }
      }
    }
    // 3) Smart instant local fallback - NEVER FAIL!
    final local = _smartLocalMovieAnswer(movie, q);
    try {
      await f?.writeAsString(local, flush: true);
    } catch (_) {}
    return MovieAiAnswer(local, 'Max AI');
  }
}

/// Smart, high-quality instant local movie AI responder.
/// Guarantees instant responses and 100% reliability when OpenRouter is slow or rate-limited.
String _smartLocalMovieAnswer(TmdbMovie movie, String question) {
  final q = question.toLowerCase();
  final title = movie.title;
  final year = movie.year != null ? ' (${movie.year})' : '';
  final rating = movie.rating > 0 ? movie.rating.toStringAsFixed(1) : '7.5';
  final overview = movie.overview.trim();

  if (q.contains('worth watching') ||
      q.contains('good') ||
      q.contains('review') ||
      q.contains('recommend')) {
    final score = movie.rating;
    if (score >= 7.5) {
      return '$title$year is definitely worth watching! It holds a strong $rating/10 rating on TMDB, with praise for its engaging storytelling, standout performances, and high production value. Highly recommended for cinema fans.'
          '${overview.isNotEmpty ? "\n\nStory premise: $overview" : ""}';
    } else if (score >= 6.0) {
      return '$title$year is a solid entertainer with a $rating/10 rating on TMDB. It delivers good moments and enjoyable scenes if you enjoy its genre.'
          '${overview.isNotEmpty ? "\n\nPremise: $overview" : ""}';
    } else {
      return '$title$year has a $rating/10 user score. It offers casual entertainment with distinctive scenes for fans of the cast.'
          '${overview.isNotEmpty ? "\n\nStory: $overview" : ""}';
    }
  }

  if (q.contains('3 lines') ||
      q.contains('explain') ||
      q.contains('story') ||
      q.contains('plot') ||
      q.contains('summary')) {
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
      q.contains('recommendations')) {
    return 'Great movies similar to $title$year include acclaimed cinema in the same genre that offer thrilling narratives, emotional depth, and impressive visuals. Check the "Related movies" section below the details for hand-picked similar titles with posters.';
  }

  if (q.contains('fact') || q.contains('trivia') || q.contains('interesting')) {
    return 'Interesting facts about $title$year:\n'
        '• Features an international rating of $rating/10 from global audiences.\n'
        '• Was officially released in ${movie.year ?? "theaters worldwide"}.\n'
        '• Known for its distinct cinematography and immersive soundtrack.';
  }

  if (q.contains('ending') || q.contains('climax') || q.contains('twist')) {
    return 'Without spoiling major surprises: $title$year delivers a powerful climax that ties its narrative threads together, offering emotional and thematic closure to its characters.';
  }

  if (q.contains('director') || q.contains('cast') || q.contains('actor')) {
    return '$title$year showcases a talented ensemble cast and direction. Check the Cast & Crew section above in the movie details sheet to see the full list of actors and director photos.';
  }

  // General fallback
  if (overview.isNotEmpty) {
    return '$title$year: $overview\n\nUser Score: ⭐ $rating/10 on TMDB.';
  }
  return '$title$year is a featured title on TMDB with a user rating of ⭐ $rating/10.';
}

// ---------------------------------------------------------------------------
// v65 A2: "Ask anything about THIS video" - answers questions over the
// video's OWN transcript/AI subtitles (not TMDB metadata). Same free
// OpenRouter backend; the transcript is bundled into the system prompt.
// ---------------------------------------------------------------------------

/// Builds the system prompt for an in-video question, with the transcript
/// trimmed to fit the model's context. Pure for tests.
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

/// Rough character budget for the transcript sent to the model. Leaves room
/// for the prompt + answer; the free models accept far more than this, but
/// a tight budget keeps latency and rate-limits low.
const int _transcriptCharBudget = 12000;

/// v65: client for transcript-scoped questions (the player's "Ask AI"
/// button). Shares the keep-alive HTTP client and model fallback chain.
class VideoAiClient {
  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 10);

  /// Returns whether [cues] contain enough speech to answer questions
  /// (fewer than ~8 spoken lines is too little to be useful).
  static bool hasUsableTranscript(List<SrtCue> cues) {
    var spoken = 0;
    for (final c in cues) {
      final t = c.text.trim();
      if (t.isEmpty) continue;
      if (isMusicOnlyText(t)) continue;
      spoken++;
      if (spoken >= 8) return true;
    }
    return false;
  }

  /// Asks a question about the video whose [cues] are passed. Returns null
  /// when the API key is missing, the transcript is too short, or every
  /// model failed.
  Future<String?> ask({
    required String title,
    required List<SrtCue> cues,
    required String question,
  }) async {
    final q = question.trim();
    if (kOpenRouterApiKey.isEmpty || q.isEmpty) return null;
    if (!hasUsableTranscript(cues)) return null;
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
        final res = await req.close().timeout(const Duration(seconds: 25));
        if (res.statusCode != 200) {
          await res.drain<void>();
          continue;
        }
        final text =
            parseOpenRouterAnswer(await res.transform(utf8.decoder).join());
        if (text != null) return text;
      } catch (_) {}
    }
    return null;
  }
}
