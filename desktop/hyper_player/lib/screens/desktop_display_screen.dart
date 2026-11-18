import 'package:flutter/material.dart';
import '../utils/app_language.dart';
import 'collection_screens.dart';

class DesktopDisplayScreen extends StatefulWidget {
  final bool listMode;
  final Future<void> Function(bool listMode, String? sort) onChange;
  const DesktopDisplayScreen(
      {super.key, required this.listMode, required this.onChange});
  @override
  State<DesktopDisplayScreen> createState() => _DesktopDisplayScreenState();
}

class _DesktopDisplayScreenState extends State<DesktopDisplayScreen> {
  late bool listMode = widget.listMode;
  String? sort;
  bool saving = false;
  Future<void> change(bool value, String? order) async {
    if (saving) {
      return;
    }
    setState(() {
      listMode = value;
      sort = order;
      saving = true;
    });
    try {
      await widget.onChange(value, order);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save display settings.')));
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10, left: 4),
      child: LText(title,
          style: const TextStyle(
              color: secondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1)));
  Widget mode(bool list, IconData icon, String title, String subtitle) {
    final selected = list == listMode;
    return Expanded(
        child: Card(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: selected ? Colors.white : edge,
              width: selected ? 1.6 : 1)),
      child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: saving ? null : () => change(list, null),
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
              child: Row(children: [
                Icon(icon,
                    size: 26, color: selected ? Colors.white : secondary),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      LText(title,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: selected ? Colors.white : secondary)),
                      const SizedBox(height: 2),
                      LText(subtitle,
                          style:
                              const TextStyle(fontSize: 12, color: secondary)),
                    ])),
              ]))),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            titleSpacing: 4,
            title: const LText('Display Settings'),
            leading: const BackButton()),
        body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      if (saving) const LinearProgressIndicator(),
                      section('LAYOUT & VIEW MODE'),
                      Row(children: [
                        mode(false, Icons.grid_view_rounded, 'Grid View',
                            'Visual cards'),
                        const SizedBox(width: 12),
                        mode(true, Icons.view_list_rounded, 'List View',
                            'Compact rows')
                      ]),
                      section('SORTING'),
                      Card(
                          child: Column(children: [
                        for (final entry in {
                          'nameAsc': 'Name · A–Z',
                          'nameDesc': 'Name · Z–A'
                        }.entries) ...[
                          ListTile(
                              leading: const Icon(Icons.sort_by_alpha),
                              title: Text(entry.value),
                              trailing: Icon(
                                  sort == entry.key
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  size: 20),
                              onTap: saving
                                  ? null
                                  : () => change(listMode, entry.key)),
                          if (entry.key != 'nameDesc')
                            const Divider(height: 1, indent: 16, endIndent: 16),
                        ]
                      ])),
                      section('GROUPING & ACTIONS'),
                      const Card(
                          child: Column(children: [
                        ListTile(
                            leading: Icon(Icons.photo_library_outlined),
                            title: Text('Group videos by'),
                            subtitle: Text(
                                'Use the Folders screen. In-library grouping is not implemented on Windows.',
                                style:
                                    TextStyle(color: secondary, fontSize: 12))),
                        Divider(height: 1, indent: 16, endIndent: 16),
                        ListTile(
                            leading: Icon(Icons.play_circle_outline_rounded),
                            title: Text('Playback action'),
                            subtitle: Text(
                                'Current queue advances automatically. Play Single setting is not implemented.',
                                style:
                                    TextStyle(color: secondary, fontSize: 12))),
                      ])),
                      const SizedBox(height: 20),
                      const Text(
                          'Layout selection is saved on this laptop. Sorting reorders the current queue without changing the active media. Other Android display options are not yet implemented.',
                          style: TextStyle(color: secondary, fontSize: 12)),
                    ]))),
      );
}
