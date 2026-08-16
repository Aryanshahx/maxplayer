import '../services/native_bridge.dart';

/// Minimal crash journal so an "app closed unexpectedly" is no longer
/// invisible: the Dart-side error is stored in the native settings store
/// (plain strings) and shown ONCE on the next app launch, where the user
/// can copy it and send it for analysis.
///
/// NOTE: this catches Dart/framework errors. A native abort inside libmpv
/// or a decoder can't be caught here - those still need a logcat or the
/// Android tombstone, but in practice most unexpected closes surface as
/// Dart errors.
class CrashLog {
  CrashLog._();

  static const String _kCrashKey = 'crash.last';

  /// Records [error] (+ truncated [stack]) under [kind] ('flutter' for
  /// widget-tree errors, 'async' for uncaught zone errors, 'zone' for the
  /// outermost guard).
  static Future<void> record(
    String kind,
    String error,
    StackTrace? stack,
  ) async {
    try {
      final buf = StringBuffer()
        ..writeln('Max Player crash report')
        ..writeln('time: ${DateTime.now().toIso8601String()}')
        ..writeln('kind: $kind')
        ..writeln('error: $error')
        ..writeln('stack:');
      final frames = stack?.toString().split('\n') ?? const <String>[];
      buf.write(frames.take(24).join('\n'));
      var text = buf.toString();
      if (text.length > 6000) text = text.substring(0, 6000);
      await NativeBridge.saveSetting(_kCrashKey, text);
    } catch (_) {
      // Never let crash-reporting itself crash the app.
    }
  }

  /// Returns the last stored report and clears it (shown once).
  static Future<String?> takeLast() async {
    try {
      final s = await NativeBridge.loadSettings();
      final v = s[_kCrashKey];
      if (v == null || v.isEmpty) return null;
      await NativeBridge.saveSetting(_kCrashKey, '');
      return v;
    } catch (_) {
      return null;
    }
  }

  /// v34: an Android-layer crash ("Max Player has stopped" - e.g. at app
  /// start, before Dart even runs) is recorded to a file by the native
  /// Application class. Prefer that report over the Dart journal; either
  /// source is cleared when taken, so it is shown exactly once.
  static Future<String?> takeLastIncludingNative() async {
    try {
      final nativeReport = await NativeBridge.nativeCrashGet();
      if (nativeReport != null && nativeReport.isNotEmpty) {
        await NativeBridge.nativeCrashClear();
        return nativeReport;
      }
    } catch (_) {
      // fall through to the Dart journal
    }
    return takeLast();
  }
}
