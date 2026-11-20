import '../local_thumbnail.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../playlist.dart';
import '../utils/app_language.dart';
import 'collection_screens.dart';

class DesktopSearchScreen extends StatefulWidget {
  final List<String> sources;
  final bool listMode;
  const DesktopSearchScreen(
      {super.key, required this.sources, required this.listMode});
  @override
  State<DesktopSearchScreen> createState() => _DesktopSearchScreenState();
}

class _DesktopSearchScreenState extends State<DesktopSearchScreen> {
  final input = TextEditingController();
  Timer? debounce;
  String query = '';
  void changed(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() => query = value.trim().toLowerCase());
      }
    });
  }

  @override
  void dispose() {
    debounce?.cancel();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = query.isEmpty
        ? <String>[]
        : widget.sources
            .toSet()
            .where((source) => labelFor(source).toLowerCase().contains(query))
            .toList()
      ..sort((a, b) =>
          labelFor(a).toLowerCase().compareTo(labelFor(b).toLowerCase()));
    return Scaffold(
      appBar: AppBar(
          titleSpacing: 0,
          title: TextField(
            controller: input,
            autofocus: true,
            onChanged: changed,
            decoration: LInputDecoration(
                hintText: 'Search media…',
                border: InputBorder.none,
                suffixIcon: input.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded, color: secondary),
                        onPressed: () {
                          input.clear();
                          changed('');
                        })),
          )),
      body: query.isEmpty
          ? collectionEmpty(Icons.search_rounded,
              'Type to search your Windows media collection')
          : Column(children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                          '${results.length} results · queue, history, favourites and saved playlists',
                          style: const TextStyle(
                              color: secondary, fontSize: 11)))),
              Expanded(
                child: results.isEmpty
                    ? collectionEmpty(
                        Icons.search_off_rounded, 'No matching media found')
                    : widget.listMode
                        ? ListView.separated(
                            itemCount: results.length,
                            separatorBuilder: (context, i) =>
                                const Divider(height: 1, indent: 72),
                            itemBuilder: (context, i) => ListTile(
                                leading: SizedBox(
                                    width: 96,
                                    height: 54,
                                    child: LocalThumbnail(results[i])),
                                title: Text(labelFor(results[i]),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: LText(validStream(results[i])
                                    ? 'Network media'
                                    : 'Local file'),
                                onTap: () =>
                                    Navigator.pop(context, results[i])))
                        : GridView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: results.length,
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 300,
                                    childAspectRatio: 1.55,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12),
                            itemBuilder: (context, i) => Card(
                                child: InkWell(
                                    onTap: () =>
                                        Navigator.pop(context, results[i]),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                                child: SizedBox(
                                                    width: double.infinity,
                                                    child: LocalThumbnail(
                                                        results[i]))),
                                            Text(labelFor(results[i]),
                                                maxLines: 2,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                          ]),
                                    )))),
              ),
            ]),
    );
  }
}
