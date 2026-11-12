import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maxplayer/services/push_image_loader.dart';

class Headers implements HttpHeaders {
  Headers(this.location);
  final String? location;
  @override
  String? value(String name) =>
      name == HttpHeaders.locationHeader ? location : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Response extends Stream<List<int>> implements HttpClientResponse {
  Response(
    this.body, {
    this.statusCode = 200,
    this.contentLength = -1,
    String? location,
  }) : headers = Headers(location);
  final Stream<List<int>> body;
  @override
  final int statusCode;
  @override
  final int contentLength;
  @override
  final HttpHeaders headers;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => body.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Request implements HttpClientRequest {
  Request(this.response);
  final Response response;
  @override
  set followRedirects(bool value) {}
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Client implements HttpClient {
  Client(this.responses);
  final List<Response> responses;
  final List<Uri> requested = [];
  bool closed = false;
  @override
  set connectionTimeout(Duration? value) {}
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested.add(url);
    return Request(responses.removeAt(0));
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final jpeg = [255, 216, 255, 224, 0, 1, 255, 217];
  Response image() => Response(Stream.value(jpeg));
  test('loads JPEG bytes independent of Content-Type header', () async {
    final client = Client([image()]);
    expect(
      await downloadPushImage(
        'https://example.test/i',
        clientFactory: () => client,
      ),
      jpeg,
    );
    expect(client.closed, isTrue);
  });
  test('refuses advertised bodies over 1 MiB', () async {
    final client = Client([
      Response(Stream.value(jpeg), contentLength: 1048577),
    ]);
    expect(
      await downloadPushImage(
        'https://example.test/i',
        clientFactory: () => client,
      ),
      isNull,
    );
    expect(client.closed, isTrue);
  });
  test('enforces streamed byte cap with unknown length', () async {
    final client = Client([
      Response(Stream.fromIterable([jpeg, List.filled(100, 0)])),
    ]);
    expect(
      await downloadPushImage(
        'https://example.test/i',
        clientFactory: () => client,
        maxBytes: 20,
      ),
      isNull,
    );
  });
  test('rejects HTML returned with successful HTTP status', () async {
    final client = Client([
      Response(Stream.value('<html>not an image</html>'.codeUnits)),
    ]);
    expect(
      await downloadPushImage(
        'https://example.test/i',
        clientFactory: () => client,
      ),
      isNull,
    );
  });
  test('follows an HTTPS redirect', () async {
    final client = Client([
      Response(
        const Stream.empty(),
        statusCode: 302,
        location: 'https://cdn.test/i',
      ),
      image(),
    ]);
    expect(
      await downloadPushImage(
        'https://example.test/i',
        clientFactory: () => client,
      ),
      jpeg,
    );
    expect(client.requested.last.host, 'cdn.test');
  });
  test('rejects redirect downgrade to HTTP', () async {
    final client = Client([
      Response(
        const Stream.empty(),
        statusCode: 302,
        location: 'http://cdn.test/i',
      ),
    ]);
    expect(
      await downloadPushImage(
        'https://example.test/i',
        clientFactory: () => client,
      ),
      isNull,
    );
    expect(client.requested.length, 1);
  });
  test('redirect loops are bounded', () async {
    final client = Client(
      List.generate(
        4,
        (_) =>
            Response(const Stream.empty(), statusCode: 302, location: '/again'),
      ),
    );
    expect(
      await downloadPushImage(
        'https://example.test/i',
        clientFactory: () => client,
      ),
      isNull,
    );
    expect(client.requested.length, 4);
  });
  test('times out stalled image stream and closes client', () async {
    final stream = StreamController<List<int>>();
    final client = Client([Response(stream.stream)]);
    expect(
      await downloadPushImage(
        'https://example.test/i',
        clientFactory: () => client,
        timeout: const Duration(milliseconds: 20),
      ),
      isNull,
    );
    expect(client.closed, isTrue);
    unawaited(stream.close());
  });
  test('recognises JPEG PNG WEBP but not arbitrary data', () {
    expect(hasPushImageSignature(jpeg), isTrue);
    expect(hasPushImageSignature([137, 80, 78, 71, 13, 10, 26, 10]), isTrue);
    expect(hasPushImageSignature('RIFF0000WEBP'.codeUnits), isTrue);
    expect(hasPushImageSignature('random bytes'.codeUnits), isFalse);
  });
}
