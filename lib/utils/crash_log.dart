import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  }

  /// Log a breadcrumb (tap, route decision, engine error, ...).
  static void crumb(String event, [Map<String, Object?> data = const {}]) {
    _write({'t': DateTime.now().toIso8601String(), 'event': event, ...data});
  }

  /// Log an error worth investigating later. Also persisted to report.last
  /// so the evidence cannot be lost even when nothing visibly crashes.
  static void error(String event, Object e,
      [Map<String, Object?> data = const {}]) {
    final report = jsonEncode({
      't': DateTime.now().toIso8601String(),
      'event': event,
      'error': e.toString(),
      ...data,
    });
    _writeRaw(report);
    unawaited(Future(() async {
      try {
        await _reportFile?.writeAsString('$report\n');
      } catch (_) {/* never throw from logging */}
    }));
  }

  static void _write(Map<String, Object?> entry) => _writeRaw(jsonEncode(entry));

  static void _writeRaw(String line) {
    unawaited(Future(() async {
      try {
        await _eventsFile?.writeAsString('$line\n', mode: FileMode.append);
      } catch (_) {/* never throw from logging */}
    }));
  }
}
