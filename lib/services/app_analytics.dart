import 'dart:async';
import 'dart:convert';
import 'country_lookup.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v1.0.1+63: Firebase activity tracking — ANONYMOUS aggregate counters
/// only. What is tracked: app opens, installs, plays (video / stream /
/// IPTV), ad impressions, playback failures with a coarse error kind and
/// the failing HOST (e.g. "example.com") so dead IPTV sources are visible.
///
/// What is NEVER tracked: file names, folders, video titles, stream URLs
/// (host only), search terms, or anything that identifies a person.
///
/// The four config values below are CLIENT config, not secrets — they ship
/// inside every installed app; security comes from firestore.rules.
/// Everything here no-ops safely when offline/unconfigured: counters are
/// fire-and-forget and can never crash the app.
class AppAnalytics {
  AppAnalytics._();
  static final AppAnalytics instance = AppAnalytics._();

  static const String kFirebaseApiKey =
      'AIzaSyDOz1FWZPP4aOzfiRYvE6xy8CF2mXiXPOY';
  static const String kFirebaseAppId =
      '1:1080871289145:android:be220a998bdbcc1a0ca8e8';
  static const String kFirebaseProjectId = 'max-player-cd43d';
  static const String kFirebaseSenderId = '1080871289145';

  /// Report tag — bump with the app version each release.
  static const String kAppVersionTag = '1.0.1+70';

  /// true only once Firebase is actually usable (configured + initialised).
  static final ValueNotifier<bool> ready = ValueNotifier<bool>(false);
  bool _triedInit = false;

  static bool get configured =>
      !kFirebaseApiKey.startsWith('PASTE_') &&
      !kFirebaseProjectId.startsWith('PASTE_');

  /// Fire-and-forget AFTER runApp(). Never throws.
  Future<void> ensureInit() async {
    if (ready.value || _triedInit || !configured) return;
    _triedInit = true;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: kFirebaseApiKey,
          appId: kFirebaseAppId,
          projectId: kFirebaseProjectId,
          messagingSenderId: kFirebaseSenderId,
        ),
      );
      ready.value = true;
    } catch (e) {
      debugPrint('Firebase init skipped: $e');
    }
  }

  /// v1.0.1+63/+65: one call from main() — waits for init, then counts
  /// the app open (+ time-of-day bucket); the install + its COUNTRY are
  /// counted ONCE per device ever (local flags).
  Future<void> trackAppOpen() async {
    await ensureInit();
    try {
      log('app_open');
      bumpDaily(appOpens: 1, appOpenHour: DateTime.now().hour);
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('aa.installCounted') ?? false)) {
        bumpTotal('installs');
        await prefs.setBool('aa.installCounted', true);
      }
      // Independent of install counting: upgrades also contribute one new IP sample.
      unawaited(_recordIpCountry());
    } catch (_) {
      /* telemetry must never break startup */
    }
  }

  bool _countryLookupRunning = false;
  Future<void> _recordIpCountry() async {
    if (_countryLookupRunning || _db == null) return;
    _countryLookupRunning = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('aa.ipCountryV1.counted') ?? false) return;
      final country = await lookupIpCountry();
      if (country.isEmpty) {
        return; // Unknown/offline: retry next launch, never use locale.
      }
      final write = _db!.collection('stats').doc('total').set({
        'ip_c_$country': FieldValue.increment(1),
      }, SetOptions(merge: true));
      unawaited(write.catchError((Object _) {}));
      await prefs.setString('aa.ipCountryV1.code', country);
      await prefs.setBool('aa.ipCountryV1.counted', true);
    } catch (_) {
      // Best-effort aggregate; never block playback or push initialization.
    } finally {
      _countryLookupRunning = false;
    }
  }

  static const featureKeys = <String>[
    'discover',
    'private',
    'folders',
    'playlists',
    'audio',
    'network',
    'cloud',
    'quickShare',
  ];
  void trackFeatureOpen(String key) {
    if (!featureKeys.contains(key)) return;
    final db = _db;
    if (db == null) return;
    final day = DateTime.now().toIso8601String().substring(0, 10);
    unawaited(
      db
          .collection('stats')
          .doc('daily_$day')
          .set({
            'feature_$key': FieldValue.increment(1),
          }, SetOptions(merge: true))
          .catchError((Object _) {}),
    );
  }

  Future<bool> uploadCapturedCrash(String text) async {
    await ensureInit();
    final db = _db;
    if (db == null) return false;
    final parsed = jsonDecode(text) as Map<String, dynamic>;
    final id = parsed['id'] as String?;
    if (id == null || !RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) return false;
    try {
      await db.collection('reports').doc('crash_$id').set({
        'type': 'crash',
        'ts': DateTime.now().toIso8601String(),
        'app': kAppVersionTag,
        'kind': 'captured_app_error',
        'text': text.length > 14000 ? text.substring(0, 14000) : text,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// v1.0.1+68: session-time ping — called when the app backgrounds.
  /// Aggregated as daily sessionSeconds + sessions (avg = sec/sessions).
  void trackSession(int seconds) {
    if (seconds <= 0) return;
    try {
      log('session_end', {'seconds': seconds});
      bumpDaily(sessionSeconds: seconds, sessions: 1);
    } catch (_) {}
  }

  /// v1.0.1+68: report uploader (crash breadcrumbs / player failures).
  /// Firestore queues the write offline and flushes it when the network
  /// returns — dead-zone friendly by design.
  void sendReport({
    required String type,
    required String text,
    String? host,
    String kind = '',
  }) {
    final db = _db;
    if (db == null) return;
    try {
      unawaited(
        db.collection('reports').add({
          'type': type,
          'ts': DateTime.now().toIso8601String(),
          'app': kAppVersionTag,
          if (host != null && host.isNotEmpty) 'host': host,
          if (kind.isNotEmpty) 'kind': kind,
          'text': text.length > 1200 ? text.substring(0, 1200) : text,
        }),
      );
    } catch (_) {}
  }

  /// v1.0.1+68: admin→app broadcast ("notification with image") — the app
  /// fetches this once per open; unseen ids pop an in-app dialog.
  Future<Map<String, String>?> fetchBroadcast() async {
    final db = _db;
    if (db == null) return null;
    try {
      final doc = await db.collection('broadcasts').doc('latest').get();
      final d = doc.data();
      if (d == null) return null;
      final id = '${d['id'] ?? ''}';
      final title = '${d['title'] ?? ''}';
      final body = '${d['body'] ?? ''}';
      final image = '${d['image'] ?? ''}';
      if (id.isEmpty || title.isEmpty) return null;
      return {'id': id, 'title': title, 'body': body, 'image': image};
    } catch (_) {
      return null;
    }
  }

  /// 'IN' from a Dart locale string like en_IN / en-IN / en_IN.UTF-8.
  static String countryFromLocale(String locale) {
    final parts = locale.split('.').first.replaceAll('-', '_').split('_');
    if (parts.length < 2) return '';
    final c = parts[1].replaceAll(RegExp('[^A-Za-z]'), '').toUpperCase();
    return c.length == 2 ? c : '';
  }

  FirebaseAnalytics? get _a => ready.value ? FirebaseAnalytics.instance : null;
  FirebaseFirestore? get _db => ready.value ? FirebaseFirestore.instance : null;

  /// Analytics event (Firebase console shows these live). No-op unconfigured.
  void log(String name, [Map<String, Object>? params]) {
    try {
      unawaited(
        _a?.logEvent(name: name, parameters: params ?? const {}) ??
            Future.value(),
      );
    } catch (_) {
      /* never throw from telemetry */
    }
  }

  static String _dayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Daily aggregate bumps powering the admin dashboard. One merged write,
  /// field-increments only — safe offline (SDK queues), no-op unconfigured.
  void bumpDaily({
    int appOpens = 0,
    int adImpressions = 0,
    int videosPlayed = 0,
    int streamsOpened = 0,
    int iptvOpened = 0,
    int iptvPlayed = 0,
    int playFailed = 0,
    String failKind = '',
    int sessionSeconds = 0,
    int sessions = 0,
    int appOpenHour = -1,
  }) {
    final db = _db;
    if (db == null) return;
    try {
      final day = _dayKey();
      unawaited(
        db.collection('stats').doc('daily_$day').set({
          'date': day,
          if (appOpens > 0) 'appOpens': FieldValue.increment(appOpens),
          if (adImpressions > 0)
            'adImpressions': FieldValue.increment(adImpressions),
          if (videosPlayed > 0)
            'videosPlayed': FieldValue.increment(videosPlayed),
          if (streamsOpened > 0)
            'streamsOpened': FieldValue.increment(streamsOpened),
          if (iptvOpened > 0) 'iptvOpened': FieldValue.increment(iptvOpened),
          if (iptvPlayed > 0) 'iptvPlayed': FieldValue.increment(iptvPlayed),
          if (sessionSeconds > 0)
            'sessionSeconds': FieldValue.increment(sessionSeconds),
          if (sessions > 0) 'sessions': FieldValue.increment(sessions),
          if (appOpenHour >= 0 && appOpenHour <= 23)
            'h_$appOpenHour': FieldValue.increment(1),
          if (playFailed > 0) ...{
            'playFailed': FieldValue.increment(playFailed),
            if (failKind.isNotEmpty)
              'fail_${sanitizeHost(failKind)}': FieldValue.increment(
                playFailed,
              ),
          },
        }, SetOptions(merge: true)),
      );
    } catch (_) {
      /* statistics must never crash the app */
    }
  }

  void bumpTotal(String field) {
    final db = _db;
    if (db == null) return;
    try {
      unawaited(
        db.collection('stats').doc('total').set({
          field: FieldValue.increment(1),
        }, SetOptions(merge: true)),
      );
    } catch (_) {}
  }

  /// Failing-host tally (stats/failHosts) — powers the "dead sources"
  /// table on the admin dashboard. Host only, never the full URL.
  /// Stores per host: `c_<key>` = count, `k_<key>__<kind>` = kind split,
  /// `n_<key>` = readable host name.
  void bumpFailHost(String host, [String kind = '']) {
    final db = _db;
    if (db == null || host.isEmpty) return;
    try {
      final key = sanitizeHost(host);
      unawaited(
        db.collection('stats').doc('failHosts').set({
          'c_$key': FieldValue.increment(1),
          if (kind.isNotEmpty) 'k_${key}__$kind': FieldValue.increment(1),
          'n_$key': host,
        }, SetOptions(merge: true)),
      );
    } catch (_) {}
  }

  /// Coarse error bucket for the daily failure counters.
  /// timeout = server unreachable, refused = port closed/server down,
  /// http = 403/404/format errors, other = codec/everything else.
  static String classifyError(String message) {
    final m = message.toLowerCase();
    if (m.contains('timed out') || m.contains('timeout')) return 'timeout';
    if (m.contains('refused')) return 'refused';
    if (m.contains('403') ||
        m.contains('404') ||
        m.contains('http') ||
        m.contains('forbidden')) {
      return 'http';
    }
    return 'other';
  }

  /// Firestore field-safe host key: lowercase, [a-z0-9] kept, rest → '_'.
  static String sanitizeHost(String host) {
    final out = StringBuffer();
    for (final c in host.toLowerCase().trim().split('')) {
      final ok = RegExp(r'[a-z0-9]').hasMatch(c);
      out.write(ok ? c : '_');
    }
    return out.toString();
  }

  /// Host of an http(s) URL, else null (local files return null — nothing
  /// about local paths ever leaves the device).
  static String? hostOf(String path) {
    final uri = Uri.tryParse(path);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri.host.isEmpty ? null : uri.host;
  }
}
