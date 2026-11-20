import 'dart:io';
import 'dart:convert';

enum DesktopNetworkProtocol { windowsShare, webFile }

class DesktopNetworkLocation {
  final String name, host, path;
  final DesktopNetworkProtocol protocol;
  final bool secure;
  final int? port;
  const DesktopNetworkLocation(
      {required this.name,
      required this.host,
      required this.path,
      required this.protocol,
      this.secure = true,
      this.port});
  String get display => protocol == DesktopNetworkProtocol.windowsShare
      ? '\\\\$host\\${_segments.join('\\')}'
      : uri.toString();
  List<String> get _segments =>
      path.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).toList();
  Uri get uri => Uri(
      scheme: secure ? 'https' : 'http',
      host: host,
      port: port,
      pathSegments: _segments);
  String get source => protocol == DesktopNetworkProtocol.windowsShare
      ? display
      : uri.toString();
  void validate() {
    if (name.trim().isEmpty || name.length > 100) {
      throw const FormatException('Enter a name (up to 100 characters).');
    }
    if (host.trim() != host ||
        host.isEmpty ||
        host.length > 253 ||
        RegExp(r'[\s/\\@?#\x00-\x1f]').hasMatch(host)) {
      throw const FormatException(
          'Enter only the server host or IP address, without a protocol or credentials.');
    }
    if (host.contains(':')
        ? InternetAddress.tryParse(host)?.type != InternetAddressType.IPv6
        : !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(host)) {
      throw const FormatException('Enter a valid server name or IP address.');
    }
    if (host == '.' ||
        host == '?' ||
        host.contains(':') && !host.contains('::')) {
      throw const FormatException(
          'Enter the server without a port. Use the Port field for HTTP(S).');
    }
    if (_segments.isEmpty ||
        _segments.any((s) =>
            s == '.' ||
            s == '..' ||
            RegExp(r'[<>:"|?*\x00-\x1f]').hasMatch(s))) {
      throw const FormatException(
          'Enter a share/file path without traversal, query tokens or reserved characters.');
    }
    if (protocol == DesktopNetworkProtocol.windowsShare && host.contains(':')) {
      throw const FormatException(
          'For SMB, use the Windows server name or IPv4 address.');
    }
    if (port != null && (port! < 1 || port! > 65535)) {
      throw const FormatException('Port must be between 1 and 65535.');
    }
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'host': host,
        'path': path,
        'protocol': protocol.name,
        'secure': secure,
        if (port != null) 'port': port
      };
  static DesktopNetworkLocation? fromJson(Object? value) {
    if (value is! Map) return null;
    if (value['name'] is! String ||
        value['host'] is! String ||
        value['path'] is! String ||
        value['secure'] is! bool) {
      return null;
    }
    if (value['port'] != null && value['port'] is! int) return null;
    final protocol = switch (value['protocol']) {
      'windowsShare' => DesktopNetworkProtocol.windowsShare,
      'webFile' => DesktopNetworkProtocol.webFile,
      _ => null
    };
    if (protocol == null) return null;
    final location = DesktopNetworkLocation(
        name: value['name'],
        host: value['host'],
        path: value['path'],
        protocol: protocol,
        secure: value['secure'],
        port: value['port']);
    try {
      location.validate();
      return location;
    } on FormatException {
      return null;
    }
  }
}

List<DesktopNetworkLocation> decodeNetworkLocations(String? raw) {
  try {
    final value = jsonDecode(raw ?? '[]');
    if (value is! List) return [];
    return [
      for (final entry in value.take(200))
        if (DesktopNetworkLocation.fromJson(entry)
            case final DesktopNetworkLocation location)
          location
    ];
  } catch (_) {
    return [];
  }
}
