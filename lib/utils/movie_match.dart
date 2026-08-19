import '../models/video_track.dart';

/// v43: tells whether a TMDB movie exists in the user's OWN local video
/// library ("In my library" button on the Discover detail sheet - the
/// moment discovery ends in OUR player, offline).
///
/// Filename reality on phones: "Interstellar.2014.1080p.BluRay.x265.mkv",
/// "3_Idiots_2009_HD.mkv"... [normalizeMovieTitle] strips all of that junk
/// down to the comparable core. Pure + unit-tested.

/// Strips separators, years, quality/codec rip-junk and brackets so two
/// differently-written names of the same movie normalize identically.
String normalizeMovieTitle(String raw) {
  var t = raw.toLowerCase();
  t = t.replaceAll(RegExp(r'[._\-]+'), ' ');
  t = t.replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ');
  t = t.replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ');
  t = t.replaceAll(
      RegExp(
          r'\b(480p|576p|720p|1080p|2160p|4320p|4k|8k|uhd|fhd|hd|sd|hq|'
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

/// The user's copy of [tmdbTitle], if the library has it. Exact normalized
/// title match wins; a filename that ALSO carries [year] is preferred over
/// a plain title hit (e.g. "Dune.2024" beats "Dune (1984)"'s remake risk).
/// Returns null when there is no match - the UI then simply hides the
/// "In my library" button.
VideoTrack? findLocalMovie(
  String tmdbTitle,
  int? year,
  List<VideoTrack> videos,
) {
  final want = normalizeMovieTitle(tmdbTitle);
  if (want.isEmpty) return null;
  VideoTrack? titleOnly;
  for (final v in videos) {
    if (normalizeMovieTitle(v.title) != want) continue;
    if (year != null && (v.title.contains('$year') || v.path.contains('$year'))) {
      return v;
    }
    titleOnly ??= v;
  }
  return titleOnly;
}
