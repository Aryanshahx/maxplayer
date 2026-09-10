// Pure M3U playlist parsing (unit-tested).
// IPTV M3U lists: "#EXTM3U" header, "#EXTINF:-1 ... ,Channel Name" then a
// URL on the next line. Comments other than EXTINF are ignored.

class IptvChannel {
  const IptvChannel({required this.name, required this.url, this.logo});

  final String name;
  final String url;
  final String? logo;

  Map<String, dynamic> toJson() => {'name': name, 'url': url, 'logo': logo};

  factory IptvChannel.fromJson(Map<String, dynamic> m) => IptvChannel(
      name: (m['name'] ?? 'Channel') as String,
      url: (m['url'] ?? '') as String,
      logo: m['logo'] as String?);
}

List<IptvChannel> parseM3u(String raw) {
  final lines = raw.split(RegExp(r'\r?\n'));
  final out = <IptvChannel>[];
  String? pendingName;
  String? pendingLogo;
  for (var line in lines) {
    line = line.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTINF:')) {
      final attr = line.substring(line.indexOf(':') + 1);
      final comma = attr.lastIndexOf(',');
      final named =
          comma >= 0 ? attr.substring(comma + 1).trim() : attr.trim();
      pendingName = named.isEmpty ? 'Channel' : named;
      final logoMatch = RegExp('tvg-logo="([^"]*)"').firstMatch(attr);
      pendingLogo = logoMatch?.group(1);
    } else if (!line.startsWith('#')) {
      out.add(IptvChannel(
          name: pendingName ?? 'Channel', url: line, logo: pendingLogo));
      pendingName = null;
      pendingLogo = null;
    }
  }
  return out;
}
