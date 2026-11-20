import '../stream_probe.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../playlist.dart';
import '../utils/app_language.dart';

class DesktopStreamScreen extends StatefulWidget {
  final List<String> recent;
  const DesktopStreamScreen({super.key, required this.recent});
  @override
  State<DesktopStreamScreen> createState() => _DesktopStreamScreenState();
}

class _DesktopStreamScreenState extends State<DesktopStreamScreen> {
  final url = TextEditingController();
  final title = TextEditingController();
  final saved = <String, String>{};
  String? error;
  bool probing = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final decoded = jsonDecode(
        prefs.getString('hyper.saved.streams.v1') ?? '{}',
      );
      if (decoded is Map && mounted) {
        setState(() {
          for (final entry in decoded.entries) {
            if (entry.key is String &&
                entry.value is String &&
                validStream(entry.key as String)) {
              saved[entry.key as String] = entry.value as String;
            }
          }
        });
      }
    } catch (_) {
      /* Invalid saved data must not prevent stream opening. */
    }
  }

  Future<void> persist() async {
    final value = jsonEncode(saved);
    await (await SharedPreferences.getInstance()).setString(
      'hyper.saved.streams.v1',
      value,
    );
  }

  bool validate() {
    if (validStream(url.text.trim())) {
      setState(() => error = null);
      return true;
    }
    setState(() =>
        error = 'Enter a direct HTTP(S), RTSP, RTMP(S), UDP or RTP media URL.');
    return false;
  }

  Future<void> play() async {
    if (probing || !validate()) return;
    final source = url.text.trim();
    setState(() => probing = true);
    try {
      final channels = await probeStreamChannels(source);
      if (!mounted) return;
      if (channels.isEmpty) {
        Navigator.pop(context, source);
        return;
      }
      final selected = await Navigator.push<String>(
          context,
          MaterialPageRoute(
              builder: (_) => Scaffold(
                    appBar: AppBar(
                        title: Text('IPTV channels · ${channels.length}')),
                    body: ListView.builder(
                        itemCount: channels.length,
                        itemBuilder: (ctx, index) => ListTile(
                            leading: const Icon(Icons.live_tv),
                            title: Text(channels[index].title),
                            onTap: () =>
                                Navigator.pop(ctx, channels[index].source))),
                  )));
      if (mounted && selected != null) Navigator.pop(context, selected);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => probing = false);
    }
  }

  Future<void> bookmark() async {
    if (!validate()) {
      return;
    }
    setState(
      () => saved[url.text.trim()] = title.text.trim().isEmpty
          ? labelFor(url.text.trim())
          : title.text.trim(),
    );
    await persist();
  }

  @override
  void dispose() {
    url.dispose();
    title.dispose();
    super.dispose();
  }

  Widget streamRow(String source, String label, {bool removable = false}) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.link, size: 22),
        title: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          Uri.tryParse(source)?.host ?? '',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        trailing: removable
            ? IconButton(
                tooltip: 'Remove saved stream',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () async {
                  setState(() => saved.remove(source));
                  await persist();
                },
              )
            : const Icon(Icons.play_arrow),
        onTap: () {
          url.text = source;
          title.text = label;
          play();
        },
      );
  @override
  Widget build(BuildContext context) {
    final scheme = Uri.tryParse(url.text.trim())?.scheme.toUpperCase();
    return Scaffold(
      backgroundColor: const Color(0xff14141c),
      appBar: AppBar(
        backgroundColor: const Color(0xff14141c),
        title: const LText(
          'Open Stream(iptv)',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in [
                    'HTTP',
                    'HTTPS',
                    'HLS/M3U8',
                    'RTSP',
                    'RTMP',
                    'FTP',
                    'SMB',
                    'WebDAV',
                  ])
                    Tooltip(
                      message: ['HTTP', 'HTTPS', 'HLS/M3U8'].contains(p)
                          ? 'Direct HTTP(S) media supported'
                          : 'Not enabled in this Windows build',
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: scheme == p
                              ? Colors.white24
                              : Colors.white.withValues(alpha: .05),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: scheme == p ? Colors.white : Colors.white10,
                          ),
                        ),
                        child: Text(
                          p,
                          style: TextStyle(
                            color: ['HTTP', 'HTTPS', 'HLS/M3U8'].contains(p)
                                ? Colors.white54
                                : Colors.white24,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        url.text.trim().isEmpty ? Colors.white12 : Colors.white,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: url,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => play(),
                        style: const TextStyle(fontSize: 13.5),
                        decoration: const LInputDecoration(
                          hintText: 'https://, http://…',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Paste URL',
                      icon: const Icon(
                        Icons.paste,
                        size: 20,
                        color: Colors.white70,
                      ),
                      onPressed: () async {
                        final data = await Clipboard.getData(
                          Clipboard.kTextPlain,
                        );
                        if (mounted && data?.text != null) {
                          setState(() => url.text = data!.text!.trim());
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .04),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextField(
                  controller: title,
                  style: const TextStyle(fontSize: 13),
                  decoration: const LInputDecoration(
                    hintText: 'Stream title (optional)',
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(context, '__IMPORT_M3U__'),
                icon: const Icon(Icons.playlist_add),
                label: const Text('Import IPTV playlist'),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: url.text.trim().isEmpty || probing ? null : play,
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  probing ? 'Checking stream / channels…' : 'Play Stream',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Direct HTTP(S) media and HLS play as one stream. Use Import IPTV playlist for channel lists. Other protocols and the Android LIVE TV catalogue are not enabled in this build.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Color(0xffe5484d)),
                  ),
                ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: bookmark,
                  icon: const Icon(Icons.bookmark_border, size: 18),
                  label: const Text('Save stream'),
                ),
              ),
              const SizedBox(height: 16),
              const LText(
                'Saved streams',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              if (saved.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    'No saved streams yet.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              for (final entry in saved.entries)
                streamRow(entry.key, entry.value, removable: true),
              const SizedBox(height: 16),
              const LText(
                'Recent streams',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              for (final source in widget.recent.where(validStream).take(20))
                streamRow(source, labelFor(source)),
              const SizedBox(height: 16),
              const Text(
                'Saved URLs are stored locally without encryption. Do not share application data if URLs contain passwords or tokens.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
