import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:photo_manager/photo_manager.dart';

import 'app_volume.dart';
import 'crash_log.dart';
import 'player_settings.dart';

enum AudioRepeatMode { off, all, one }

/// Pure next-track math (unit-tested — no engine involved).
/// Returns -1 when playback should STOP after the current track.
/// [rand] is injected for tests: it must map [count) -> 0..count-1.
int audioNextIndex({
  required int current,
  required int count,
  required bool shuffle,
  required AudioRepeatMode repeat,
  int Function(int maxExclusive)? rand,
}) {
  if (count <= 0 || current < 0) return -1;
  if (repeat == AudioRepeatMode.one) return current;
  if (shuffle) {
    final r = rand ?? Random().nextInt;
    var next = r(count);
    // Avoid the "shuffle plays the same song again" anti-feel when there
    // is more than one candidate.
    if (count > 1 && next == current) next = (next + 1) % count;
    return next;
  }
  final n = current + 1;
  if (n >= count) return repeat == AudioRepeatMode.all ? 0 : -1;
  return n;
}

/// Pure previous-track math: classic player semantics — wrap to the last
/// track from the first only under repeat-all, otherwise stay at 0.
int audioPrevIndex({
  required int current,
  required int count,
  required AudioRepeatMode repeat,
}) {
  if (count <= 0 || current < 0) return -1;
  if (current > 0) return current - 1;
  return repeat == AudioRepeatMode.all ? count - 1 : 0;
}

/// Process-lifetime audio playback engine (v1.0.21): created once, kept
/// alive when the full player screen closes, so music keeps going while
/// you browse the Audio tab (the mini bar there drives it back up).
class AudioPlayerHolder extends ChangeNotifier {
  AudioPlayerHolder._() {
    AppVolume.instance.addListener(_applyVolume);
  }

  static final AudioPlayerHolder instance = AudioPlayerHolder._();

  Player? _player;
  final List<StreamSubscription<dynamic>> _subs = [];
  final Map<String, String> _pathCache = {};
  int _token = 0;

  List<AssetEntity> _queue = const [];
  int currentIndex = -1;

  bool playing = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool shuffle = false;
  AudioRepeatMode repeat = AudioRepeatMode.off;
  double rate = 1.0;
  String? error;

  bool get hasTrack => currentIndex >= 0 && currentIndex < _queue.length;
  AssetEntity? get current => hasTrack ? _queue[currentIndex] : null;
  String get currentTitle => current?.title ?? 'Audio';
  int get count => _queue.length;

  Future<void> _ensureEngine() async {
    if (_player != null) return;
    final p = Player();
    _player = p;
    _subs.add(p.stream.playing.listen((v) {
      playing = v;
      notifyListeners();
    }));
    _subs.add(p.stream.position.listen((v) {
      position = v;
      notifyListeners();
    }));
    _subs.add(p.stream.duration.listen((v) {
      duration = v;
      notifyListeners();
    }));
    _subs.add(p.stream.completed.listen((done) {
      if (!done) return;
      final next = audioNextIndex(
        current: currentIndex,
        count: count,
        shuffle: shuffle,
        repeat: repeat,
      );
      if (next < 0) {
        position = duration;
        notifyListeners();
        return;
      }
      if (next == currentIndex && repeat == AudioRepeatMode.one) {
        unawaited(seek(Duration.zero).then((_) => play()));
      } else {
        unawaited(_playIndex(next));
      }
    }));
    _subs.add(p.stream.error.listen((e) {
      error = e;
      CrashLog.error('audio.engine_error', e);
      notifyListeners();
    }));
  }

  /// Replaces the queue and starts [start]. The queue is a LIST OF ASSETS;
  /// file paths resolve lazily per track (cached) so opening a 400-song
  /// library costs one file lookup, not 400.
  Future<void> setQueue(List<AssetEntity> queue, int start) async {
    _queue = List<AssetEntity>.from(queue);
    currentIndex = -1;
    if (_queue.isEmpty) {
      notifyListeners();
      return;
    }
    await _playIndex(start.clamp(0, _queue.length - 1).toInt());
  }

  Future<void> _playIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final token = ++_token;
    await _ensureEngine();
    final asset = _queue[index];
    error = null;
    try {
      var path = _pathCache[asset.id];
      path ??= (await asset.file)?.path;
      if (path == null) throw StateError('no backing file');
      if (token != _token) return; // superseded while resolving
      final p = _player!;
      await p.open(Media(path), play: true);
      if (token != _token) return;
      await _mpvSetProp(p, 'volume-max', '200');
      currentIndex = index;
      position = Duration.zero;
      _applyVolume();
      unawaited(p.setRate(rate));
      CrashLog.crumb('audio.play', {'i': index, 'title': asset.title});
      notifyListeners();
    } catch (e) {
      CrashLog.error('audio.open_failed', e, {'id': asset.id});
      if (token != _token) return;
      error = 'Could not play this file';
      // Skip ahead on broken files rather than dying on a landmine.
      final next = audioNextIndex(
          current: index, count: count, shuffle: false, repeat: repeat);
      if (next >= 0 && next != index) {
        unawaited(_playIndex(next));
      }
      notifyListeners();
    }
  }

  Future<void> _mpvSetProp(Player p, String key, String value) async {
    try {
      final platform = p.platform;
      if (platform != null) {
        await (platform as dynamic).setProperty(key, value);
      }
    } catch (e) {
      CrashLog.error('audio.mpv_set_failed', e, {'key': key, 'value': value});
    }
  }

  void _applyVolume() {
    final p = _player;
    if (p == null) return;
    unawaited(_mpvSetProp(
        p, 'volume', AppVolume.instance.mpvGain.round().toString()));
  }

  bool get boostEnabled => PlayerSettings.instance.volumeBoost;

  Future<void> toggle() async {
    final p = _player;
    if (p == null || !hasTrack) return;
    unawaited(p.playOrPause());
  }

  Future<void> play() async {
    final p = _player;
    if (p == null) return;
    unawaited(p.play());
  }

  Future<void> next() async {
    final n = audioNextIndex(
        current: currentIndex, count: count, shuffle: shuffle, repeat: repeat);
    if (n >= 0) await _playIndex(n);
  }

  Future<void> prev() async {
    // Classic: past ~3s in, "prev" restarts the current track instead.
    if (position.inSeconds > 3 && hasTrack) {
      await seek(Duration.zero);
      return;
    }
    final n = audioPrevIndex(
        current: currentIndex, count: count, repeat: repeat);
    if (n >= 0) await _playIndex(n);
  }

  Future<void> playIndex(int i) => _playIndex(i);

  Future<void> seek(Duration d) async {
    final p = _player;
    if (p == null) return;
    position = d;
    notifyListeners();
    unawaited(p.seek(d));
  }

  void setShuffle(bool v) {
    shuffle = v;
    notifyListeners();
  }

  void cycleRepeat() {
    repeat = AudioRepeatMode
        .values[(repeat.index + 1) % AudioRepeatMode.values.length];
    notifyListeners();
  }

  Future<void> setSpeed(double r) async {
    rate = r;
    notifyListeners();
    final p = _player;
    if (p != null) unawaited(p.setRate(r));
  }
}
