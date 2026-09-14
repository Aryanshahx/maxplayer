import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:shared_preferences/shared_preferences.dart';

/// In-app notification centre (bell icon on the home header).
///
/// Device-local only (local-first rule): notifications live in
/// SharedPreferences as a JSON list. They are NOT system notifications —
/// the lock-screen/media notifications stay in MainActivity.kt. This is
/// the app's own inbox for welcomes, tips and release notes.

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.iconKey,
    required this.ts,
    this.read = false,
  });

  final String id;
  final String title;
  final String body;

  /// Semantic icon key (see [notificationIconFor]) — stored as a string so
  /// the icon resolves to a CONST Material icon in the UI. IconData's
  /// codePoint is @mustBeConst, so runtime-constructed IconData is not
  /// allowed (it would break release icon tree-shaking).
  final String iconKey;
  final int ts; // epoch millis
  final bool read;

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        title: title,
        body: body,
        iconKey: iconKey,
        ts: ts,
        read: read ?? this.read,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'icon': iconKey,
        'ts': ts,
        'read': read,
      };

  static AppNotification fromJson(Map<String, dynamic> j) => AppNotification(
        id: (j['id'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        body: (j['body'] ?? '') as String,
        iconKey: (j['icon'] ?? 'info') as String,
        ts: (j['ts'] as num?)?.toInt() ?? 0,
        read: (j['read'] as bool?) ?? false,
      );
}

/// Maps a notification icon key to a CONST Material icon.
IconData notificationIconFor(String key) {
  switch (key) {
    case 'welcome':
      return Icons.waving_hand;
    case 'volume':
      return Icons.volume_up;
    case 'ai':
      return Icons.psychology;
    case 'update':
      return Icons.system_update;
    case 'info':
      return Icons.info_outline;
    default:
      return Icons.notifications_none;
  }
}

// ---------------------------------------------------------------------------
// Pure logic (unit-tested): newest first, dedupe by id, capped.
// ---------------------------------------------------------------------------

List<AppNotification> upsertNotification(
  List<AppNotification> list,
  AppNotification n, {
  int cap = 50,
}) {
  final out = [n, ...list.where((e) => e.id != n.id)];
  out.sort((a, b) => b.ts.compareTo(a.ts));
  if (out.length > cap) out.removeRange(cap, out.length);
  return out;
}

int unreadNotificationCount(List<AppNotification> list) =>
    list.where((e) => !e.read).length;

List<AppNotification> markNotificationRead(
    List<AppNotification> list, String id) {
  return [
    for (final e in list) e.id == id ? e.copyWith(read: true) : e,
  ];
}

List<AppNotification> markAllNotificationsRead(List<AppNotification> list) => [
      for (final e in list) e.copyWith(read: true),
    ];

/// Seeds the welcome + first tips ONCE (only when the inbox is empty — it
/// never overwrites notifications the user already has, and it never
/// re-seeds after the user clears everything).
List<AppNotification> seedWelcomeNotifications(
    List<AppNotification> list, int nowMs) {
  if (list.isNotEmpty) return list;
  return [
    AppNotification(
      id: 'welcome',
      title: 'Welcome to Max Player 👋',
      body:
          'Tap any video to play it. Everything is offline-first and private — no account, no uploads.',
      iconKey: 'welcome',
      ts: nowMs,
    ),
    AppNotification(
      id: 'tip-volume',
      title: 'Try the swipe gestures',
      body:
          'In the player, swipe UP/DOWN on the right half for volume and on the left half for brightness.',
      iconKey: 'volume',
      ts: nowMs + 1,
    ),
    AppNotification(
      id: 'tip-askai',
      title: 'Ask AI works offline',
      body:
          'On the Discover screen, Ask AI answers from the movie\'s own details when there is no internet — instant and free.',
      iconKey: 'ai',
      ts: nowMs + 2,
    ),
  ];
}

// ---------------------------------------------------------------------------
// Reactive store (singleton, mirrors AppSettings).
// ---------------------------------------------------------------------------

class NotificationsStore extends ChangeNotifier {
  NotificationsStore._();

  static final NotificationsStore instance = NotificationsStore._();

  static const _kItems = 'notifications.items';

  List<AppNotification> _items = const [];
  bool _loaded = false;

  List<AppNotification> get items => List.unmodifiable(_items);
  bool get isLoaded => _loaded;
  int get unreadCount => unreadNotificationCount(_items);

  Future<void> load() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kItems);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List)
            .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
            .toList();
        _items = list;
      } catch (_) {
        _items = const [];
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kItems, jsonEncode(_items.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  /// First-run seed: adds the welcome + tips when the inbox is empty.
  Future<void> seedIfEmpty() async {
    final before = _items;
    final after =
        seedWelcomeNotifications(_items, DateTime.now().millisecondsSinceEpoch);
    if (!identical(before, after)) {
      _items = after;
      await _save();
    }
  }

  Future<void> add(AppNotification n) async {
    _items = upsertNotification(_items, n);
    await _save();
  }

  Future<void> markRead(String id) async {
    _items = markNotificationRead(_items, id);
    await _save();
  }

  Future<void> markAllRead() async {
    _items = markAllNotificationsRead(_items);
    await _save();
  }

  Future<void> clearAll() async {
    _items = const [];
    await _save();
  }
}
