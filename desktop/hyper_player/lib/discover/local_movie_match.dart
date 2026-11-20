import '../playlist.dart';
import '../local_media_index.dart';

String normalizeMovieTitle(String raw) {
  var t = raw.toLowerCase();
  t = t.replaceAll(RegExp(r'[._\-]+'), ' ');
  t = t.replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ');
  t = t.replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ');
  t = t.replaceAll(
      RegExp(r'\b(480p|576p|720p|1080p|2160p|4320p|4k|8k|uhd|fhd|hd|sd|hq|'
          r'x264|x265|h264|h265|hevc|avc|av1|bluray|bdrip|brrip|webrip|'
          r'web dl|webdl|hdrip|hdtv|dvdrip|camrip|hdcam|dvdscr|ts|'
          r'proper|repack|extended|remastered|unrated|directors?|cut|imax|'
          r'10bit|hdr10?|hdr|dolby|vision|atmos|aac|ac3|eac3|dts|mp3|'
          r'dual|multi|audio|esub|subs?|eng|english|hindi|tamil|telugu|'
          r'clean|line|sample)\b'),
      ' ');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t;
}

/// Only known local video sources. Prefer year match; never choose an explicitly
/// different-year remake. No whole-disk search or download inference.
String? findLocalMovieSource(
    String title, int? year, Iterable<String> sources) {
  final want = normalizeMovieTitle(title);
  if (want.isEmpty) return null;
  String? fallback;
  for (final source in sources) {
    if (validStream(source) || !isMediaPath(source) || isAudioPath(source)) {
      continue;
    }
    final name = labelFor(source).replaceFirst(RegExp(r'\.[^.]+$'), '');
    if (normalizeMovieTitle(name) != want) continue;
    final years = RegExp(r'\b(?:19|20)\d{2}\b')
        .allMatches(name.replaceAll(RegExp(r'[._-]'), ' '))
        .map((m) => int.parse(m.group(0)!))
        .toList();
    if (year != null && years.contains(year)) return source;
    if (year != null && years.isNotEmpty) continue;
    fallback ??= source;
  }
  return fallback;
}
