import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/video_track.dart';
import '../state/media_player_state.dart';
import '../state/video_library_state.dart';

/// One remote playback beacon received from another Max Player device
/// on the same local Wi-Fi.
class RemoteResumeBeacon {
  final String device;
  final String title;
  final String path;
  final int positionSecs;
  final int durationSecs;
  final int timestampMs;
  final String host;

  const RemoteResumeBeacon({
    required this.device,
    required this.title,
    required this.path,
    required this.positionSecs,
    required this.durationSecs,
    required this.timestampMs,
    required this.host,
  });

  factory RemoteResumeBeacon.fromJson(Map<String, dynamic> json, String host) {
    return RemoteResumeBeacon(
      device: json['device'] as String? ?? 'Nearby Device',
      title: json['title'] as String? ?? '',
      path: json['path'] as String? ?? '',
      positionSecs: (json['positionSecs'] as num?)?.toInt() ?? 0,
      durationSecs: (json['durationSecs'] as num?)?.toInt() ?? 0,
      timestampMs: (json['ts'] as num?)?.toInt() ?? 0,
      host: host,
    );
  }

  Map<String, dynamic> toJson() => {
        'app': 'maxplayer',
        'device': device,
        'title': title,
        'path': path,
        'positionSecs': positionSecs,
        'durationSecs': durationSecs,
        'ts': timestampMs,
      };
}

/// v69 C3 & v70 C4: Local Wi-Fi Resume-Sync & Wear OS / Remote companion service.
///
/// 1. Broadcasts/listens for UDP beacons on port 52325 so phones/tablets/TVs
///    on the same Wi-Fi can hand off and resume playback with 1 tap.
/// 2. Runs a lightweight HTTP server on port 52326 for Wear OS smartwatches
///    and local remote control (Play/Pause, Seek, Volume, Status).
class ResumeSyncService {
  static final ResumeSyncService instance = ResumeSyncService._();
  ResumeSyncService._();

  static const int kBeaconPort = 52325;
  static const int kRemoteHttpPort = 52326;

  RawDatagramSocket? _udpSocket;
  HttpServer? _httpServer;
  Timer? _beaconTimer;
  MediaPlayerState? _player;

  final ValueNotifier<RemoteResumeBeacon?> remoteBeacon = ValueNotifier(null);

  bool get isRunning => _udpSocket != null;

  /// Starts the UDP discovery and Wear OS companion HTTP service.
  Future<void> start(MediaPlayerState player) async {
    _player = player;
    if (_udpSocket != null) return;
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kBeaconPort,
        reuseAddress: true,
        reusePort: false,
      );
      _udpSocket?.broadcastEnabled = true;
      _udpSocket?.listen(_handleUdpMessage);

      _beaconTimer?.cancel();
      _beaconTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => _sendBeacon(),
      );

      _httpServer = await HttpServer.bind(
        InternetAddress.anyIPv4,
        kRemoteHttpPort,
      );
      _httpServer?.listen(_handleHttpRequest);
    } catch (_) {}
  }

  void _handleUdpMessage(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _udpSocket?.receive();
    if (dg == null) return;
    try {
      final text = utf8.decode(dg.data);
      final json = jsonDecode(text);
      if (json is Map<String, dynamic> && json['app'] == 'maxplayer') {
        final b = RemoteResumeBeacon.fromJson(json, dg.address.address);
        // Ignore self-broadcasts if identical track & position.
        final curr = _player?.currentTrack;
        if (curr != null &&
            curr.title == b.title &&
            (_player?.position.inSeconds ?? 0) == b.positionSecs) {
          return;
        }
        if (b.title.isNotEmpty && b.positionSecs > 5) {
          remoteBeacon.value = b;
        }
      }
    } catch (_) {}
  }

  void _sendBeacon() {
    final p = _player;
    if (p == null || !p.isPlaying || p.currentTrack == null) return;
    final track = p.currentTrack!;
    final beacon = RemoteResumeBeacon(
      device: Platform.localHostname,
      title: track.title,
      path: track.path,
      positionSecs: p.position.inSeconds,
      durationSecs: p.duration.inSeconds,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      host: '127.0.0.1',
    );
    try {
      final bytes = utf8.encode(jsonEncode(beacon.toJson()));
      _udpSocket?.send(
        bytes,
        InternetAddress('255.255.255.255'),
        kBeaconPort,
      );
    } catch (_) {}
  }

  /// Handles incoming Wear OS companion / HTTP remote control requests.
  void _handleHttpRequest(HttpRequest request) async {
    final p = _player;
    final path = request.uri.path;
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('Access-Control-Allow-Origin', '*');

    if (p == null) {
      request.response.statusCode = 503;
      request.response.write(jsonEncode({'error': 'Player not initialized'}));
      await request.response.close();
      return;
    }

    try {
      if (path == '/status') {
        final data = {
          'title': p.currentTrack?.title ?? '',
          'path': p.currentTrack?.path ?? '',
          'isPlaying': p.isPlaying,
          'position': p.position.inSeconds,
          'duration': p.duration.inSeconds,
          'volume': p.volume,
        };
        request.response.write(jsonEncode(data));
      } else if (path == '/play') {
        if (!p.isPlaying) await p.togglePlay();
        request.response.write(jsonEncode({'status': 'playing'}));
      } else if (path == '/pause') {
        if (p.isPlaying) await p.pause();
        request.response.write(jsonEncode({'status': 'paused'}));
      } else if (path == '/toggle') {
        await p.togglePlay();
        request.response.write(jsonEncode({'isPlaying': p.isPlaying}));
      } else if (path == '/next') {
        await p.nextTrack();
        request.response.write(jsonEncode({'status': 'next'}));
      } else if (path == '/prev') {
        await p.prevTrack();
        request.response.write(jsonEncode({'status': 'prev'}));
      } else if (path == '/seek') {
        final delta = int.tryParse(request.uri.queryParameters['delta'] ?? '');
        final to = int.tryParse(request.uri.queryParameters['to'] ?? '');
        if (to != null) {
          await p.seek(Duration(seconds: to));
        } else if (delta != null) {
          await p.seek(p.position + Duration(seconds: delta));
        }
        request.response.write(jsonEncode({'position': p.position.inSeconds}));
      } else if (path == '/volume') {
        final level = double.tryParse(request.uri.queryParameters['level'] ?? '');
        if (level != null) {
          await p.setVolume(level);
        }
        request.response.write(jsonEncode({'volume': p.volume}));
      } else {
        request.response.statusCode = 404;
        request.response.write(jsonEncode({'error': 'Not found'}));
      }
    } catch (e) {
      request.response.statusCode = 500;
      request.response.write(jsonEncode({'error': '$e'}));
    }
    await request.response.close();
  }

  /// Resumes [beacon] on this local device by matching a library track.
  Future<bool> resumeOnThisDevice(
    RemoteResumeBeacon beacon,
    VideoLibraryState library,
    MediaPlayerState player,
  ) async {
    VideoTrack? match;
    for (final v in library.videos) {
      if (v.title.toLowerCase() == beacon.title.toLowerCase() ||
          v.path == beacon.path) {
        match = v;
        break;
      }
    }
    if (match != null) {
      await player.setPlaylistAndPlay([match], 0);
      await player.seek(Duration(seconds: beacon.positionSecs));
      remoteBeacon.value = null;
      return true;
    }
    return false;
  }

  void stop() {
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _udpSocket?.close();
    _udpSocket = null;
    _httpServer?.close(force: true);
    _httpServer = null;
  }
}
