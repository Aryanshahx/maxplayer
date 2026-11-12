import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_analytics.dart';

bool validPushImage(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}

@pragma('vm:entry-point')
Future<void> maxPlayerPushBackground(RemoteMessage message) async {
  await AppAnalytics.instance.ensureInit();
  await PushService.instance.show(message);
}

class PushService extends ChangeNotifier {
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
  bool enabled = false;
  String? error;
  bool _started = false;
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
    pendingTap = data;
    onTap?.call(data);
  }

  Future<void> start() async {
    if (_started) return;
    try {
      await AppAnalytics.instance.ensureInit();
      if (!AppAnalytics.ready.value) {
        throw StateError('Firebase is unavailable');
      }
      final auth = FirebaseAuth.instance;
      final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
      uid = user!.uid;
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
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        if (enabled) unawaited(saveToken(token));
      });
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool('push.enabled') ?? false;
      _started = true;
      if (enabled) await _register();
      error = null;
    } catch (e) {
      error = 'Notification setup failed: $e';
    }
    notifyListeners();
  }

  Future<void> saveToken(String token) async {
    if (uid == null) return;
    // A stable, URL-safe document key makes token rotation idempotent.
    final key = base64Url.encode(utf8.encode(token)).replaceAll('=', '');
    await db.collection('users').doc(uid).collection('tokens').doc(key).set({
      'token': token,
      'platform': 'android',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _register() async {
    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await saveToken(token);
    await FirebaseMessaging.instance.subscribeToTopic('all');
  }

  Future<void> setEnabled(bool value) async {
    error = null;
    try {
      if (!_started) await start();
      if (!_started) throw StateError(error ?? 'Firebase unavailable');
      if (value) {
        // Only called by the user's Enable button, never on first launch.
        final permission = await FirebaseMessaging.instance.requestPermission();
        if (permission.authorizationStatus != AuthorizationStatus.authorized &&
            permission.authorizationStatus != AuthorizationStatus.provisional) {
          throw StateError(
            'Android has not allowed notifications. If permanently denied, enable them in Android settings.',
          );
        }
        await _register();
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic('all');
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && uid != null) {
          final key = base64Url.encode(utf8.encode(token)).replaceAll('=', '');
          await db
              .collection('users')
              .doc(uid)
              .collection('tokens')
              .doc(key)
              .delete();
        }
        await FirebaseMessaging.instance.deleteToken();
        await FirebaseMessaging.instance.setAutoInitEnabled(false);
        await local.cancelAll();
      }
      enabled = value;
      await (await SharedPreferences.getInstance()).setBool(
        'push.enabled',
        value,
      );
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  Future<String?> _image(String url) async {
    if (!validPushImage(url)) return null;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      return await (() async {
        final request = await client.getUrl(Uri.parse(url));
        request.followRedirects = false;
        final response = await request.close();
        if (response.statusCode != 200 ||
            response.contentLength > 1048576 ||
            !(response.headers.contentType?.mimeType.startsWith('image/') ??
                false)) {
          return null;
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 1048576) return null;
          bytes.addAll(chunk);
        }
        if (bytes.isEmpty) return null;
        final file = File(
          '${(await getTemporaryDirectory()).path}/maxplayer_push_${DateTime.now().microsecondsSinceEpoch}.jpg',
        );
        await file.writeAsBytes(bytes, flush: true);
        return file.path;
      })().timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> show(RemoteMessage message) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (!(prefs.getBool('push.enabled') ?? false)) return;
    final data = message.data;
    final id = data['noticeId'] ?? message.messageId;
    if (id == null || id.isEmpty) return;
    // Deterministic ID replaces duplicate deliveries rather than adding trays.
    final notificationId = id.codeUnits.fold<int>(
      0,
      (a, b) => ((a * 31) + b) & 0x7fffffff,
    );
    await initLocal();
    final title = data['title'] ?? message.notification?.title ?? 'MaxPlayer';
    final body = data['message'] ?? message.notification?.body ?? '';
    final image = await _image(data['image'] ?? '');
    final textStyle = BigTextStyleInformation(body, contentTitle: title);
    try {
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
            styleInformation: image == null
                ? textStyle
                : BigPictureStyleInformation(
                    FilePathAndroidBitmap(image),
                    contentTitle: title,
                    summaryText: body,
                  ),
          ),
        ),
        payload: jsonEncode(data),
      );
    } catch (_) {
      await local.show(
        notificationId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            icon: 'ic_stat_maxplayer',
            styleInformation: textStyle,
          ),
        ),
        payload: jsonEncode(data),
      );
    } finally {
      if (image != null) {
        try {
          await File(image).delete();
        } catch (_) {}
      }
    }
  }
}
