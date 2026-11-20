import '../app_design.dart';
import 'package:flutter/material.dart';
import '../utils/app_language.dart';
import 'collection_screens.dart';

class DesktopDisplayScreen extends StatefulWidget {
  final bool listMode;
  final String initialSort;
  final bool queueAll;
  final bool groupByFolder;
  final Future<void> Function(bool)? onGroupByFolder;
  final bool onlyFavourites;
  final Future<void> Function(bool)? onOnlyFavourites;
  final Future<void> Function(bool)? onQueueAll;
  final Future<void> Function(bool listMode, String? sort) onChange;
  const DesktopDisplayScreen(
      {super.key,
      required this.listMode,
      required this.onChange,
      this.initialSort = 'queue',
      this.groupByFolder = false,
      this.onGroupByFolder,
      this.onlyFavourites = false,
      this.onOnlyFavourites,
      this.queueAll = true,
      this.onQueueAll});
  @override
  State<DesktopDisplayScreen> createState() => _DesktopDisplayScreenState();
}

class _DesktopDisplayScreenState extends State<DesktopDisplayScreen> {
  late bool listMode = widget.listMode;
  late bool queueAll = widget.queueAll;
  late bool groupByFolder = widget.groupByFolder;
  late bool onlyFavourites = widget.onlyFavourites;
  late String? sort = widget.initialSort;
  bool saving = false;
  Future<void> change(bool value, String? order) async {
    if (saving) {
      return;
    }
    final previousMode = listMode;
    final previousSort = sort;
    setState(() {
      listMode = value;
      sort = order;
      saving = true;
    });
    try {
      await widget.onChange(value, order);
    } catch (_) {
      if (mounted) {
        setState(() {
          listMode = previousMode;
          sort = previousSort;
        });
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
                constraints:
                    BoxConstraints(maxWidth: AppDesign.instance.contentWidth),
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      if (saving) const LinearProgressIndicator(),
                      section('APP DESIGN · ALL SCREENS'),
                      Card(
                          child: Column(children: [
                        for (final mode in AppDesignMode.values)
                          ListTile(
                              title: Text(AppDesign.instance.label(mode)),
                              subtitle: Text(switch (mode) {
                                AppDesignMode.android =>
                                  'Android-style default',
                                AppDesignMode.compact =>
                                  'Dense controls, compact typography and squared surfaces',
                                AppDesignMode.cinema =>
                                  'Large typography, spacious controls and rounded surfaces'
                              }),
                              trailing: Icon(mode == AppDesign.instance.mode
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off),
                              onTap: saving
                                  ? null
                                  : () async {
                                      final value = mode;
                                      setState(() => saving = true);
                                      try {
                                        await AppDesign.instance.select(value);
                                      } catch (_) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(this.context)
                                              .showSnackBar(const SnackBar(
                                                  content: Text(
                                                      'Could not save app design.')));
                                        }
                                      } finally {
                                        if (mounted) {
                                          setState(() => saving = false);
                                        }
                                      }
                                    })
                      ])),
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
                          'queue': 'Queue order',
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
                      Card(
                          child: SwitchListTile(
                        secondary: const Icon(Icons.favorite_border_rounded),
                        title: const Text('Show only favourites'),
                        value: onlyFavourites,
                        onChanged: saving || widget.onOnlyFavourites == null
                            ? null
                            : (value) async {
                                setState(() => saving = true);
                                try {
                                  await widget.onOnlyFavourites!(value);
                                  if (mounted) {
                                    setState(() => onlyFavourites = value);
                                  }
                                } catch (_) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(this.context)
                                        .showSnackBar(const SnackBar(
                                            content: Text(
                                                'Could not save favourites filter.')));
                                  }
                                } finally {
                                  if (mounted) setState(() => saving = false);
                                }
                              },
                      )),
                      Card(
                          child: Column(children: [
                        SwitchListTile(
                          secondary: const Icon(Icons.photo_library_outlined),
                          title: const Text('Group videos by folder'),
                          subtitle: Text(groupByFolder ? 'Folder' : 'None'),
                          value: groupByFolder,
                          onChanged: saving || widget.onGroupByFolder == null
                              ? null
                              : (value) async {
                                  setState(() => saving = true);
                                  try {
                                    await widget.onGroupByFolder!(value);
                                    if (mounted) {
                                      setState(() => groupByFolder = value);
                                    }
                                  } catch (_) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(this.context)
                                          .showSnackBar(const SnackBar(
                                              content: Text(
                                                  'Could not save folder grouping.')));
                                    }
                                  } finally {
                                    if (mounted) setState(() => saving = false);
                                  }
                                },
                        ),
                        Divider(height: 1, indent: 16, endIndent: 16),
                        SwitchListTile(
                            secondary:
                                const Icon(Icons.play_circle_outline_rounded),
                            title: const Text('Queue All'),
                            subtitle: Text(queueAll
                                ? 'Continue to the next queued file at the end.'
                                : 'Play Single: stop at the end. Manual next/previous still work.'),
                            value: queueAll,
                            onChanged: saving || widget.onQueueAll == null
                                ? null
                                : (value) async {
                                    setState(() => saving = true);
                                    try {
                                      await widget.onQueueAll!(value);
                                      if (mounted) {
                                        setState(() => queueAll = value);
                                      }
                                    } catch (_) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(this.context)
                                            .showSnackBar(const SnackBar(
                                                content: Text(
                                                    'Could not save playback action.')));
                                      }
                                    } finally {
                                      if (mounted) {
                                        setState(() => saving = false);
                                      }
                                    }
                                  }),
                      ])),
                      const SizedBox(height: 20),
                      const Text(
                          'Layout selection is saved on this laptop. Sorting changes the library view only; playback queue order and active media stay unchanged. Play Single stops automatic queue advance (including repeat); manual navigation remains available. Other Android display options are not yet implemented.',
                          style: TextStyle(color: secondary, fontSize: 12)),
                    ]))),
      );
}
