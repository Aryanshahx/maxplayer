import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

bool validPushImage(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}

bool hasPushImageSignature(List<int> b) {
  if (b.length >= 3 && b[0] == 255 && b[1] == 216 && b[2] == 255) return true;
  if (b.length >= 8 &&
      b[0] == 137 &&
      b[1] == 80 &&
      b[2] == 78 &&
      b[3] == 71 &&
      b[4] == 13 &&
      b[5] == 10 &&
      b[6] == 26 &&
      b[7] == 10) {
    return true;
  }
  return b.length >= 12 &&
      String.fromCharCodes(b.take(4)) == 'RIFF' &&
      String.fromCharCodes(b.skip(8).take(4)) == 'WEBP';
}

/// HTTPS only, bounded streaming and deadline, including HTTPS redirects.
/// Check bytes instead of trusting/misinterpreting the host's MIME header.
Future<Uint8List?> downloadPushImage(
  String url, {
  HttpClient Function()? clientFactory,
  Duration timeout = const Duration(seconds: 10),
  int maxBytes = 1048576,
}) async {
  if (!validPushImage(url)) return null;
  final client = (clientFactory ?? HttpClient.new)()
    ..connectionTimeout = timeout;
  try {
    return await (() async {
      var uri = Uri.parse(url);
      for (var redirects = 0; redirects <= 3; redirects++) {
        final request = await client.getUrl(uri);
        request.followRedirects = false;
        final response = await request.close();
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final next = response.headers.value(HttpHeaders.locationHeader);
          if (next == null || redirects == 3) return null;
          uri = uri.resolve(next);
          if (!validPushImage(uri.toString())) return null;
          continue;
        }
        if (response.statusCode != 200 || response.contentLength > maxBytes) {
          return null;
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (bytes.length + chunk.length > maxBytes) return null;
          bytes.add(chunk);
        }
        final result = bytes.takeBytes();
        return hasPushImageSignature(result) ? result : null;
      }
      return null;
    })().timeout(timeout);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
