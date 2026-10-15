import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// v1.0.1+58: Firebase bootstrap + analytics + daily counters for the
/// referral program and the admin dashboard.
///
/// PASTE YOUR FIREBASE VALUES BELOW (Firebase console -> Project settings
/// -> "Your apps" -> web app config). They are CLIENT config values, not
/// secrets — they ship inside every shipped app; security comes from
/// firestore.rules, never from hiding these strings.
///
/// While the placeholders remain, EVERYTHING here safely no-ops: no
/// analytics, no counters, no crashes — same rule as the ads SDK.
class AppAnalytics {
  AppAnalytics._();
  static final AppAnalytics instance = AppAnalytics._();

  // TODO(firebase): create the project for Max Player and paste the four
  // values, then bump +59. The app runs fully WITHOUT them.
  static const String kFirebaseApiKey = 'AIzaSyDOz1FWZPP4aOzfiRYvE6xy8CF2mXiXPOY';
  static const String kFirebaseAppId = '1:1080871289145:android:be220a998bdbcc1a0ca8e8';
  static const String kFirebaseProjectId = 'max-player-cd43d';
  static const String kFirebaseSenderId = '1080871289145';

  /// true only once Firebase is actually usable (configured + initialised).
  static final ValueNotifier<bool> ready = ValueNotifier<bool>(false);
  bool _triedInit = false;

  static bool get configured =>
      !kFirebaseApiKey.startsWith('PASTE_') &&
      !kFirebaseProjectId.startsWith('PASTE_');

  /// Fire-and-forget AFTER runApp() (called from ReferralService.init too).
  /// Never throws.
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

  /// Daily aggregate bumps powering the admin website. One batched write,
  /// field-increments only — safe offline (SDK queues), no-op unconfigured.
  void bumpDaily({int appOpens = 0, int adImpressions = 0, int shares = 0}) {
    final db = _db;
    if (db == null) return;
    try {
      final now = DateTime.now();
      final day =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      unawaited(
        db.collection('stats').doc('daily_$day').set({
          'date': day,
          if (appOpens > 0) 'appOpens': FieldValue.increment(appOpens),
          if (adImpressions > 0)
            'adImpressions': FieldValue.increment(adImpressions),
          if (shares > 0) 'shares': FieldValue.increment(shares),
        }, SetOptions(merge: true)),
      );
    } catch (_) {
      /* offline/statistics must never crash the app */
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
}
