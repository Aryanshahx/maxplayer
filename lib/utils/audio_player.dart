import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:photo_manager/photo_manager.dart';

import 'app_volume.dart';
import 'crash_log.dart';
import 'player_settings.dart';

// v1.0.1 fix 3: the repeat-mode enum and the pure next/prev queue math moved
// to queue_math.dart so the VIDEO player can use the exact same logic (it now
// has shuffle/repeat buttons too). Re-exported here — every existing import
// of this file keeps compiling untouched.
import 'queue_math.dart';

export 'queue_math.dart';


/// Pure (unit-tested): raw mpv/engine errors ("Error decoding audio",
/// decoder init failures…) mapped to something an actual human can act on.
/// The raw text always lands in CrashLog regardless.
String describeAudioEngineError(String raw) {
  final r = raw.toLowerCase();
  if (r.contains('decod') || r.contains('codec') || r.contains('format')) {
    return 'Decode hiccup — auto-resuming. If this file keeps failing, it '
        'may be corrupt or use a codec this device build lacks.';
  }
  if (r.contains('timed out') || r.contains('timeout') || r.contains('eof')) {
    return 'The file stopped responding mid-play (corrupt or truncated?).';
  }
  if (r.contains('network') || r.contains('socket') || r.contains('http')) {
    return 'Connection problem while playing.';
  }
  final t = raw.trim();
  return t.isEmpty ? 'Playback error' : t;
}

/// Process-lifetime audio playback engine: created once and reused across
/// opens. v1.0.1+4: the Audio tab mini bar was removed — the Now Playing
/// screen now PAUSES the engine when it closes, so playback never runs
/// without a UI to control it.
class AudioPlayerHolder extends ChangeNotifier {
  AudioPlayerHolder._() {
    AppVolume.instance.addListener(_applyVolume);
  }

  static final AudioPlayerHolder instance = AudioPlayerHolder._();

  Player? _player;
  final List<StreamSubscription<dynamic>> _subs = [];
  final Map<String, String> _pathCache = {};
  int _token = 0;
  int _engineRecoveries = 0;

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
      if (v && error != null) {
        // Playback recovered — drop the stale ⚠ badge. Before this, ONE
        // mid-song decoder hiccup left "Error decoding audio" on screen
        // forever even though music was playing again.
        error = null;
        _engineRecoveries = 0;
      }
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
      error = describeAudioEngineError(e);
      CrashLog.error('audio.engine_error', e);
      _recoverFromEngineError();
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
    _engineRecoveries = 0;
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

  /// mpv on Android throws "Error decoding audio" mid-song on decoder
  /// resets (bluetooth/focus changes, edgy codecs) — a seek+play nudge at
  /// the current position recovers almost every time. Bounded at 2 tries
  /// per track so a genuinely dead file can't loop forever.
  void _recoverFromEngineError() {
    final p = _player;
    if (p == null || !hasTrack || !playing || _engineRecoveries >= 2) return;
    _engineRecoveries++;
    final at = position;
    unawaited(Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (_player != p || !hasTrack) return;
      CrashLog.crumb(
          'audio.recover_attempt', {'at_ms': at.inMilliseconds});
      p.seek(at).then((_) => p.play());
    }));
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

  /// Pause without touching the queue or position — called when the full
  /// Now Playing screen closes (no mini bar anymore, so invisible music
  /// would be uncontrollable).
  Future<void> pause() async {
    final p = _player;
    if (p == null) return;
    unawaited(p.pause());
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
