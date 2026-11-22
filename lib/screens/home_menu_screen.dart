import 'package:flutter/material.dart';
import '../app_info.dart';
import '../utils/app_language.dart';

/// Remains below its child pages in the Navigator stack. Never pop this page
/// just to open a setting: that caused the Home flash and incorrect Back route.
class HomeMenuScreen extends StatefulWidget {
  const HomeMenuScreen({super.key, required this.onSelected});
  final Future<void> Function(BuildContext context, String action) onSelected;
  @override
  State<HomeMenuScreen> createState() => _HomeMenuScreenState();
}

class _HomeMenuScreenState extends State<HomeMenuScreen> {
  bool opening = false;
  Future<void> open(String action) async {
    if (opening) return;
    opening = true;
    try {
      await widget.onSelected(context, action);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open this item. Please try again.'),
          ),
        );
      }
    } finally {
      opening = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LText('Settings and more')),
    body: ListView(
      key: const PageStorageKey('home-settings-menu'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final entry in const <(String, IconData, String)>[
          ('appearance', Icons.brightness_6_outlined, 'Appearance'),
          ('language', Icons.language, 'Language'),
          ('display', Icons.tune_rounded, 'Display settings'),
          ('stats', Icons.bar_chart_rounded, 'Watch statistics'),
          ('manual', Icons.menu_book_outlined, 'User manual'),
          ('about', Icons.info_outline_rounded, 'About Max Player'),
          ('privacy', Icons.privacy_tip_outlined, 'Privacy policy'),
          ('report', Icons.flag_outlined, 'Report a problem'),
          ('instagram', Icons.camera_alt_outlined, 'Follow on Instagram'),
        ])
          ListTile(
            leading: Icon(entry.$2),
            title: LText(entry.$3),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open(entry.$1),
          ),
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text('Version $kAppVersion', textAlign: TextAlign.center),
        ),
      ],
    ),
  );
}
