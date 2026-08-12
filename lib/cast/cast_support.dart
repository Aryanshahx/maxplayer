/// Pure, unit-testable building blocks for DLNA/UPnP casting.
///
/// Everything here is dependency-free and contains no I/O, so the wire
/// formats (SSDP headers, device-description XML, SOAP envelopes, DIDL-Lite
/// metadata, DLNA time format) can be locked down by unit tests without a
/// TV. The sockets/HTTP that use these live in `cast_state.dart` and
/// `cast_file_server.dart`.
library;

/// One discovered DLNA renderer (a TV, Android box, ...).
class DlnaDevice {
  /// Display name from the device description ("Living Room TV").
  final String name;

  /// The SSDP LOCATION header (device description URL) - used to dedupe.
  final String location;

  /// Absolute AVTransport control URL we POST SOAP actions to.
  final String controlUrl;

  const DlnaDevice({
    required this.name,
    required this.location,
    required this.controlUrl,
  });
}

// ---------------------------------------------------------------------------
// SSDP (discovery)
// ---------------------------------------------------------------------------

/// M-SEARCH request body for a given search target.
String buildMSearchRequest(String st) =>
    'M-SEARCH * HTTP/1.1\r\n'
    'HOST: 239.255.255.250:1900\r\n'
    'MAN: "ssdp:discover"\r\n'
    'MX: 2\r\n'
    'ST: $st\r\n'
    '\r\n';

/// Header lookup in an SSDP response/notify (case-insensitive names).
String? ssdpHeader(String datagram, String name) {
  final lower = name.toLowerCase();
  for (final line in datagram.split(RegExp(r'\r?\n'))) {
    final idx = line.indexOf(':');
    if (idx <= 0) continue;
    if (line.substring(0, idx).trim().toLowerCase() == lower) {
      final v = line.substring(idx + 1).trim();
      return v.isEmpty ? null : v;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Device description XML (UPnP)
// ---------------------------------------------------------------------------

String _xmlUnescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');

/// Parses a UPnP device description into a [DlnaDevice], or returns null
/// when the device has no AVTransport service (i.e. it is not a renderer
/// we can cast to - routers, speakers-only, etc.).
DlnaDevice? parseDeviceDescription(String xml, String location) {
  final nameMatch =
      RegExp(r'<friendlyName>([^<]*)</friendlyName>').firstMatch(xml);
  final name = nameMatch != null
      ? _xmlUnescape(nameMatch.group(1)!.trim())
      : 'DLNA device';

  // Find the <service> block that offers AVTransport (any version).
  String? controlPath;
  for (final m in RegExp(
    r'<service>(.*?)</service>',
    dotAll: true,
  ).allMatches(xml)) {
    final block = m.group(1)!;
    if (!block.contains('AVTransport')) continue;
    final cm = RegExp(r'<controlURL>([^<]+)</controlURL>').firstMatch(block);
    if (cm != null) {
      controlPath = cm.group(1)!.trim();
      break;
    }
  }
  if (controlPath == null || controlPath.isEmpty) return null;

  // controlURL is usually root-relative ("/dmr/avtransport") - resolve it
  // against the scheme://host:port of the description URL.
  final String controlUrl;
  if (controlPath.startsWith('http://') || controlPath.startsWith('https://')) {
    controlUrl = controlPath;
  } else {
    final loc = Uri.parse(location);
    final base = '${loc.scheme}://${loc.host}:${loc.port}';
    controlUrl = controlPath.startsWith('/')
        ? '$base$controlPath'
        : '$base/$controlPath';
  }

  return DlnaDevice(name: name, location: location, controlUrl: controlUrl);
}

// ---------------------------------------------------------------------------
// SOAP over HTTP (AVTransport control)
// ---------------------------------------------------------------------------

/// XML-escape a value embedded in SOAP / DIDL payloads.
String xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

const String avTransportServiceType =
    'urn:schemas-upnp-org:service:AVTransport:1';

/// Builds a SOAP envelope for [action] with [args] as <Key>value</Key>
/// entries (InstanceID is always first - every AVTransport action needs it).
String buildSoapEnvelope(String action, List<MapEntry<String, String>> args) {
  final buf = StringBuffer()
    ..write('<?xml version="1.0" encoding="utf-8"?>')
    ..write('<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">')
    ..write('<s:Body>')
    ..write('<u:$action xmlns:u="$avTransportServiceType">')
    ..write('<InstanceID>0</InstanceID>');
  for (final a in args) {
    buf.write('<${a.key}>${xmlEscape(a.value)}</${a.key}>');
  }
  buf
    ..write('</u:$action>')
    ..write('</s:Body></s:Envelope>');
  return buf.toString();
}

/// Pulls one tag value out of a SOAP response body (<RelTime>0:03:12</..>).
/// Tolerates namespaced tags (<m:RelTime>) and whitespace.
String? soapTag(String body, String tag) {
  final m = RegExp(
    '<(?:[A-Za-z0-9_]+:)?$tag>([^<]*)</(?:[A-Za-z0-9_]+:)?$tag>',
  ).firstMatch(body);
  if (m == null) return null;
  final v = m.group(1)!.trim();
  return v.isEmpty ? null : v;
}

// ---------------------------------------------------------------------------
// DIDL-Lite metadata (describes the media handed to the TV)
// ---------------------------------------------------------------------------

/// Content-type a TV understands, derived from the file extension.
String mimeForExtension(String path) {
  final q = path.split('?').first; // drop query when path is a URL
  final ext = q.contains('.') ? q.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'mp4':
    case 'm4v':
      return 'video/mp4';
    case 'mkv':
      return 'video/x-matroska';
    case 'webm':
      return 'video/webm';
    case 'avi':
    case 'divx':
      return 'video/x-msvideo';
    case 'mov':
      return 'video/quicktime';
    case 'flv':
    case 'f4v':
      return 'video/x-flv';
    case 'wmv':
    case 'asf':
      return 'video/x-ms-wmv';
    case 'ts':
    case 'm2ts':
    case 'mts':
      return 'video/mp2t';
    case '3gp':
    case '3gpp':
      return 'video/3gpp';
    case 'mpg':
    case 'mpeg':
    case 'vob':
      return 'video/mpeg';
    case 'rmvb':
    case 'rm':
      return 'video/vnd.rn-realvideo';
    default:
      // Unknown: mp4 is the most widely accepted container claim.
      return 'video/mp4';
  }
}

/// DIDL-Lite <item> describing the video. Some renderers reject playback
/// when CurrentURIMetadata is empty, so we always send this.
String buildDidlMetadata({
  required String title,
  required String videoUrl,
  required String mime,
  String? subsUrl,
}) {
  final buf = StringBuffer()
    ..write('<DIDL-Lite '
        'xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"')
    ..write(subsUrl == null ? '' : ' xmlns:sec="http://www.sec.co.kr/"')
    ..write('>')
    ..write('<item id="0" parentID="-1" restricted="1">')
    ..write('<dc:title>${xmlEscape(title)}</dc:title>')
    ..write('<upnp:class>object.item.videoItem</upnp:class>')
    ..write('<res protocolInfo="http-get:*:$mime:*">'
        '${xmlEscape(videoUrl)}</res>');
  if (subsUrl != null) {
    // Samsung-style external subtitle pointer.
    buf.write('<sec:CaptionInfoEx sec:type="srt">${xmlEscape(subsUrl)}'
        '</sec:CaptionInfoEx>');
  }
  buf.write('</item></DIDL-Lite>');
  return buf.toString();
}

// ---------------------------------------------------------------------------
// DLNA time format (H:MM:SS[.FFF]) used by Seek / GetPositionInfo
// ---------------------------------------------------------------------------

String formatRelTime(Duration d) {
  final totalSecs = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = totalSecs ~/ 3600;
  final m = (totalSecs % 3600) ~/ 60;
  final s = totalSecs % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return '$h:${two(m)}:${two(s)}';
}

/// Parses "0:03:12", "00:03:12.000" etc. Returns null for the sentinel
/// values TVs send when a property is unavailable (NOT_IMPLEMENTED/_X_...).
Duration? parseRelTime(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty || s.toUpperCase().contains('NOT_IMPLEMENTED')) return null;
  final parts = s.split(':');
  if (parts.length != 3) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final secPart = double.tryParse(parts[2]);
  if (h == null || m == null || secPart == null) return null;
  return Duration(
    hours: h,
    minutes: m,
    seconds: secPart.floor(),
    milliseconds: ((secPart - secPart.floor()) * 1000).round(),
  );
}
