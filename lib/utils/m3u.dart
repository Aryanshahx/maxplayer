// Pure M3U playlist parsing (unit-tested).
// IPTV M3U lists: "#EXTM3U" header, "#EXTINF:-1 ... ,Channel Name" then a
// URL on the next line. Comments other than EXTINF are ignored.
// iptv-org playlists (https://iptv-org.github.io) carry extra attributes:
//   tvg-id / tvg-name / tvg-country / tvg-language / group-title / tvg-logo

class IptvChannel {
  const IptvChannel({
    required this.name,
    required this.url,
    this.logo,
    this.group,
  });

  final String name;
  final String url;
  final String? logo;

  /// iptv-org group-title — e.g. News, Sports, Movies. Null when absent.
  final String? group;

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'logo': logo,
    'group': group,
  };

  factory IptvChannel.fromJson(Map<String, dynamic> m) => IptvChannel(
    name: (m['name'] ?? 'Channel') as String,
    url: (m['url'] ?? '') as String,
    logo: m['logo'] as String?,
    group: m['group'] as String?,
  );
}

bool isHlsManifest(String raw) =>
    RegExp(r'^\s*#EXT-X-', multiLine: true).hasMatch(raw);

List<IptvChannel> parseM3u(String raw, {Uri? baseUri}) {
  // HLS master variants and media segments belong to one playable stream.
  if (isHlsManifest(raw)) return [];
  final lines = raw.split(RegExp(r'\r?\n'));
  final out = <IptvChannel>[];
  String? pendingName;
  String? pendingLogo;
  String? pendingGroup;
  for (var line in lines) {
    line = line.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTINF:')) {
      final attr = line.substring(line.indexOf(':') + 1);
      final comma = attr.lastIndexOf(',');
      final named = comma >= 0 ? attr.substring(comma + 1).trim() : attr.trim();
      pendingName = named.isEmpty ? 'Channel' : named;
      final logoMatch = RegExp('tvg-logo="([^"]*)"').firstMatch(attr);
      pendingLogo = logoMatch?.group(1);
      final groupMatch = RegExp('group-title="([^"]*)"').firstMatch(attr);
      pendingGroup = groupMatch?.group(1);
    } else if (!line.startsWith('#')) {
      final reference = Uri.tryParse(line);
      if (baseUri != null && reference == null) {
        pendingName = null;
        pendingLogo = null;
        pendingGroup = null;
        continue;
      }
      final resolved = baseUri != null
          ? baseUri.resolveUri(reference!).toString()
          : line;
      final logoReference = pendingLogo == null
          ? null
          : Uri.tryParse(pendingLogo);
      if (baseUri != null) {
        final uri = Uri.tryParse(resolved);
        if (uri == null ||
            ![
              'http',
              'https',
              'rtsp',
              'rtmp',
              'rtmps',
              'udp',
              'rtp',
            ].contains(uri.scheme) ||
            uri.host.isEmpty) {
          pendingName = null;
          pendingLogo = null;
          pendingGroup = null;
          continue;
        }
      }
      out.add(
        IptvChannel(
          name: pendingName ?? 'Channel',
          url: resolved,
          logo: pendingLogo == null
              ? null
              : (baseUri != null && logoReference != null
                    ? baseUri.resolveUri(logoReference).toString()
                    : pendingLogo),
          group: pendingGroup,
        ),
      );
      pendingName = null;
      pendingLogo = null;
      pendingGroup = null;
    }
  }
  return out;
}
