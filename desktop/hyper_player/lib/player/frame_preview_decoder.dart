import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Independent muted, paused decoder; never seeks the main player. Local files
/// only (no stream requests, private-vault material, screenshots on disk/history).
/// The Windows renderer must still be validated with real codec fixtures.
class FramePreviewDecoder {
  final _cache = <String, Uint8List>{};
  int _cacheBytes = 0;
  Player? _player;
  VideoController? _video;
  String? _source;
  bool _disposed = false;
  bool _running = false;
  Timer? _idle;
  ({String source, Duration position, Completer<Uint8List?> reply})? _pending;
  Future<Uint8List?> frame(String source, Duration position) {
    if (_disposed || !Platform.isWindows) return Future.value();
    final cacheKey = '$source|${position.inSeconds}';
    final cached = _cache.remove(cacheKey);
    if (cached != null) {
      _cache[cacheKey] = cached;
      return Future.value(cached);
    }
    _idle?.cancel();
    _pending?.reply.complete(null);
    final reply = Completer<Uint8List?>();
    _pending = (source: source, position: position, reply: reply);
    if (!_running) unawaited(_drain());
    return reply.future;
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (!_disposed && _pending != null) {
        final request = _pending!;
        _pending = null;
        final result = await _decode(request.source, request.position);
        if (result != null && !_disposed) {
          final key = '${request.source}|${request.position.inSeconds}';
          final old = _cache.remove(key);
          _cacheBytes -= old?.length ?? 0;
          _cache[key] = result;
          _cacheBytes += result.length;
          while (_cache.length > 48 || _cacheBytes > 12 * 1024 * 1024) {
            _cacheBytes -= _cache.remove(_cache.keys.first)!.length;
          }
        }
        request.reply.complete(_disposed ? null : result);
      }
    } finally {
      _running = false;
      if (!_disposed) {
        _idle = Timer(const Duration(seconds: 15), () => unawaited(_release()));
      }
    }
  }

  Future<Uint8List?> _decode(String source, Duration position) async {
    final uri = Uri.tryParse(source);
    if (_disposed ||
        uri?.isScheme('http') == true ||
        uri?.isScheme('https') == true) {
      return null;
    }
    try {
      if (!await File(source).exists()) return null;
      final player = _player ??= Player(
          configuration: const PlayerConfiguration(
              muted: true,
              bufferSize: 4 * 1024 * 1024,
              title: 'Hyper frame preview',
              protocolWhitelist: ['file']));
      _video ??= VideoController(player,
          configuration: const VideoControllerConfiguration(
              width: 320, height: 180, enableHardwareAcceleration: false));
      await _video!.platform.future.timeout(const Duration(seconds: 4));
      if (_disposed) return null;
      final native = player.platform;
      if (native is! NativePlayer) return null;
      if (_source != source) {
        await native.setProperty('aid', 'no');
        await native.setProperty('sid', 'no');
        await native.setProperty('vf', 'scale=320:-2');
        await player
            .open(Media(source, start: position), play: false)
            .timeout(const Duration(seconds: 4));
        _source = source;
      }
      if (_disposed) return null;
      await player.seek(position).timeout(const Duration(seconds: 3));
      final stop = DateTime.now().add(const Duration(seconds: 3));
      while (!_disposed && DateTime.now().isBefore(stop)) {
        final seeking = await native
            .getProperty('seeking')
            .timeout(const Duration(seconds: 1));
        final actual = double.tryParse(await native
            .getProperty('time-pos')
            .timeout(const Duration(seconds: 1)));
        if (seeking == 'no' &&
            actual != null &&
            (actual * 1000 - position.inMilliseconds).abs() < 1000) {
          final image = await player
              .screenshot(format: 'image/jpeg')
              .timeout(const Duration(seconds: 2));
          if (_disposed) return null;
          return image != null && image.length <= 4 * 1024 * 1024
              ? image
              : null;
        }
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      return null;
    } catch (_) {
      _source = null;
      return null;
    }
  }

  Future<void> _release() async {
    final player = _player;
    _player = null;
    _video = null;
    _source = null;
    try {
      await player?.dispose();
    } catch (_) {/* Native teardown best effort. */}
  }

  Future<void> dispose() async {
    _disposed = true;
    _cache.clear();
    _cacheBytes = 0;
    _idle?.cancel();
    _pending?.reply.complete(null);
    _pending = null;
    await _release();
  }
}
