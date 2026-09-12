import 'dart:convert';

/// A saved network-storage connection (SMB / FTP / WebDAV), same shape the
/// old app persisted under `network.locations_v2`.
class NetworkLocation {
  final String name;
  final String protocol;
  final String host;
  final int port;
  final String path;
  final String username;
  final String password;

  const NetworkLocation({
    required this.name,
    required this.protocol,
    required this.host,
    this.port = 0,
    this.path = '',
    this.username = '',
    this.password = '',
  });

  String get streamUrl {
    final auth = username.isNotEmpty
        ? (password.isNotEmpty ? '$username:$password@' : '$username@')
        : '';
    final portStr = port > 0 ? ':$port' : '';
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return '$protocol://$auth$host$portStr$cleanPath';
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'protocol': protocol,
        'host': host,
        'port': port,
        'path': path,
        'username': username,
        'password': password,
      };

  factory NetworkLocation.fromJson(Map<String, dynamic> j) => NetworkLocation(
        name: '${j['name'] ?? ''}',
        protocol: '${j['protocol'] ?? 'smb'}',
        host: '${j['host'] ?? ''}',
        port: int.tryParse('${j['port'] ?? 0}') ?? 0,
        path: '${j['path'] ?? ''}',
        username: '${j['username'] ?? ''}',
        password: '${j['password'] ?? ''}',
      );
}

/// Parses the stored JSON list of network locations (drops malformed rows).
List<NetworkLocation> parseNetworkLocationsJson(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final e in decoded)
        if (e is Map && e['host'] != null && '${e['host']}'.isNotEmpty)
          NetworkLocation.fromJson(Map<String, dynamic>.from(e)),
    ];
  } catch (_) {
    return const [];
  }
}

String networkLocationsToJson(List<NetworkLocation> locations) =>
    jsonEncode([for (final l in locations) l.toJson()]);
