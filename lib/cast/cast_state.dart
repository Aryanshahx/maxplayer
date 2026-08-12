import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/native_bridge.dart';
import 'cast_file_server.dart';
import 'cast_support.dart';

enum CastPhase {
  /// Nothing happening.
  idle,

  /// SSDP discovery in flight.
  scanning,

  /// Scan finished; [devices] may be empty.
  scanDone,

  /// Handing the video to the chosen TV.
  connecting,

  /// TV is (or should be) playing; remote controls are live.
  casting,

  /// Something failed - [error] explains what, in plain words.
  error,
}

/// Owns one DLNA casting session: SSDP discovery of renderers, the SOAP
/// AVTransport control channel, the embedded file server the TV pulls the
/// video from, and 2-second position polling for the remote-control UI.
///
/// Everything is guarded: with no Wi-Fi, no devices, or a grumpy TV the
/// state machine lands in [CastPhase.error] instead of throwing.
class CastState extends ChangeNotifier {
  CastPhase phase = CastPhase.idle;
  List<DlnaDevice> devices = const [];
  DlnaDevice? current;
  String? error;

  // Polled from the TV while casting (remote-control slider).
  Duration tvPosition = Duration.zero;
  Duration tvDuration = Duration.zero;
  bool tvPlaying = false;

  final CastFileServer _server = CastFileServer();
  Timer? _pollTimer;
  bool _disposed = false;

  String? get videoUrl => _server.videoUrl;

  // ---------------------------------------------------------------------------
  // Discovery
  // ---------------------------------------------------------------------------

  /// Multicasts SSDP M-SEARCH for ~4 seconds and describes whatever
  /// answers. Safe to call repeatedly.
  Future<void> scan() async {
    if (phase == CastPhase.scanning || phase == CastPhase.connecting) return;
    phase = CastPhase.scanning;
    devices = const [];
    error = null;
    notifyListeners();

    await NativeBridge.setMulticastLock(true);
    final locations = <String>{};
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)
          .timeout(const Duration(seconds: 3));
      final s = socket; // bind succeeded, non-nullable from here on
      final target = InternetAddress('239.255.255.250');
      final packets = [
        ascii.encode(
            buildMSearchRequest('urn:schemas-upnp-org:device:MediaRenderer:1')),
        ascii.encode(buildMSearchRequest('ssdp:all')),
      ];

      final sub = s.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? dg;
        while ((dg = s.receive()) != null) {
          final text = utf8.decode(dg!.data, allowMalformed: true);
          final loc = ssdpHeader(text, 'location');
          if (loc != null && loc.startsWith('http')) locations.add(loc);
        }
      });

      // Three waves - multicast UDP can drop packets.
      for (var wave = 0; wave < 3; wave++) {
        for (final p in packets) {
          try {
            s.send(p, target, 1900);
          } catch (_) {}
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      await sub.cancel();
    } catch (e) {
      phase = CastPhase.error;
      error = 'Wi-Fi scan failed (${e.runtimeType}). Connect both phone and '
          'TV to the same Wi-Fi and retry.';
      notifyListeners();
      socket?.close();
      await NativeBridge.setMulticastLock(false);
      return;
    }
    socket.close();
    await NativeBridge.setMulticastLock(false);

    // Fetch each responder's description (in parallel) and keep renderers.
    final found = await Future.wait([
      for (final loc in locations) _describe(loc),
    ]);
    final seen = <String>{};
    final list = <DlnaDevice>[];
    for (final d in found) {
      if (d == null) continue;
      if (!seen.add(d.controlUrl)) continue; // same TV via two LOCATIONs
      list.add(d);
    }
    if (_disposed) return;
    devices = list;
    phase = CastPhase.scanDone;
    notifyListeners();
  }

  Future<DlnaDevice?> _describe(String location) async {
    final client = HttpClient();
    try {
      client.connectionTimeout = const Duration(seconds: 4);
      final req = await client
          .getUrl(Uri.parse(location))
          .timeout(const Duration(seconds: 4));
      final res = await req.close().timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return null;
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 4));
      return parseDeviceDescription(body, location);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Connect + control
  // ---------------------------------------------------------------------------

  /// Starts the file server (for local files; streams are handed to the TV
  /// directly), points the TV at the video and presses play.
  Future<void> connect(
    DlnaDevice device, {
    required String videoPath,
    required String title,
    String? subsPath,
  }) async {
    phase = CastPhase.connecting;
    current = device;
    error = null;
    tvPosition = Duration.zero;
    tvDuration = Duration.zero;
    tvPlaying = false;
    notifyListeners();

    try {
      String videoUrl;
      String? subsUrl;
      final mime = mimeForExtension(videoPath);
      if (videoPath.startsWith('http://') || videoPath.startsWith('https://')) {
        // Network stream: the TV pulls it straight from the internet; the
        // phone only acts as the remote control.
        videoUrl = videoPath;
        subsUrl = null;
      } else {
        final hasSubs = subsPath != null && File(subsPath).existsSync();
        final ok = await _server.start(
          videoPath: videoPath,
          videoMime: mime,
          subsPath: hasSubs ? subsPath : null,
        );
        if (!ok) {
          throw StateError('could not start the phone-side media server '
              '(no Wi-Fi?)');
        }
        videoUrl = _server.videoUrl!;
        subsUrl = _server.subsUrl;
      }

      final metadata = buildDidlMetadata(
        title: title,
        videoUrl: videoUrl,
        mime: mime,
        subsUrl: subsUrl,
      );
      await _soap(device.controlUrl, 'SetAVTransportURI', [
        MapEntry('CurrentURI', videoUrl),
        MapEntry('CurrentURIMetadata', metadata),
      ]);
      await _soap(device.controlUrl, 'Play', [const MapEntry('Speed', '1')]);

      if (_disposed) return;
      phase = CastPhase.casting;
      tvPlaying = true;
      notifyListeners();
      _startPolling();
    } catch (e) {
      await _server.stop();
      if (_disposed) return;
      phase = CastPhase.error;
      current = null;
      error = 'The TV rejected the stream '
          '(${e.toString().split('\n').first}). The video format may be '
          'unsupported by this TV, or the connection dropped.';
      notifyListeners();
    }
  }

  Future<void> togglePlayPause() async {
    final device = current;
    if (phase != CastPhase.casting || device == null) return;
    final action = tvPlaying ? 'Pause' : 'Play';
    // Optimistic UI; the next poll corrects it if the TV disagrees.
    tvPlaying = !tvPlaying;
    notifyListeners();
    try {
      await _soap(device.controlUrl, action, [
        if (action == 'Play') const MapEntry('Speed', '1'),
      ]);
    } catch (_) {}
  }

  Future<void> seekTo(Duration target) async {
    final device = current;
    if (phase != CastPhase.casting || device == null) return;
    tvPosition = target;
    notifyListeners();
    try {
      await _soap(device.controlUrl, 'Seek', [
        const MapEntry('Unit', 'REL_TIME'),
        MapEntry('Target', formatRelTime(target)),
      ]);
    } catch (_) {}
  }

  /// Stops playback on the TV and tears everything down.
  Future<void> stopCast({bool tellTv = true}) async {
    _pollTimer?.cancel();
    _pollTimer = null;
    final device = current;
    if (tellTv && device != null && phase == CastPhase.casting) {
      try {
        await _soap(device.controlUrl, 'Stop', []);
      } catch (_) {}
    }
    await _server.stop();
    if (_disposed) return;
    current = null;
    tvPosition = Duration.zero;
    tvDuration = Duration.zero;
    tvPlaying = false;
    phase = CastPhase.idle;
    error = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // SOAP plumbing + polling
  // ---------------------------------------------------------------------------

  Future<String> _soap(
    String controlUrl,
    String action,
    List<MapEntry<String, String>> args,
  ) async {
    final client = HttpClient();
    try {
      client.connectionTimeout = const Duration(seconds: 6);
      final req = await client
          .postUrl(Uri.parse(controlUrl))
          .timeout(const Duration(seconds: 6));
      req.headers.set(
        HttpHeaders.contentTypeHeader,
        'text/xml; charset="utf-8"',
      );
      req.headers.set(
        'SOAPACTION',
        '"$avTransportServiceType#$action"',
      );
      req.write(buildSoapEnvelope(action, args));
      final res = await req.close().timeout(const Duration(seconds: 6));
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) {
        throw SocketException('SOAP $action -> HTTP ${res.statusCode}');
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    // First poll right away so the slider has real values quickly.
    _poll();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  Future<void> _poll() async {
    final device = current;
    if (_disposed || phase != CastPhase.casting || device == null) return;
    try {
      final info = await _soap(device.controlUrl, 'GetTransportInfo', []);
      final state = soapTag(info, 'CurrentTransportState');
      final posBody = await _soap(device.controlUrl, 'GetPositionInfo', []);
      final rel = parseRelTime(soapTag(posBody, 'RelTime'));
      final dur = parseRelTime(soapTag(posBody, 'TrackDuration'));
      if (_disposed) return;
      if (state == 'PLAYING') {
        tvPlaying = true;
      } else if (state != 'TRANSITIONING') {
        tvPlaying = false; // PAUSED_PLAYBACK / STOPPED / NO_MEDIA_PRESENT
      } // TRANSITIONING: keep the previous play/pause state.
      if (rel != null) tvPosition = rel;
      if (dur != null) tvDuration = dur;
      notifyListeners();
    } catch (_) {
      // Transient network hiccup - the next tick retries.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    current = null;
    unawaited(_server.stop());
    super.dispose();
  }
}
