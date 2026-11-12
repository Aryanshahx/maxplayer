import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';

import 'app_analytics.dart';
import 'push_image_loader.dart';
export 'push_image_loader.dart' show validPushImage;

@pragma('vm:entry-point')
Future<void> maxPlayerPushBackground(RemoteMessage message) async {
  await AppAnalytics.instance.ensureInit();
  await PushService.instance.show(message);
}

class PushService {
  PushService._();
  static final instance = PushService._();
  final local = FlutterLocalNotificationsPlugin();
  static const channel = AndroidNotificationChannel(
    'maxplayer_notices',
    'MaxPlayer notices',
    description: 'Updates from MaxPlayer',
    importance: Importance.high,
  );
  String? uid;
  bool _starting = false;
  bool _started = false,
      _mediaReady = false,
      _requesting = false,
      _askedThisForeground = false;
  bool _permitted = false;
  DateTime? _lastRequest;
  Future<void>? _localInit;
  void Function(Map<String, dynamic>)? onTap;
  Map<String, dynamic>? pendingTap;
  FirebaseFirestore get db => FirebaseFirestore.instance;

  Future<void> initLocal() => _localInit ??= _initLocal();
  Future<void> _initLocal() async {
    await local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_maxplayer'),
      ),
      onDidReceiveNotificationResponse: (response) {
        try {
          tap(Map<String, dynamic>.from(jsonDecode(response.payload ?? '{}')));
        } catch (_) {}
      },
    );
    await local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  void tap(Map<String, dynamic> data) {
    if (onTap != null) {
      onTap!(data);
    } else {
      pendingTap = data;
    }
  }

  /// Library permission is resolved first, so two Android dialogs cannot race.
  void mediaPermissionSettled() {
    _mediaReady = true;
    unawaited(requestOnForeground());
  }

  void backgrounded() {
    _askedThisForeground = false;
  }

  Future<void> requestOnForeground() async {
    if (!_mediaReady || _requesting) return;
    _requesting = true;
    try {
      await initLocal();
      final android = local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      _permitted = await android?.areNotificationsEnabled() ?? false;
      if (!_permitted &&
          !_askedThisForeground &&
          (_lastRequest == null ||
              DateTime.now().difference(_lastRequest!).inSeconds >= 30)) {
        _askedThisForeground = true;
        _lastRequest = DateTime.now();
        // Android decides whether another prompt is allowed. No forced settings redirect.
        _permitted = await android?.requestNotificationsPermission() ?? false;
      }
      if (_permitted && _started) await _register();
    } catch (e) {
      debugPrint('Notification permission/registration: $e');
    } finally {
      _requesting = false;
    }
  }

  Future<void> start() async {
    if (_started || _starting) return;
    _starting = true;
    try {
      await AppAnalytics.instance.ensureInit();
      if (!AppAnalytics.ready.value) return;
      final auth = FirebaseAuth.instance;
      uid = (auth.currentUser ?? (await auth.signInAnonymously()).user)!.uid;
      await initLocal();
      final launch = await local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        try {
          tap(
            Map<String, dynamic>.from(
              jsonDecode(launch!.notificationResponse?.payload ?? '{}'),
            ),
          );
        } catch (_) {}
      }
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) tap(initial.data);
      FirebaseMessaging.onMessageOpenedApp.listen((m) => tap(m.data));
      FirebaseMessaging.onMessage.listen((m) => unawaited(show(m)));
      FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        try {
          if (_permitted) await saveToken(token);
        } catch (e) {
          debugPrint('Push token sync: $e');
        }
      });
      _started = true;
      await requestOnForeground();
    } catch (e) {
      debugPrint('Push initialization: $e');
    } finally {
      _starting = false;
    }
  }

  Future<void> saveToken(String token) async {
    if (uid == null) return;
    final key = base64Url.encode(utf8.encode(token)).replaceAll('=', '');
    await db.collection('users').doc(uid).collection('tokens').doc(key).set({
      'token': token,
      'platform': 'android',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _register() async {
    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    // Topic registration must not be blocked by an unrelated token-document write.
    await FirebaseMessaging.instance.subscribeToTopic('all');
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await saveToken(token);
  }

  Future<String?> _image(String url) async {
    final bytes = await downloadPushImage(url);
    if (bytes == null) return null;
    final dir = Directory(
      '${(await getTemporaryDirectory()).path}/maxplayer_notice_images',
    );
    await dir.create(recursive: true);
    // Keep a small bounded cache; don't delete the image immediately after display.
    final old = await dir
        .list()
        .where((entry) => entry is File)
        .cast<File>()
        .toList();
    old.sort((a, b) => a.path.compareTo(b.path));
    for (final file in old.take(old.length > 19 ? old.length - 19 : 0)) {
      try {
        await file.delete();
      } catch (_) {}
    }
    final file = File(
      '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.img',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> show(RemoteMessage message) async {
    // Android notification permission is the only gate. No hidden app switch/pref.
    await initLocal();
    final allowed = await local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.areNotificationsEnabled();
    if (allowed == false) return;
    final data = message.data;
    final String? id = data['noticeId'] is String
        ? data['noticeId'] as String
        : message.messageId;
    if (id == null || id.isEmpty) return;
    final notificationId = id.codeUnits.fold<int>(
      0,
      (a, b) => ((a * 31) + b) & 0x7fffffff,
    );
    final title = data['title'] ?? message.notification?.title ?? 'MaxPlayer';
    final body = data['message'] ?? message.notification?.body ?? '';
    final payload = jsonEncode(data);
    final text = BigTextStyleInformation(body, contentTitle: title);
    // Post text immediately: slow image networking must not swallow the entire notice.
    await local.show(
      notificationId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          icon: 'ic_stat_maxplayer',
          color: const Color(0xff8b5cf6),
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: text,
        ),
      ),
      payload: payload,
    );
    try {
      final image = await _image(data['image'] ?? '');
      if (image == null) return;
      final bitmap = FilePathAndroidBitmap(image);
      await local.show(
        notificationId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            icon: 'ic_stat_maxplayer',
            color: const Color(0xff8b5cf6),
            importance: Importance.high,
            priority: Priority.high,
            onlyAlertOnce: true,
            largeIcon: bitmap,
            styleInformation: BigPictureStyleInformation(
              bitmap,
              contentTitle: title,
              summaryText: body,
              hideExpandedLargeIcon: true,
            ),
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('Notification image unavailable; text retained: $e');
    }
  }
}
