import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/push_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.initialNotice});
  final Map<String, dynamic>? initialNotice;
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final push = PushService.instance;
  Set<String> read = {};
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    read =
        (await SharedPreferences.getInstance())
            .getStringList('push.read')
            ?.toSet() ??
        {};
    await push.start();
    if (mounted) {
      setState(() {});
      final initial = widget.initialNotice;
      if (initial != null) {
        await _open(initial['noticeId'] as String? ?? '', initial);
      }
    }
  }

  Future<void> _open(String id, Map<String, dynamic> data) async {
    read.add(id);
    await (await SharedPreferences.getInstance()).setStringList(
      'push.read',
      read.toList(),
    );
    if (mounted) setState(() {});
    final link = Uri.tryParse(data['link'] as String? ?? '');
    if (link == null ||
        link.scheme != 'https' ||
        link.host.isEmpty ||
        !mounted) {
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open external link?'),
        content: Text(link.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    if (approved == true) {
      await launchUrl(link, mode: LaunchMode.externalApplication);
    }
  }

  Widget _list(Query<Map<String, dynamic>> query, String empty) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Cannot load notices. Check your connection and published Firestore rules.',
            ),
          );
        }
        if (!snapshot.hasData) return const LinearProgressIndicator();
        if (snapshot.data!.docs.isEmpty) {
          return Padding(padding: const EdgeInsets.all(16), child: Text(empty));
        }
        return Column(
          children: snapshot.data!.docs.map((doc) {
            final data = doc.data();
            return ListTile(
              leading: Icon(
                read.contains(doc.id) ? Icons.notifications_none : Icons.circle,
                size: read.contains(doc.id) ? 24 : 12,
              ),
              title: Text(data['title'] as String? ?? 'MaxPlayer'),
              subtitle: Text(data['message'] as String? ?? ''),
              onTap: () => _open(doc.id, data),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications')),
    body: ListenableBuilder(
      listenable: push,
      builder: (context, _) => ListView(
        children: [
          SwitchListTile(
            title: const Text('Android notifications'),
            subtitle: const Text(
              'Updates in your notification tray. Permission is requested only when you enable this.',
            ),
            value: push.enabled,
            onChanged: (value) async {
              await push.setEnabled(value);
            },
          ),
          if (push.error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                push.error!,
                style: const TextStyle(color: Colors.orange),
              ),
            ),
          if (push.uid != null)
            ListTile(
              title: const Text('Your installation ID'),
              subtitle: SelectableText(push.uid!),
              trailing: IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: push.uid!)),
              ),
            ),
          const Padding(padding: EdgeInsets.all(16), child: Text('Everyone')),
          if (push.uid != null)
            _list(
              FirebaseFirestore.instance
                  .collection('publishedNotices')
                  .orderBy('createdAt', descending: true)
                  .limit(50),
              'No notices yet.',
            ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('For this installation'),
          ),
          if (push.uid != null)
            _list(
              FirebaseFirestore.instance
                  .collection('users')
                  .doc(push.uid)
                  .collection('inbox')
                  .orderBy('createdAt', descending: true)
                  .limit(50),
              'No personal notices yet.',
            ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Unread dots are stored on this installation. Reinstalling resets your anonymous ID. Older notices are limited to the latest 50 per list.',
            ),
          ),
        ],
      ),
    ),
  );
}
