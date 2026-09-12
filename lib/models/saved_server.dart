import 'dart:convert';

/// A saved streaming endpoint (NAS over WebDAV/HTTP, a direct link, an rtsp
/// camera...). Stored as a JSON list in the local store under the key
/// [kServersSettingKey] — the same shape the old app used.
const String kServersSettingKey = 'servers.list';

class SavedServer {
  final String name;
  final String url;

  const SavedServer({required this.name, required this.url});

  Map<String, String> toJson() => {'name': name, 'url': url};

  factory SavedServer.fromJson(Map<dynamic, dynamic> json) =>
      SavedServer(name: '${json['name'] ?? ''}', url: '${json['url'] ?? ''}');
}

/// Parses the stored JSON list. Anything malformed (empty, wrong type,
/// entries without a url) is dropped instead of throwing.
List<SavedServer> parseServersJson(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final e in decoded)
        if (e is Map && e['url'] != null && '${e['url']}'.isNotEmpty)
          SavedServer.fromJson(e),
    ];
  } catch (_) {
    return const [];
  }
}

String serversToJson(List<SavedServer> servers) =>
    jsonEncode([for (final s in servers) s.toJson()]);

/// Adds [server] unless the same url is already saved (dedupe by url).
List<SavedServer> addSavedServer(
  List<SavedServer> servers,
  SavedServer server,
) {
  if (servers.any((s) => s.url == server.url)) return servers;
  return [...servers, server];
}
