import 'tmdb.dart';

// ---------------------------------------------------------------------------
// Amazon Associates India — the affiliate engine for "Watch on Prime Video".
// The tag is NOT a secret: it appears in every link by design. When a user
// taps through, anything they buy on amazon.in within 24h earns a small %.
// Rules baked into this file (Associates Operating Agreement):
//   * every link must carry our tag (XXXXX-21 format for India)
//   * no link shorteners that hide the Amazon destination
//   * the "As an Amazon Associate... earn from qualifying purchases"
//     disclosure must live WITH the links (see _WatchBlock in
//     movie_detail_sheet.dart — it ships attached to the button).
// ---------------------------------------------------------------------------

/// Our Amazon Associates India store tag.
const String kAmazonAssociateTag = 'maxplayer0a-21';

/// Pure: does TMDB's Indian watch-provider info include Prime Video?
/// Names seen in the wild: 'Amazon Prime Video', 'Amazon Prime Video
/// with Ads', 'Amazon Video'. Stream / rent / buy all count.
bool tmdbWatchHasPrime(TmdbWatchInfo info) {
  bool hit(List<String> names) => names.any((n) {
        final l = n.toLowerCase();
        return l.contains('amazon') || l.contains('prime video');
      });
  return hit(info.stream) || hit(info.rent) || hit(info.buy);
}

/// Pure: open the title in the PRIME VIDEO APP or, when not installed, the
/// primevideo.com website (user request — go to Prime, not the Amazon
/// shopping app). NOTE: primevideo.com carries NO Associates tag (Amazon
/// only credits amazon.* shopping-domain links), so the tagged shopping
/// link below is kept as the secondary "buy or rent" path.
String primeVideoSearchUrl(String title, {int? year}) {
  final trimmed = title.trim();
  final phrase = (year != null && year > 0) ? '$trimmed $year' : trimmed;
  return Uri.https('www.primevideo.com', '/search', <String, String>{
    'phrase': phrase,
  }).toString();
}

/// Pure: the commissionable link for a title.
/// TMDB does not expose per-title Prime page IDs (they're Amazon GTIs, not
/// ASINs), so we land a TAGGED Prime-Video-scoped search — Associates rules
/// allow search links, and the tag keeps 24h attribution regardless.
String amazonPrimeSearchUrl(String title, {int? year}) {
  final trimmed = title.trim();
  final q =
      (year != null && year > 0) ? '$trimmed $year movie' : '$trimmed movie';
  return Uri.https('www.amazon.in', '/s', <String, String>{
    'k': q,
    'i': 'instant-video', // scope to the Prime Video store
    'tag': kAmazonAssociateTag,
  }).toString();
}
