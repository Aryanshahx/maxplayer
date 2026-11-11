/// v1.0.1+62: iptv-org (legal, free-to-air) .m3u playlist parser.
/// Pure functions — no IO — so the logic is fully unit-tested.
class IptvChannel {
  const IptvChannel({
    required this.name,
    required this.url,
    this.logo = '',
    this.group = '',
    this.quality = '',
  });

  final String name;
  final String url;
  final String logo;
  final String group; // group-title (News / Sports / ...)

  /// The trailing quality token on many iptv-org names, e.g.
  /// "NDTV 24x7 (720p)" -> "720p"; empty when absent.
  final String quality;
}

/// Parse an Extended M3U text into channels. Handles the iptv-org style
/// exactly, plus plain "#EXTINF: -1, Name" lines without attributes.
List<IptvChannel> parseIptvM3u(String m3u) {
  final out = <IptvChannel>[];
  String name = '';
  String logo = '';
  String group = '';
  for (final raw in m3u.split('\n')) {
    final line = raw.trimRight();
    if (line.startsWith('#EXTINF')) {
      final comma = line.indexOf(',');
      name = comma >= 0 ? line.substring(comma + 1).trim() : 'Channel';
      logo = _attr(line, 'tvg-logo');
      group = _attr(line, 'group-title');
    } else if (line.isNotEmpty && !line.startsWith('#')) {
      if (name.isNotEmpty) {
        out.add(
          IptvChannel(
            name: _stripQuality(name, out),
            url: line,
            logo: logo,
            group: group,
            quality: _qualityOf(name),
          ),
        );
      }
      name = logo = group = '';
    }
  }
  return out;
}

String _attr(String line, String key) {
  final m = RegExp('$key="([^"]*)"').firstMatch(line);
  return m?.group(1) ?? '';
}

String _qualityOf(String name) {
  final m = RegExp(
    r'\((\d{3,4}p|HD|SD|4K)\)\s*$',
    caseSensitive: false,
  ).firstMatch(name);
  return m?.group(1)?.toUpperCase() ?? '';
}

String _stripQuality(String name, List<IptvChannel> _) {
  return name
      .replaceAll(
        RegExp(r'\s*\((\d{3,4}p|HD|SD|4K)\)\s*$', caseSensitive: false),
        '',
      )
      .trim();
}

/// iptv-org endpoints we offer out of the box (all legal free-to-air).
const kIptvWorldUrl = 'https://iptv-org.github.io/iptv/index.m3u';
const kIptvIndiaUrl = 'https://iptv-org.github.io/iptv/countries/in.m3u';
