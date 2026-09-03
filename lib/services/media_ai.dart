import 'dart:convert';
import 'dart:io';

import '../utils/formatters.dart';
import 'movie_ai.dart';

/// v95: REAL analysis for the File Manager's "AI Media Insights".
///
/// WHY THIS FILE EXISTS
/// --------------------
/// The old `_showAiMediaInsights()` counted files and then printed the SAME
/// hardcoded sentence for every folder on the device:
///   "AI Recommendation: All media formats here are fully accelerated by
///    libmpv for 100% smooth playback."
/// That is why it read as meaningless - it was not looking at anything.
///
/// This service instead computes findings that are genuinely derived from the
/// folder (orphaned subtitles, probable duplicates, unrecognized extensions,
/// the largest file), and only THEN asks the app's EXISTING OpenRouter client
/// in movie_ai.dart for commentary on top - same key, same model fallback
/// chain, no new dependency and no new secret to manage.
///
/// PRIVACY: only file *names*, sizes and counts leave the device, and only for
/// the handful of items actually worth commenting on. Never file contents,
/// never paths outside the folder being inspected.

enum MediaKind { video, audio, image, doc, subtitle, other }

class MediaFileInfo {
  final String name;
  final int bytes;
  final MediaKind kind;

  const MediaFileInfo(this.name, this.bytes, this.kind);

  /// Lowercased extension without the dot; '' when there is none.
  String get ext {
    final i = name.lastIndexOf('.');
    return (i <= 0 || i == name.length - 1)
        ? ''
        : name.substring(i + 1).toLowerCase();
  }

  /// Name with its extension removed, lowercased - used to pair subtitles up.
  String get stem {
    final i = name.lastIndexOf('.');
    return (i <= 0 ? name : name.substring(0, i)).toLowerCase();
  }
}

/// Pure, computed facts about one folder. The caller does the I/O; this class
/// only reasons about what it was given, so it is unit-testable.
class MediaFolderStats {
  final String folderName;
  final int dirs;
  final List<MediaFileInfo> files;

  MediaFolderStats({
    required this.folderName,
    required this.dirs,
    required this.files,
  });

  int countOf(MediaKind k) => files.where((f) => f.kind == k).length;

  int get videos => countOf(MediaKind.video);
  int get audios => countOf(MediaKind.audio);
  int get images => countOf(MediaKind.image);
  int get docs => countOf(MediaKind.doc);
  int get subtitles => countOf(MediaKind.subtitle);
  int get others => countOf(MediaKind.other);

  int get totalBytes => files.fold(0, (a, f) => a + f.bytes);

  MediaFileInfo? get largest {
    MediaFileInfo? best;
    for (final f in files) {
      if (best == null || f.bytes > best.bytes) best = f;
    }
    return best;
  }

  /// Subtitle files that have no video in this folder to attach to, so they
  /// will never auto-load. Allows the common "movie.en.srt" / "movie (1).srt"
  /// spellings to still count as a match for "movie.mkv".
  List<MediaFileInfo> get orphanedSubtitles {
    final all = files.where((f) => f.kind == MediaKind.subtitle).toList();
    if (all.isEmpty) return const [];
    final stems =
        files.where((f) => f.kind == MediaKind.video).map((f) => f.stem).toList();
    if (stems.isEmpty) return all;
    return all.where((f) {
      for (final v in stems) {
        if (f.stem == v || f.stem.startsWith('$v.') || f.stem.startsWith('$v ')) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  /// Videos that are byte-identical in size AND extension - almost certainly
  /// the same file downloaded twice. The 1 MB floor skips thumbnails/partial
  /// downloads, which collide constantly and would be noise.
  List<String> get duplicateCandidates {
    final seen = <String, List<MediaFileInfo>>{};
    for (final f in files) {
      if (f.kind != MediaKind.video) continue;
      if (f.bytes < 1024 * 1024) continue;
      seen.putIfAbsent('${f.bytes}|${f.ext}', () => []).add(f);
    }
    final out = <String>[];
    for (final group in seen.values) {
      if (group.length < 2) continue;
      out.add('${group.length} x ${group.first.name}');
    }
    out.sort();
    return out;
  }

  /// The four most common extensions, most frequent first.
  Map<String, int> get topExtensions {
    final m = <String, int>{};
    for (final f in files) {
      if (f.ext.isEmpty) continue;
      m[f.ext] = (m[f.ext] ?? 0) + 1;
    }
    final sorted = m.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map<String, int>.fromEntries(sorted.take(4));
  }
}

/// Findings derived purely from the data above - ALWAYS shown, even with no
/// network and no API key. This is the part that can never be a lie.
List<String> localMediaInsights(MediaFolderStats s) {
  final out = <String>[];

  if (s.files.isEmpty && s.dirs == 0) {
    out.add('This folder is empty - nothing to analyze.');
    return out;
  }
  if (s.files.isEmpty) {
    out.add('Only subfolders here (${s.dirs}), no media files at this level.');
    return out;
  }

  final orphans = s.orphanedSubtitles;
  if (orphans.isNotEmpty) {
    final names = orphans.take(3).map((f) => f.name).join(', ');
    out.add(
      '${orphans.length} subtitle file${orphans.length == 1 ? '' : 's'} match no '
      'video in this folder: $names. Rename ${orphans.length == 1 ? 'it' : 'them'} '
      'to the video\'s exact name to make ${orphans.length == 1 ? 'it' : 'them'} load automatically.',
    );
  }

  final dupes = s.duplicateCandidates;
  if (dupes.isNotEmpty) {
    out.add(
      'Possible duplicates (same size and container): ${dupes.take(3).join('; ')}.',
    );
  }

  if (s.others > 0) {
    final ex = s.files
        .where((f) => f.kind == MediaKind.other)
        .take(3)
        .map((f) => f.name)
        .join(', ');
    out.add(
      '${s.others} file${s.others == 1 ? '' : 's'} with an unrecognized extension '
      '($ex) - these may not play.',
    );
  }

  final big = s.largest;
  if (big != null && big.bytes >= 1024 * 1024 * 1024) {
    final share = s.totalBytes == 0 ? 0 : (big.bytes * 100) ~/ s.totalBytes;
    out.add(
      'Largest: ${big.name} at ${formatFileSize(big.bytes)} - $share% of this '
      'folder\'s ${formatFileSize(s.totalBytes)}.',
    );
  }

  if (out.isEmpty) {
    final exts = s.topExtensions.entries.map((e) => '.${e.key}').join(', ');
    out.add(
      'Nothing needs attention: ${s.videos} video${s.videos == 1 ? '' : 's'}, '
      '${s.files.length} files, ${formatFileSize(s.totalBytes)}'
      '${exts.isEmpty ? '' : ', formats $exts'} - all handled natively by libmpv.',
    );
  }
  return out;
}

class MediaAiAnswer {
  final String text;
  final String model;

  const MediaAiAnswer(this.text, this.model);
}

const String kMediaAiSystemPrompt =
    'You are the media librarian inside the Max Player Android app. You are '
    'given REAL statistics that were computed on the user\'s device about one '
    'folder of their storage. Reply with 2 to 4 short, specific, practical '
    'observations in plain prose - no markdown, no headings, no bullet '
    'characters, no emoji. Refer ONLY to files, counts and sizes that actually '
    'appear in the statistics; never invent titles or files, never suggest '
    'buying anything, never say that you are an AI. If nothing needs the '
    'user\'s attention, say that plainly in one sentence. Keep the whole reply '
    'under 90 words.';

class MediaAiClient {
  static const String _url = 'https://openrouter.ai/api/v1/chat/completions';

  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 8);

  /// Compact, privacy-bounded payload: counts, sizes, formats and at most a
  /// few file names. Never contents, never the full path.
  static String statsPrompt(MediaFolderStats s) {
    final buf = StringBuffer()
      ..writeln('Folder: ${s.folderName}')
      ..writeln('Subfolders: ${s.dirs}')
      ..writeln(
        'Files: ${s.files.length} (videos ${s.videos}, audio ${s.audios}, '
        'images ${s.images}, documents ${s.docs}, subtitles ${s.subtitles}, '
        'unrecognized ${s.others})',
      )
      ..writeln('Total size: ${formatFileSize(s.totalBytes)}');

    final exts = s.topExtensions;
    if (exts.isNotEmpty) {
      buf.writeln(
        'Formats: ${exts.entries.map((e) => '.${e.key} x${e.value}').join(', ')}',
      );
    }
    final big = s.largest;
    if (big != null) {
      buf.writeln('Largest file: ${big.name} (${formatFileSize(big.bytes)})');
    }
    final orphans = s.orphanedSubtitles;
    if (orphans.isNotEmpty) {
      buf.writeln(
        'Subtitles matching no video in this folder: '
        '${orphans.take(4).map((f) => f.name).join(', ')}',
      );
    }
    final dupes = s.duplicateCandidates;
    if (dupes.isNotEmpty) {
      buf.writeln('Same-size same-format video groups: ${dupes.take(3).join('; ')}');
    }
    buf.write(
      'On-device findings already shown to the user: '
      '${localMediaInsights(s).join(' | ')}',
    );
    return buf.toString();
  }

  /// Returns null when there is no API key, no network, or every model in the
  /// fallback chain failed. The caller then shows the on-device findings
  /// instead and says so - it never substitutes a made-up sentence.
  static Future<MediaAiAnswer?> ask(MediaFolderStats s) async {
    if (kOpenRouterApiKey.isEmpty) return null;
    if (s.files.isEmpty && s.dirs == 0) return null;

    final question = statsPrompt(s);
    for (final model in kOpenRouterModels) {
      try {
        final req = await _http.postUrl(Uri.parse(_url));
        req.headers.set('content-type', 'application/json');
        req.headers.set('authorization', 'Bearer $kOpenRouterApiKey');
        req.headers.set('x-title', 'Max Player');
        req.write(jsonEncode(openRouterChatBody(
          model: model,
          system: kMediaAiSystemPrompt,
          question: question,
          maxTokens: 260,
        )));
        final res = await req.close().timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) {
          await res.drain<void>();
          continue;
        }
        final body = await res.transform(utf8.decoder).join();
        final text = parseOpenRouterAnswer(body);
        if (text != null && text.trim().isNotEmpty) {
          return MediaAiAnswer(text.trim(), model);
        }
      } catch (_) {
        // try the next model in the chain
      }
    }
    return null;
  }
}
