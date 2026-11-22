import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-only eligibility. No ratings, review text or success claims are stored.
class ReviewEligibility {
  static bool allows({
    required DateTime now,
    required DateTime firstUse,
    required int sessions,
    required int seconds,
    required int attempts,
    DateTime? lastAttempt,
  }) =>
      !now.isBefore(firstUse.add(const Duration(days: 3))) &&
      sessions >= 3 &&
      seconds >= 1200 &&
      attempts < 3 &&
      (lastAttempt == null ||
          !now.isBefore(lastAttempt.add(const Duration(days: 120))));
}

class ReviewPrompt {
  ReviewPrompt._();
  static final instance = ReviewPrompt._();
  static const prefix = 'play.review.v1.';
  bool _busy = false;

  Future<void> recordFirstUse() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey('${prefix}first')) {
        await prefs.setInt(
          '${prefix}first',
          DateTime.now().millisecondsSinceEpoch,
        );
      }
    } catch (_) {
      /* Review must not affect playback/startup. */
    }
  }

  /// Call after leaving playback, never interrupt playback or ask for stars.
  /// A qualifying session needs a minute of foreground, non-buffering playback.
  Future<void> afterPlayback(
    int seconds, {
    required bool Function() canPresent,
  }) async {
    if (_busy ||
        seconds < 60 ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _busy = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final first =
          prefs.getInt('${prefix}first') ?? now.millisecondsSinceEpoch;
      await prefs.setInt('${prefix}first', first);
      final sessions = (prefs.getInt('${prefix}sessions') ?? 0) + 1;
      final total = (prefs.getInt('${prefix}seconds') ?? 0) + seconds;
      await prefs.setInt('${prefix}sessions', sessions);
      await prefs.setInt('${prefix}seconds', total);
      final last = prefs.getInt('${prefix}last');
      if (!ReviewEligibility.allows(
        now: now,
        firstUse: DateTime.fromMillisecondsSinceEpoch(first),
        sessions: sessions,
        seconds: total,
        attempts: prefs.getInt('${prefix}attempts') ?? 0,
        lastAttempt: last == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(last),
      )) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!canPresent() ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      final review = InAppReview.instance;
      if (!await review.isAvailable()) return;
      if (!canPresent() ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      // Record the attempt before calling Play. Play does not tell us whether
      // a dialog was displayed or a rating submitted. Do not retry immediately.
      await prefs.setInt('${prefix}last', now.millisecondsSinceEpoch);
      await prefs.setInt(
        '${prefix}attempts',
        (prefs.getInt('${prefix}attempts') ?? 0) + 1,
      );
      await review.requestReview();
    } catch (_) {
      /* Not available/offline/sideloaded: quietly skip. */
    } finally {
      _busy = false;
    }
  }
}
