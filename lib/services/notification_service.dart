import 'dart:async';

import 'package:flutter/material.dart';

import '../models/history_entry.dart';
import 'native_bridge.dart';

/// v63 Phase 2: the REAL notifications built on the v62 foundation.
///
/// Three features, all over the existing [NativeBridge] notification API:
///
///  1. AI subtitles ready      ([notifyAiSubsReady] / [notifyAiSubsProgress] /
///                              [notifyAiSubsFailed]) - low-urgency, tap opens
///                              the video with the fresh subtitles loaded.
///  2. Continue watching       ([notifyContinueWatching]) - one notification
///                              for the latest in-progress video, with strict
///                              anti-spam rules so it never nags.
///  3. Cast status             ([notifyCasting] / [cancelCasting]) - an
///                              ongoing "Casting to <TV>" while on the TV.
///
/// Notification payloads are the deep links handled in main.dart:
///   video:<path>     -> open that local video in the player
///   cast:            -> just bring the app forward (cast controls are there)
///
/// Every public method is best-effort and never throws: if the user denied
/// the permission or the platform channel is absent (tests/desktop), calls
/// resolve silently.
class NotificationService {
  NotificationService._();

  /// Stable notification ids (the same id updates, never stacks duplicates).
  static const int _idAiSubs = 2001;
  static const int _idContinue = 2002;
  static const int _idCast = 2003;

  // --- anti-spam state for "continue watching" ----------------------------
  // Only ONE continue-watching notification may exist at a time, and we
  // won't re-post for the same video more than once per cool-down, even
  // across background/foreground cycles.
  static String? _lastContinuePath;
  static DateTime? _lastContinueAt;
  static const Duration _continueCooldown = Duration(hours: 12);

  /// A video only qualifies as "continue watching" when it is between
  /// 5% and 95% watched. Before/after that there's nothing meaningful to
  /// resume (or the user already finished it).
  static const double _minResumeFraction = 0.05;
  static const double _maxResumeFraction = 0.95;
  static const int _minResumeSecs = 60; // ignore tiny <1min resume points

  // -------------------------------------------------------------------------
  // 1) AI subtitles
  // -------------------------------------------------------------------------

  /// Shown while an AI subtitle job is running (downloading / extracting /
  /// transcribing). It is an ongoing, low-urgency notification with a real
  /// progress bar; [percent] 0 makes it indeterminate. Call again to update.
  static Future<void> notifyAiSubsProgress({
    required String videoTitle,
    required int percent,
  }) async {
    if (!await NativeBridge.notificationsEnabled()) return;
    await NativeBridge.showNotification(
      id: _idAiSubs,
      channel: NotificationChannels.aiSubs,
      title: 'AI subtitles',
      body: 'Generating subtitles for "$videoTitle"…',
      ongoing: true,
      progress: percent.clamp(0, 100),
      payload: 'video:', // tap just returns to the app; job stays in foreground
    );
  }

  /// "Subtitles ready" - replaces the progress notification with a normal,
  /// auto-cancelling one. Tapping it opens [videoPath] in the player.
  static Future<void> notifyAiSubsReady({
    required String videoTitle,
    required String videoPath,
  }) async {
    if (!await NativeBridge.notificationsEnabled()) return;
    await NativeBridge.showNotification(
      id: _idAiSubs,
      channel: NotificationChannels.aiSubs,
      title: 'Subtitles ready',
      body: 'AI subtitles for "$videoTitle" are ready - tap to play.',
      ongoing: false,
      payload: 'video:$videoPath',
    );
  }

  /// Failure shown only when it's not a user cancel. Tap returns to app.
  static Future<void> notifyAiSubsFailed({
    required String videoTitle,
    required String reason,
  }) async {
    if (reason == 'cancelled') {
      await NativeBridge.cancelNotification(_idAiSubs);
      return;
    }
    if (!await NativeBridge.notificationsEnabled()) return;
    await NativeBridge.showNotification(
      id: _idAiSubs,
      channel: NotificationChannels.aiSubs,
      title: 'Subtitles failed',
      body: 'Could not finish subtitles for "$videoTitle".',
      ongoing: false,
      payload: 'video:',
    );
  }

  /// Clears the AI-subtitles notification (e.g. when the video is opened).
  static Future<void> cancelAiSubs() =>
      NativeBridge.cancelNotification(_idAiSubs);

  // -------------------------------------------------------------------------
  // 2) Continue watching
  // -------------------------------------------------------------------------

  /// Whether [entry] is worth a "continue watching" nudge. Pure so it can be
  /// unit-tested. Qualifies when 5%..95% watched and at least 60s in.
  static bool isResumable(HistoryEntry entry) {
    if (entry.lastPositionSecs < _minResumeSecs) return false;
    if (entry.durationSecs <= 0) {
      // Unknown duration: if there's a meaningful resume point, allow it.
      return entry.lastPositionSecs >= _minResumeSecs;
    }
    final frac = entry.lastPositionSecs / entry.durationSecs;
    return frac >= _minResumeFraction && frac <= _maxResumeFraction;
  }

  /// Posts (or updates) the single "Continue watching" notification for the
  /// most recent resumable video. Skips when [entries] has nothing
  /// resumable, when the same video was notified within the cool-down, or
  /// when notifications are disabled. Returns true if it posted.
  static Future<bool> notifyContinueWatching(
    List<HistoryEntry> entries,
  ) async {
    if (!await NativeBridge.notificationsEnabled()) return false;
    // History is newest-first; pick the first resumable one.
    HistoryEntry? target;
    for (final e in entries) {
      if (isResumable(e)) {
        target = e;
        break;
      }
    }
    if (target == null) {
      await NativeBridge.cancelNotification(_idContinue);
      return false;
    }
    // Anti-spam: don't re-nag for the same video within the cooldown.
    final now = DateTime.now();
    if (target.path == _lastContinuePath &&
        _lastContinueAt != null &&
        now.difference(_lastContinueAt!) < _continueCooldown) {
      return false;
    }
    final remaining = target.durationSecs > 0
        ? target.durationSecs - target.lastPositionSecs
        : 0;
    final body = remaining > 0
        ? '${target.title} · ${_formatRemaining(remaining)} left'
        : 'Tap to resume ${target.title}';
    await NativeBridge.showNotification(
      id: _idContinue,
      channel: NotificationChannels.continueWatching,
      title: 'Continue watching',
      body: body,
      payload: 'video:${target.path}',
    );
    _lastContinuePath = target.path;
    _lastContinueAt = now;
    return true;
  }

  /// Clears the continue-watching notification and its cooldown (called when
  /// the user opens/finishes that video).
  static Future<void> cancelContinueWatching() async {
    _lastContinuePath = null;
    _lastContinueAt = null;
    await NativeBridge.cancelNotification(_idContinue);
  }

  /// Test/debug hook to reset the in-memory anti-spam guard.
  @visibleForTesting
  static void debugResetContinueGuard() {
    _lastContinuePath = null;
    _lastContinueAt = null;
  }

  // -------------------------------------------------------------------------
  // 3) Cast status
  // -------------------------------------------------------------------------

  /// Ongoing "Casting to <device>" notification while a video is on the TV.
  /// Tap brings the app forward so the user gets the remote controls.
  static Future<void> notifyCasting(String deviceName) async {
    if (!await NativeBridge.notificationsEnabled()) return;
    await NativeBridge.showNotification(
      id: _idCast,
      channel: NotificationChannels.playback,
      title: 'Casting to TV',
      body: deviceName.isEmpty ? 'Playing on a nearby TV' : deviceName,
      ongoing: true,
      payload: 'cast:',
    );
  }

  static Future<void> cancelCasting() =>
      NativeBridge.cancelNotification(_idCast);

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  static String _formatRemaining(int secs) {
    if (secs >= 3600) {
      final h = secs ~/ 3600;
      final m = (secs % 3600) ~/ 60;
      return '$h h ${m.toString().padLeft(2, '0')} min left';
    }
    final m = secs ~/ 60;
    return '$m min left';
  }
}

/// Result of routing a notification-tap payload in main.dart.
sealed class NotificationAction {
  const NotificationAction();

  /// "video:<path>" - open/play a local video (empty path = just foreground).
  factory NotificationAction.video(String path) = VideoNotificationAction;

  /// "cast:" - bring the app to the foreground for cast controls.
  const factory NotificationAction.cast() = CastNotificationAction;

  /// "test:..." from the About-sheet test button (Phase 1) - no-op beyond the
  /// snackbar.
  factory NotificationAction.test(String tag) = TestNotificationAction;

  /// Anything unrecognized - ignored.
  const factory NotificationAction.unknown() = UnknownNotificationAction;

  /// Parses an opaque notification payload into a typed action.
  static NotificationAction parse(String payload) {
    final colon = payload.indexOf(':');
    if (colon < 0) return const NotificationAction.unknown();
    final kind = payload.substring(0, colon);
    final data = payload.substring(colon + 1);
    switch (kind) {
      case 'video':
        return NotificationAction.video(data);
      case 'cast':
        return const NotificationAction.cast();
      case 'test':
        return NotificationAction.test(data);
      default:
        return const NotificationAction.unknown();
    }
  }
}

class VideoNotificationAction extends NotificationAction {
  final String path;
  VideoNotificationAction(this.path);
}

class CastNotificationAction extends NotificationAction {
  const CastNotificationAction();
}

class TestNotificationAction extends NotificationAction {
  final String tag;
  TestNotificationAction(this.tag);
}

class UnknownNotificationAction extends NotificationAction {
  const UnknownNotificationAction();
}
