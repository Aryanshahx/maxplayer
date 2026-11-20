import 'package:share_plus/share_plus.dart';
import 'dart:async';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../local_share.dart';
import '../playlist.dart';
import '../local_media_index.dart';
import '../local_thumbnail.dart';
import 'playback_sheets.dart';

const _videoTypes = XTypeGroup(
    label: 'Videos',
    extensions: ['mp4', 'mkv', 'avi', 'mov', 'webm', 'm4v', 'ts', 'wmv']);

class DesktopQuickShareScreen extends StatefulWidget {
  final List<String> knownSources;
  const DesktopQuickShareScreen({super.key, required this.knownSources});
  @override
  State<DesktopQuickShareScreen> createState() =>
      _DesktopQuickShareScreenState();
}

class _DesktopQuickShareScreenState extends State<DesktopQuickShareScreen> {
  late final List<String> videos = widget.knownSources
      .where((s) => !validStream(s) && isMediaPath(s) && !isAudioPath(s))
      .toSet()
      .toList();
  final selected = <String>{};
  bool trusted = false;
  Future<void> addFiles() async {
    try {
      final files = await openFiles(acceptedTypeGroups: [_videoTypes]);
      if (mounted) {
        setState(() {
          for (final file in files) {
            if (!videos.contains(file.path)) videos.add(file.path);
          }
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open file picker.')));
      }
    }
  }

  Future<void> receive() async {
    final paths =
        await showPlaybackSheet<List<String>>(context, const _ReceiveSheet());
    if (mounted && paths != null && paths.isNotEmpty) {
      Navigator.pop(context, paths);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: const Color(0xff060608),
      appBar: AppBar(title: const Text('Quick Share'), actions: [
        IconButton(
            tooltip: 'Choose videos',
            onPressed: addFiles,
            icon: const Icon(Icons.add)),
        IconButton(
            tooltip: 'Receive from another device',
            onPressed: receive,
            icon: const Icon(Icons.download_rounded))
      ]),
      body: Column(children: [
        Expanded(
            child: videos.isEmpty
                ? const Center(
                    child: Text(
                        'No videos selected from this PC.\nUse + to choose videos.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54)))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: videos.length,
                    separatorBuilder: (_, i) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final path = videos[i];
                      return Card(
                          child: CheckboxListTile(
                              value: selected.contains(path),
                              activeColor: Colors.white,
                              checkColor: Colors.black,
                              secondary: SizedBox(
                                  width: 80,
                                  height: 45,
                                  child: LocalThumbnail(path)),
                              title: Text(labelFor(path),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13.5)),
                              subtitle: const Text(
                                  'Only checked files are offered',
                                  style: TextStyle(
                                      color: Colors.white54, fontSize: 11.5)),
                              onChanged: (value) => setState(() {
                                    if (value == true) {
                                      selected.add(path);
                                    } else {
                                      selected.remove(path);
                                    }
                                  })));
                    })),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: trusted,
                onChanged: (v) => setState(() => trusted = v ?? false),
                title: const Text('I trust this local network',
                    style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                    'Local HTTP is not encrypted. Anyone with the temporary link can download the selected files while the session is open. Windows Firewall may ask for permission.',
                    style: TextStyle(
                        color: Colors.white54, fontSize: 11.5, height: 1.4)))),
        SafeArea(
            top: false,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: Row(children: [
                  Expanded(
                      child: FilledButton.icon(
                          onPressed: selected.isEmpty || !trusted
                              ? null
                              : () => showPlaybackSheet<void>(context,
                                  _SendSheet(sources: selected.toList())),
                          icon: const Icon(Icons.wifi_tethering_rounded,
                              size: 18),
                          label: const Text('Direct send'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: OutlinedButton.icon(
                          onPressed: selected.isEmpty
                              ? null
                              : () async {
                                  try {
                                    final files = <XFile>[];
                                    for (final source in selected) {
                                      if (await File(source).exists()) {
                                        files.add(XFile(source));
                                      }
                                    }
                                    if (files.isEmpty) {
                                      throw StateError(
                                          'Selected files are unavailable');
                                    }
                                    await SharePlus.instance.share(ShareParams(
                                        files: files,
                                        title: 'Share with other apps'));
                                  } catch (_) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text(
                                                  'Windows sharing is unavailable. Check installed share targets or use Direct send.')));
                                    }
                                  }
                                },
                          icon: const Icon(Icons.ios_share_rounded, size: 18),
                          label: const Text('Via other apps')))
                ]))),
      ]));
}

class _SendSheet extends StatefulWidget {
  final List<String> sources;
  const _SendSheet({required this.sources});
  @override
  State<_SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends State<_SendSheet> {
  LocalShareSession? session;
  List<String> hosts = [];
  String? error;
  @override
  void initState() {
    super.initState();
    start();
  }

  Future<void> start() async {
    try {
      final active =
          await LocalShareSession.start(widget.sources, onChanged: () {
        if (mounted) setState(() {});
      });
      if (!mounted) {
        await active.stop();
        return;
      }
      session = active;
      try {
        final interfaces = await NetworkInterface.list(
            type: InternetAddressType.IPv4, includeLoopback: false);
        hosts = interfaces
            .expand((i) => i.addresses)
            .map((a) => a.address)
            .toSet()
            .toList();
      } catch (_) {
        error =
            'Could not list local addresses. Stop sharing and reconnect to Wi-Fi.';
      }
      if (mounted) {
        setState(() {});
      } else {
        await active.stop();
      }
    } catch (_) {
      if (mounted) {
        setState(() => error =
            'Could not start sharing. Check selected files and Windows Firewall. No files are being offered by this screen.');
      }
    }
  }

  @override
  void dispose() {
    unawaited(session?.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = session;
    return Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PlaybackSheetHandle(),
              const Text('Direct send',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (active == null && error == null)
                const LinearProgressIndicator(minHeight: 2),
              if (error != null)
                Text(error!,
                    style: const TextStyle(
                        color: Colors.orangeAccent, fontSize: 12.5)),
              if (active != null) ...[
                Text(
                    active.closed
                        ? 'Sharing stopped'
                        : '${active.files.length} selected videos · stops after 15 minutes or when this sheet closes',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 10),
                if (!active.closed && hosts.isEmpty)
                  const Text(
                      'No LAN IPv4 address found. Reconnect to Wi-Fi and try again.',
                      style: TextStyle(
                          color: Colors.orangeAccent, fontSize: 12.5)),
                if (!active.closed)
                  for (final host in hosts)
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: SelectableText(active.url(host),
                            style: const TextStyle(fontSize: 12.5)),
                        trailing: IconButton(
                            tooltip: 'Copy temporary private link',
                            onPressed: () => Clipboard.setData(
                                ClipboardData(text: active.url(host))),
                            icon: const Icon(Icons.copy, size: 20))),
                const Text(
                    'Open a link in the receiving device’s browser on the same trusted network, or paste it into Windows Quick Share Receive. Current Android Receive strips token paths, so use its browser for this Windows link. No automatic discovery, router setup or public hosting is performed.',
                    style: TextStyle(
                        color: Colors.white54, fontSize: 12, height: 1.5)),
                const SizedBox(height: 10),
                Text(
                    '${active.completed} file responses sent (not confirmation that the receiver saved them)',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 11.5)),
                const SizedBox(height: 14),
                SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                        onPressed: active.closed
                            ? null
                            : () async {
                                await active.stop();
                                if (mounted) setState(() {});
                              },
                        icon: const Icon(Icons.stop_rounded),
                        label: const Text('Stop sharing'))),
              ],
            ]));
  }
}

class _ReceiveSheet extends StatefulWidget {
  const _ReceiveSheet();
  @override
  State<_ReceiveSheet> createState() => _ReceiveSheetState();
}

class _ReceiveSheetState extends State<_ReceiveSheet> {
  final address = TextEditingController();
  final client = LocalShareClient();
  List<ShareFile> files = [];
  final selected = <int>{};
  final downloaded = <String>[];
  Uri? base;
  bool busy = false, trusted = false;
  bool batchCancelled = false;
  String? error;
  int received = 0, total = 0;
  Future<void> connect() async {
    if (busy || !trusted) return;
    setState(() {
      busy = true;
      error = null;
      files = [];
      selected.clear();
      base = null;
    });
    try {
      final uri = normalizeShareAddress(address.text);
      final manifest = await client.manifest(uri);
      if (mounted) {
        setState(() {
          base = uri;
          files = manifest;
          if (files.isEmpty) {
            error = 'Sender is not offering any supported media.';
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error =
            'Could not read the sender list. Check the full temporary link, same-network access and that the send session is still open.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> download() async {
    if (busy || base == null || selected.isEmpty) return;
    setState(() => busy = true);
    String? destination;
    try {
      destination = await getDirectoryPath(
          confirmButtonText: 'Save received videos here');
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not open the destination folder picker.';
        });
      }
      return;
    }
    if (!mounted) return;
    if (destination == null) {
      setState(() => busy = false);
      return;
    }
    setState(() {
      busy = true;
      batchCancelled = false;
      error = null;
      received = 0;
      total = 0;
    });
    try {
      for (final file
          in files.where((f) => selected.contains(f.index)).toList()) {
        if (batchCancelled) throw const ShareCancelled();
        final saved = await client.download(base!, file, Directory(destination),
            onProgress: (done, size) {
          if (mounted) {
            setState(() {
              received = done;
              total = size;
            });
          }
        });
        downloaded.add(saved.path);
        if (!mounted) return;
        setState(() => selected.remove(file.index));
      }
    } on ShareCancelled {
      if (mounted) {
        setState(() => error =
            'Transfer cancelled. Incomplete copies are cleaned up where possible; completed files kept.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => error =
            'Transfer failed. Check the sender, disk space and destination. Incomplete copies are cleaned up where possible; completed files kept.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    client.cancel();
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: EdgeInsets.fromLTRB(
          18, 0, 18, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PlaybackSheetHandle(),
            const Text('Receive from another device',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
                controller: address,
                onChanged: (_) => setState(() {
                      files = [];
                      selected.clear();
                      base = null;
                    }),
                enabled: !busy,
                decoration: const InputDecoration(
                    labelText: 'Sender address / full temporary link',
                    hintText: 'http://192.168.1.10:4747',
                    border: OutlineInputBorder())),
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: trusted,
                onChanged:
                    busy ? null : (v) => setState(() => trusted = v ?? false),
                title: const Text('I trust the sender and this network',
                    style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                    'Downloads use HTTP without encryption unless the sender explicitly provides HTTPS. Received filenames are sanitized; files are saved only to your chosen folder.',
                    style: TextStyle(color: Colors.white54, fontSize: 11.5))),
            OutlinedButton(
                onPressed: busy || !trusted ? null : connect,
                child: const Text('Connect / load files')),
            if (error != null)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(error!,
                      style: const TextStyle(
                          color: Colors.orangeAccent, fontSize: 12))),
            if (files.isNotEmpty)
              SizedBox(
                  height: 200,
                  child: ListView(children: [
                    for (final file in files)
                      CheckboxListTile(
                          value: selected.contains(file.index),
                          onChanged: busy
                              ? null
                              : (v) => setState(() {
                                    if (v == true) {
                                      selected.add(file.index);
                                    } else {
                                      selected.remove(file.index);
                                    }
                                  }),
                          title: Text(file.name,
                              style: const TextStyle(fontSize: 13.5)),
                          subtitle: Text(mediaSize(file.size),
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 11.5)))
                  ])),
            if (busy) ...[
              LinearProgressIndicator(
                  value: total > 0 ? (received / total).clamp(0, 1) : null,
                  minHeight: 4),
              Text('${mediaSize(received)} of ${mediaSize(total)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              TextButton(
                  onPressed: () {
                    batchCancelled = true;
                    client.cancel();
                  },
                  child: const Text('Cancel transfer'))
            ],
            if (files.isNotEmpty)
              FilledButton.icon(
                  onPressed: busy || selected.isEmpty ? null : download,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Receive selected · choose folder')),
            if (downloaded.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextButton(
                      onPressed: busy
                          ? null
                          : () => Navigator.pop(context, downloaded),
                      child: Text(
                          'Done · add ${downloaded.length} received videos to library'))),
          ]));
}
