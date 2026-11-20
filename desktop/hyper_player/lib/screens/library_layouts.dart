import 'package:flutter/material.dart';
import '../app_design.dart';
import '../local_thumbnail.dart';
import '../playlist.dart';

class LibraryDestination {
  final String label;
  final IconData icon;
  final VoidCallback open;
  const LibraryDestination(this.label, this.icon, this.open);
}

/// Different compositions, not theme aliases: Android dashboard, desktop
/// navigation + library workspace, and cinema navigation + horizontal shelves.
class LibraryLayouts extends StatelessWidget {
  final AppDesignMode mode;
  final Widget androidLibrary;
  final List<LibraryDestination> destinations;
  final List<String> videos;
  final ValueChanged<String> play;
  const LibraryLayouts(
      {super.key,
      required this.mode,
      required this.androidLibrary,
      required this.destinations,
      required this.videos,
      required this.play});
  @override
  Widget build(BuildContext context) {
    if (mode == AppDesignMode.android) return androidLibrary;
    if (mode == AppDesignMode.compact) {
      return LayoutBuilder(
          builder: (context, size) => Row(children: [
                SizedBox(
                    width: size.maxWidth < 800 ? 64 : 216,
                    child: Material(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        child: ListView(children: [
                          const SizedBox(height: 12),
                          if (size.maxWidth >= 800)
                            const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('LIBRARY WORKSPACE',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold))),
                          for (final destination in destinations)
                            size.maxWidth < 800
                                ? IconButton(
                                    tooltip: destination.label,
                                    onPressed: destination.open,
                                    icon: Icon(destination.icon))
                                : ListTile(
                                    leading: Icon(destination.icon),
                                    title: Text(destination.label),
                                    onTap: destination.open),
                        ]))),
                const VerticalDivider(width: 1),
                Expanded(child: androidLibrary),
              ]));
    }
    Widget shelf(String title, List<String> sources) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child:
                  Text(title, style: Theme.of(context).textTheme.titleLarge)),
          SizedBox(
              height: 210,
              child: sources.isEmpty
                  ? const Center(
                      child: Text('Open files or scan folders to add videos'))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      scrollDirection: Axis.horizontal,
                      itemCount: sources.length,
                      separatorBuilder: (_, index) => const SizedBox(width: 18),
                      itemBuilder: (context, index) => SizedBox(
                          width: 290,
                          child: InkWell(
                              onTap: () => play(sources[index]),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                        child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                          LocalThumbnail(sources[index]),
                                          const Center(
                                              child: Icon(
                                                  Icons.play_circle_outline,
                                                  size: 44))
                                        ])),
                                    Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 10),
                                        child: Text(labelFor(sources[index]),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis)),
                                  ]))))),
        ]);
    return ListView(children: [
      Padding(
          padding: const EdgeInsets.all(24),
          child: Text('YOUR PRIVATE CINEMA',
              style: Theme.of(context).textTheme.headlineMedium)),
      SizedBox(
          height: 58,
          child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                for (final destination in destinations)
                  Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: ActionChip(
                          avatar: Icon(destination.icon, size: 18),
                          label: Text(destination.label),
                          onPressed: destination.open)),
              ])),
      shelf('Ready to watch', videos.take(20).toList()),
      shelf('More in your library', videos.skip(20).toList()),
      const SizedBox(height: 32),
    ]);
  }
}
