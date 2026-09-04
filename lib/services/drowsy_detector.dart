/// v100: front-camera drowsiness + look-away detection (both strictly
/// opt-in, off by default).
///
/// Uses the `camera` plugin (front lens, low resolution, no audio, no
/// preview widget - frames only) + ML Kit face detection (on-device; its
/// model downloads once via Play Services, then works offline).
///
/// Two independent watchers share one camera session:
/// * sleep watch: face visible + BOTH eyes closed continuously for 30 s
///   -> [DrowsyEvent.sleepPause]. A missing face FREEZES the timer
///   (looking away is not sleeping).
/// * look-away watch: no face (or extreme head yaw) for 3 s ->
///   [DrowsyEvent.lookAwayPause]; face back afterwards ->
///   [DrowsyEvent.lookBackResume].
///
/// Everything degrades silently: no camera, denied permission (checked by
/// the UI before arming), missing ML model, or a bad frame just means no
/// events fire. [ensureStarted] reports success so the player state can
/// tell the user once when the camera itself will not start.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Events the detector raises. The player state decides what each means
/// (it knows whether anything is playing).
enum DrowsyEvent {
  /// Eyes closed for the full sleep window.
  sleepPause,

  /// Looked away for the full away window.
  lookAwayPause,

  /// Face back after a look-away pause (resume hint).
  lookBackResume,
}

class DrowsyDetector {
  /// Eye-open probability below this counts as "closed" (ML Kit documents
  /// the value as a confidence, not a measurement - 0.4 is conservative).
  static const double kClosedThreshold = 0.4;

  /// Continuous closed-eye time before a sleep event (the requested 30 s).
  static const Duration kSleepSeconds = Duration(seconds: 30);

  /// Continuous face-absent time before a look-away event.
  static const Duration kAwaySeconds = Duration(seconds: 3);

  /// |head yaw| beyond this counts as "looking away" even with a face.
  static const double kAwayYawDegrees = 45.0;

  /// Frames arrive at ~15-30/s; every Nth frame is classified (CPU stays
  /// trivial next to video decode).
  static const int kFrameStride = 6;

  void Function(DrowsyEvent event)? onEvent;

  /// Every streamed frame is also offered here (air gestures share the
  /// session; a throwing subscriber never breaks face watching).
  void Function(CameraImage image)? onFrame;

  bool _wantHands = false;

  /// Rotation of the owned camera for frame consumers (MediaPipe).
  int get cameraRotation =>
      _controller?.description.sensorOrientation ?? 0;

  CameraController? _controller;
  FaceDetector? _faceDetector;
  bool _wantSleep = false;
  bool _wantLookAway = false;
  bool _foreground = true;
  bool _busy = false;
  int _frameCount = 0;
  bool _starting = false;

  DateTime? _closedSince;
  bool _sleepFired = false;
  DateTime? _awaySince;
  bool _awayFired = false;

  bool get isRunning => _controller?.value.isInitialized ?? false;

  /// (Re)configures which watchers are armed. Starts the camera when at
  /// least one is armed AND the app is foregrounded; stops it otherwise.
  Future<void> configure({
    required bool sleep,
    required bool lookAway,
    bool hands = false,
  }) async {
    _wantSleep = sleep;
    _wantLookAway = lookAway;
    _wantHands = hands;
    if (!_wantSleep && !_wantLookAway && !_wantHands) {
      await stop();
      return;
    }
    if (_foreground) await ensureStarted();
  }

  /// The app left / returned. The camera never runs in the background
  /// (battery + the OS camera-indicator rules).
  Future<void> setForeground(bool fg) async {
    _foreground = fg;
    if (!fg) {
      await stop();
    } else if (_wantSleep || _wantLookAway || _wantHands) {
      await ensureStarted();
    }
  }

  /// Starts the shared camera session. True when frames will flow.
  Future<bool> ensureStarted() async {
    if (isRunning) return true;
    if (_starting) return false;
    _starting = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return false;
      final front = cameras.where(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      final desc = front.isNotEmpty ? front.first : cameras.first;
      final controller = CameraController(
        desc,
        ResolutionPreset.low,
        enableAudio: false,
      );
      await controller.initialize();
      if (!controller.value.isInitialized) {
        await controller.dispose();
        return false;
      }
      _faceDetector ??= FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          enableTracking: true,
          performanceMode: FaceDetectorMode.fast,
          minFaceSize: 0.15,
        ),
      );
      _controller = controller;
      reset();
      await controller.startImageStream(_onFrame);
      return true;
    } catch (_) {
      await stop();
      return false;
    } finally {
      _starting = false;
    }
  }

  void _onFrame(CameraImage image) {
    if (onFrame != null) {
      try {
        onFrame!(image);
      } catch (_) {}
    }
    if (_busy) return;
    _frameCount++;
    if (_frameCount % kFrameStride != 0) return;
    _busy = true;
    unawaited(_classify(image).whenComplete(() => _busy = false));
  }

  Future<void> _classify(CameraImage image) async {
    final detector = _faceDetector;
    final controller = _controller;
    if (detector == null || controller == null) return;
    try {
      final bytes = _toNv21(image);
      final rotation = InputImageRotationValue.fromRawValue(
            controller.description.sensorOrientation,
          ) ??
          InputImageRotation.rotation0deg;
      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.width,
      );
      final faces = await detector.processImage(
        InputImage.fromBytes(bytes: bytes, metadata: metadata),
      );
      _update(faces.isEmpty ? null : faces.first);
    } catch (_) {
      // A bad frame is dropped - the next one tries again.
    }
  }

  /// YUV_420_888 (3 planes, arbitrary strides) -> packed NV21 (Y + VU).
  /// Converted explicitly instead of requesting NV21 from the plugin, so
  /// this works whatever pixel layout the camera backend hands over.
  static Uint8List _toNv21(CameraImage image) {
    if (image.planes.length < 3) throw StateError('expected 3 planes');
    final w = image.width;
    final h = image.height;
    final out = Uint8List(w * h + (w * h) ~/ 2);
    final y = image.planes[0];
    var o = 0;
    for (var r = 0; r < h; r++) {
      out.setRange(o, o + w, y.bytes, r * y.bytesPerRow);
      o += w;
    }
    // NV21 interleaves V before U, both subsampled 2x2.
    final u = image.planes[1];
    final v = image.planes[2];
    final uRow = u.bytesPerRow;
    final vRow = v.bytesPerRow;
    final uPix = u.bytesPerPixel ?? 1;
    final vPix = v.bytesPerPixel ?? 1;
    for (var r = 0; r < h ~/ 2; r++) {
      var uOff = r * uRow;
      var vOff = r * vRow;
      for (var c = 0; c < w ~/ 2; c++) {
        out[o++] = v.bytes[vOff];
        out[o++] = u.bytes[uOff];
        uOff += uPix;
        vOff += vPix;
      }
    }
    return out;
  }

  void _update(Face? face, [DateTime? nowOverride]) {
    final now = nowOverride ?? DateTime.now();
    final yaw = face?.headEulerAngleY?.abs() ?? 0.0;
    final away = face == null || yaw > kAwayYawDegrees;

    // --- sleep watch: needs a face; absence freezes the timer. ---
    if (_wantSleep && !_sleepFired) {
      final left = face?.leftEyeOpenProbability;
      final right = face?.rightEyeOpenProbability;
      final closed = face != null &&
          left != null &&
          right != null &&
          left < kClosedThreshold &&
          right < kClosedThreshold;
      if (closed) {
        _closedSince ??= now;
        if (now.difference(_closedSince!) >= kSleepSeconds) {
          _sleepFired = true;
          onEvent?.call(DrowsyEvent.sleepPause);
        }
      } else if (face != null) {
        // Eyes verifiably open: the streak (and the fired flag) reset.
        _closedSince = null;
        _sleepFired = false;
      }
    }

    // --- look-away watch. ---
    if (_wantLookAway) {
      if (away) {
        _awaySince ??= now;
        if (!_awayFired && now.difference(_awaySince!) >= kAwaySeconds) {
          _awayFired = true;
          onEvent?.call(DrowsyEvent.lookAwayPause);
        }
      } else {
        _awaySince = null;
        if (_awayFired) {
          _awayFired = false;
          onEvent?.call(DrowsyEvent.lookBackResume);
        }
      }
    }
  }

  /// Clears streaks (fresh arm, or a new video).
  void reset() {
    _closedSince = null;
    _sleepFired = false;
    _awaySince = null;
    _awayFired = false;
  }

  Future<void> stop() async {
    reset();
    final controller = _controller;
    _controller = null;
    try {
      if (controller != null) {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
        await controller.dispose();
      }
    } catch (_) {}
  }

  Future<void> dispose() async {
    onEvent = null;
    await stop();
    try {
      await _faceDetector?.close();
    } catch (_) {}
    _faceDetector = null;
  }
}
