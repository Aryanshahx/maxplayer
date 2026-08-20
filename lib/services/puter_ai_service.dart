import 'dart:convert';
import 'dart:io';

import '../utils/srt.dart';

/// Puter AI API Key, injected at build time:
/// `flutter build ... --dart-define=PUTER_API_KEY=<key>`.
/// Can also be passed dynamically by the user in the AI Subtitle dialog.
const String kPuterApiKey = String.fromEnvironment('PUTER_API_KEY');

/// Puter AI models available for Subtitle Translation, Formatting & AI Enhancements.
const List<String> kPuterAiModels = [
  'claude-3-5-sonnet',
  'gpt-4o-mini',
  'gemini-1.5-flash',
  'deepseek-chat',
];

/// Result object from Puter AI Subtitle Service.
class PuterAiSubtitleResult {
  final List<SrtCue> cues;
  final String modelUsed;
  final String? rawResponse;

  const PuterAiSubtitleResult({
    required this.cues,
    required this.modelUsed,
    this.rawResponse,
  });
}

/// Service that leverages Puter AI API (api.puter.com) to translate,
/// polish, and format AI subtitles in Max Player.
class PuterAiService {
  static const String _puterAiUrl = 'https://api.puter.com/v2/ai/chat';

  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 15);

  /// Translates existing SRT subtitle cues into [targetLanguage] using Puter AI.
  /// Preserves exact timing timestamps and line structure.
  static Future<PuterAiSubtitleResult?> translateSubtitles({
    required List<SrtCue> cues,
    required String targetLanguage,
    String model = 'claude-3-5-sonnet',
    String? userApiKey,
  }) async {
    final apiKey = (userApiKey != null && userApiKey.trim().isNotEmpty)
        ? userApiKey.trim()
        : kPuterApiKey;

    if (cues.isEmpty) return null;

    final buffer = StringBuffer();
    for (var i = 0; i < cues.length; i++) {
      buffer.writeln('${i + 1}');
      buffer.writeln(cues[i].text.replaceAll('\n', ' '));
      buffer.writeln();
    }

    final systemPrompt =
        'You are an expert movie subtitle translator for Max Player. '
        'Translate the following numbered subtitle lines into $targetLanguage. '
        'CRITICAL RULES:\n'
        '1. Keep the exact line numbers (1, 2, 3...).\n'
        '2. Translate ONLY the text below each number.\n'
        '3. Do NOT add notes, explanations, or commentary.\n'
        '4. Maintain natural dialogue flow and character tone.';

    final userPrompt = buffer.toString();

    try {
      final responseText = await _callPuterAi(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        model: model,
        apiKey: apiKey,
      );

      if (responseText == null || responseText.trim().isEmpty) return null;

      final translatedCues = _parseNumberedTranslation(responseText, cues);
      if (translatedCues.isEmpty) return null;

      return PuterAiSubtitleResult(
        cues: translatedCues,
        modelUsed: model,
        rawResponse: responseText,
      );
    } catch (_) {
      return null;
    }
  }

  /// Enhances raw or Whisper-generated subtitles using Puter AI:
  /// fixes grammar, removes noise artifacts like [music], and formats lines.
  static Future<PuterAiSubtitleResult?> enhanceSubtitles({
    required List<SrtCue> cues,
    String model = 'gpt-4o-mini',
    String? userApiKey,
  }) async {
    final apiKey = (userApiKey != null && userApiKey.trim().isNotEmpty)
        ? userApiKey.trim()
        : kPuterApiKey;

    if (cues.isEmpty) return null;

    final buffer = StringBuffer();
    for (var i = 0; i < cues.length; i++) {
      buffer.writeln('${i + 1}');
      buffer.writeln(cues[i].text.replaceAll('\n', ' '));
      buffer.writeln();
    }

    final systemPrompt =
        'You are an AI Subtitle Polisher for Max Player. '
        'Refine the following numbered subtitle lines:\n'
        '1. Fix punctuation, capitalization, and minor typos.\n'
        '2. Remove hallucinated noise tags like [music], (cheering), ♪.\n'
        '3. Keep line numbers intact.\n'
        '4. Do not alter the core meaning or timing.';

    try {
      final responseText = await _callPuterAi(
        systemPrompt: systemPrompt,
        userPrompt: buffer.toString(),
        model: model,
        apiKey: apiKey,
      );

      if (responseText == null || responseText.trim().isEmpty) return null;

      final polishedCues = _parseNumberedTranslation(responseText, cues);
      if (polishedCues.isEmpty) return null;

      return PuterAiSubtitleResult(
        cues: polishedCues,
        modelUsed: model,
        rawResponse: responseText,
      );
    } catch (_) {
      return null;
    }
  }

  /// Executes HTTP request to Puter AI chat endpoint.
  static Future<String?> _callPuterAi({
    required String systemPrompt,
    required String userPrompt,
    required String model,
    required String apiKey,
  }) async {
    try {
      final uri = Uri.parse(_puterAiUrl);
      final req = await _http.postUrl(uri);

      req.headers.set('Content-Type', 'application/json');
      if (apiKey.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $apiKey');
        req.headers.set('puter-auth', apiKey);
      }

      final payload = {
        'model': model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'temperature': 0.3,
        'max_tokens': 2000,
      };

      req.write(jsonEncode(payload));
      final res = await req.close().timeout(const Duration(seconds: 45));

      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }

      final body = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);

      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('choices') && decoded['choices'] is List) {
          final choices = decoded['choices'] as List;
          if (choices.isNotEmpty && choices.first is Map) {
            final msg = choices.first['message'];
            if (msg is Map && msg.containsKey('content')) {
              return msg['content']?.toString();
            }
          }
        } else if (decoded.containsKey('text')) {
          return decoded['text']?.toString();
        } else if (decoded.containsKey('message')) {
          return decoded['message']?.toString();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Re-maps translated/polished numbered lines back onto original SRT timestamps.
  static List<SrtCue> _parseNumberedTranslation(
    String responseText,
    List<SrtCue> originalCues,
  ) {
    final lines = responseText.split('\n');
    final Map<int, String> parsedLines = {};

    int? currentIdx;
    StringBuffer textBuffer = StringBuffer();

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final match = RegExp(r'^\d+$').firstMatch(line);
      if (match != null) {
        if (currentIdx != null && textBuffer.isNotEmpty) {
          parsedLines[currentIdx] = textBuffer.toString().trim();
          textBuffer.clear();
        }
        currentIdx = int.tryParse(line);
      } else {
        if (currentIdx != null) {
          if (textBuffer.isNotEmpty) textBuffer.write(' ');
          textBuffer.write(line);
        }
      }
    }

    if (currentIdx != null && textBuffer.isNotEmpty) {
      parsedLines[currentIdx] = textBuffer.toString().trim();
    }

    final List<SrtCue> out = [];
    for (var i = 0; i < originalCues.length; i++) {
      final cueIndex = i + 1;
      final newText = parsedLines[cueIndex] ?? originalCues[i].text;
      out.add(SrtCue(originalCues[i].startMs, originalCues[i].endMs, newText));
    }

    return out;
  }
}
