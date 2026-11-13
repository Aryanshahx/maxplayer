import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

/// Crash forensics from day one (non-negotiable #3).
///
/// Appends JSONL events to `<docs>/logs/events.jsonl` and mirrors the
/// latest report-worthy event to `<docs>/logs/report.last`. Evidence must
/// survive even if no dialog ever appears.
class CrashLog {
  CrashLog._();

  static File? _eventsFile;
  static File? _reportFile;

  static Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    final logs = Directory('${dir.path}/logs');
    if (!logs.existsSync()) logs.createSync(recursive: true);
    _eventsFile = File('${logs.path}/events.jsonl');
    _reportFile = File('${logs.path}/report.last');
    _crashFile = File('${logs.path}/crash.last');
  }

  static File? _crashFile;
  static void captureCrash(
    String event,
    Object error,
    StackTrace? stack, {
    required bool fatal,
  }) {
    try {
      final report = jsonEncode({
        'id': List.generate(
          16,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join(),
        't': DateTime.now().toIso8601String(),
        'event': event,
        'fatal': fatal,
        'error': error.toString().substring(
          0,
          error.toString().length.clamp(0, 3000),
        ),
        'stack': (stack?.toString() ?? '').substring(
          0,
          (stack?.toString() ?? '').length.clamp(0, 9000),
        ),
      });
      _crashFile?.writeAsStringSync(report, flush: true);
    } catch (_) {}
  }

  static Future<String?> peekCrashReport() async {
    try {
      final f = _crashFile;
      return f != null && f.existsSync() ? await f.readAsString() : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearCrashReport(String expected) async {
    try {
      final f = _crashFile;
      if (f != null && f.existsSync() && await f.readAsString() == expected) {
        await f.delete();
      }
    } catch (_) {}
  }

  /// Log a breadcrumb (tap, route decision, engine error, ...).
  static void crumb(String event, [Map<String, Object?> data = const {}]) {
    _write({'t': DateTime.now().toIso8601String(), 'event': event, ...data});
  }

  /// Log an error worth investigating later. Also persisted to report.last
  /// so the evidence cannot be lost even when nothing visibly crashes.
  static void error(
    String event,
    Object e, [
    Map<String, Object?> data = const {},
  ]) {
    final report = jsonEncode({
      't': DateTime.now().toIso8601String(),
      'event': event,
      'error': e.toString(),
      ...data,
    });
    _writeRaw(report);
    unawaited(
      Future(() async {
        try {
          await _reportFile?.writeAsString('$report\n');
        } catch (_) {
          /* never throw from logging */
        }
      }),
    );
  }

  /// v1.0.1+65: ONE-SHOT report download — returns the last persisted
  /// error report (if any) and CLEARS it, so each crash is uploaded once.
  static Future<String?> takeReport() async {
    try {
      final f = _reportFile;
      if (f == null || !f.existsSync()) return null;
      final text = (await f.readAsString()).trim();
      await f.delete();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  static void _write(Map<String, Object?> entry) =>
      _writeRaw(jsonEncode(entry));

  static void _writeRaw(String line) {
    unawaited(
      Future(() async {
        try {
          await _eventsFile?.writeAsString('$line\n', mode: FileMode.append);
        } catch (_) {
          /* never throw from logging */
        }
      }),
    );
  }
}
