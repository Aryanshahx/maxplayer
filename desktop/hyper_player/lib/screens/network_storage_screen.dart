import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../network_locations.dart';
import '../network_browser.dart';
import '../playlist.dart';

class DesktopNetworkStorageScreen extends StatefulWidget {
  const DesktopNetworkStorageScreen({super.key});
  @override
  State<DesktopNetworkStorageScreen> createState() =>
      _DesktopNetworkStorageScreenState();
}

class _DesktopNetworkStorageScreenState
    extends State<DesktopNetworkStorageScreen> {
  final name = TextEditingController(),
      host = TextEditingController(),
      port = TextEditingController(),
      path = TextEditingController();
  final saved = <DesktopNetworkLocation>[];
  DesktopNetworkProtocol protocol = DesktopNetworkProtocol.windowsShare;
  bool secure = true, form = false, loading = true, saving = false;
  String? error;
  bool loadFailed = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final values =
          decodeNetworkLocations(prefs.getString('hyper.network.locations.v1'));
      if (mounted) {
        setState(() {
          saved
            ..clear()
            ..addAll(values);
          loadFailed = false;
          error = null;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          loadFailed = true;
          error =
              'Could not load saved locations. Retry before adding or removing connections.';
        });
      }
    }
  }

  Future<void> persist(List<DesktopNetworkLocation> values) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString('hyper.network.locations.v1',
        jsonEncode(values.map((v) => v.toJson()).toList()))) {
      throw StateError('Could not save locations');
    }
  }

  Future<void> add() async {
    if (saving || loadFailed) return;
    final value = DesktopNetworkLocation(
        name: name.text.trim(),
        host: host.text.trim(),
        path: path.text.trim(),
        protocol: protocol,
        secure: secure,
        port: protocol == DesktopNetworkProtocol.webFile &&
                port.text.trim().isNotEmpty
            ? int.tryParse(port.text.trim()) ?? -1
            : null);
    try {
      value.validate();
      if (saved.length >= 200) {
        throw const FormatException(
            'Saved-location limit reached. Remove an unused connection first.');
      }
    } on FormatException catch (e) {
      setState(() => error = e.message.toString());
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await persist([value, ...saved]);
      if (mounted) {
        setState(() {
          saved.insert(0, value);
          form = false;
          name.clear();
          host.clear();
          port.clear();
          path.clear();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error =
            'Could not save location. Previous connections are unchanged.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> remove(int index) async {
    if (saving || loadFailed) return;
    setState(() => saving = true);
    final next = [...saved]..removeAt(index);
    try {
      await persist(next);
      if (mounted) {
        setState(() {
          saved
            ..clear()
            ..addAll(next);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            error = 'Could not remove saved location. No files were deleted.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> connect(DesktopNetworkLocation location) async {
    if (location.protocol == DesktopNetworkProtocol.webFile) {
      Navigator.pop(context, location.source);
      return;
    }
    final source = await Navigator.push<String>(
        context,
        MaterialPageRoute(
            builder: (_) => NetworkFolderScreen(path: location.source)));
    if (mounted && source != null) Navigator.pop(context, source);
  }

  @override
  void dispose() {
    name.dispose();
    host.dispose();
    port.dispose();
    path.dispose();
    super.dispose();
  }

  Widget field(TextEditingController controller, String label, String hint) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
              controller: controller,
              enabled: !saving,
              decoration: InputDecoration(
                  labelText: label,
                  hintText: hint,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: .05),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)))));
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: const Color(0xff14141c),
      appBar: AppBar(
          backgroundColor: const Color(0xff14141c),
          title: const Text('Network Storage (NAS / Share)',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          actions: [
            if (!form && !loading && !loadFailed)
              IconButton(
                  tooltip: 'Add Connection',
                  onPressed: saving
                      ? null
                      : () => setState(() {
                            form = true;
                            error = null;
                          }),
                  icon: const Icon(Icons.add_circle_outline))
          ]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : loadFailed
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(error ?? 'Could not load connections'),
                  TextButton(
                      onPressed: () {
                        setState(() => loading = true);
                        load();
                      },
                      child: const Text('Retry'))
                ]))
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: form
                          ? ListView(
                              padding: const EdgeInsets.all(18),
                              children: [
                                  Wrap(spacing: 8, runSpacing: 6, children: [
                                    ChoiceChip(
                                        label:
                                            const Text('SMB (Windows/Samba)'),
                                        selected: protocol ==
                                            DesktopNetworkProtocol.windowsShare,
                                        onSelected: saving
                                            ? null
                                            : (_) => setState(() => protocol =
                                                DesktopNetworkProtocol
                                                    .windowsShare)),
                                    ChoiceChip(
                                        label:
                                            const Text('HTTP(S) / WebDAV file'),
                                        selected: protocol ==
                                            DesktopNetworkProtocol.webFile,
                                        onSelected: saving
                                            ? null
                                            : (_) => setState(() => protocol =
                                                DesktopNetworkProtocol
                                                    .webFile)),
                                    const Tooltip(
                                        message:
                                            'FTP/FTPS authentication and protocol support are not implemented here',
                                        child: ChoiceChip(
                                            label: Text(
                                                'FTP / FTPS · unavailable'),
                                            selected: false,
                                            onSelected: null))
                                  ]),
                                  const SizedBox(height: 18),
                                  field(name, 'Connection name',
                                      'My media server'),
                                  field(host, 'Host / IP address',
                                      '192.168.1.10'),
                                  if (protocol ==
                                      DesktopNetworkProtocol.webFile) ...[
                                    SwitchListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text('Use HTTPS'),
                                        value: secure,
                                        onChanged: saving
                                            ? null
                                            : (v) =>
                                                setState(() => secure = v)),
                                    field(port, 'Port (optional)',
                                        secure ? '443' : '80')
                                  ],
                                  field(
                                      path,
                                      protocol ==
                                              DesktopNetworkProtocol
                                                  .windowsShare
                                          ? 'Share / folder path'
                                          : 'Direct media file path',
                                      protocol ==
                                              DesktopNetworkProtocol
                                                  .windowsShare
                                          ? r'Media\Movies'
                                          : '/media/example.mp4'),
                                  Text(
                                      protocol ==
                                              DesktopNetworkProtocol
                                                  .windowsShare
                                          ? 'Windows opens this share using your existing Windows network session. Connect/sign in through File Explorer first. Hyper Player does not store a NAS username or password.'
                                          : 'Opens a direct HTTP(S) media resource, not a WebDAV folder listing. Password login, embedded credentials and query tokens are not supported in saved locations. Only connect to servers you trust.',
                                      style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12.5,
                                          height: 1.5)),
                                  if (error != null)
                                    Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        child: Text(error!,
                                            style: const TextStyle(
                                                color: Colors.orangeAccent,
                                                fontSize: 12.5))),
                                  const SizedBox(height: 18),
                                  FilledButton.icon(
                                      onPressed: saving ? null : add,
                                      style: FilledButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor: Colors.black,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10))),
                                      icon: const Icon(Icons.save_outlined),
                                      label: const Text('Save connection')),
                                  TextButton(
                                      onPressed: saving
                                          ? null
                                          : () => setState(() {
                                                form = false;
                                                error = null;
                                              }),
                                      child: const Text('Cancel')),
                                ])
                          : Column(children: [
                              if (error != null)
                                Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Text(error!,
                                        style: const TextStyle(
                                            color: Colors.orangeAccent,
                                            fontSize: 12.5))),
                              Expanded(
                                  child: saved.isEmpty
                                      ? Center(
                                          child: Padding(
                                              padding: const EdgeInsets.all(24),
                                              child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                        Icons.dns_outlined,
                                                        size: 48,
                                                        color: Colors.white24),
                                                    const SizedBox(height: 12),
                                                    const Text(
                                                        'No saved network storage connections',
                                                        style: TextStyle(
                                                            color:
                                                                Colors.white54,
                                                            fontSize: 14)),
                                                    const SizedBox(height: 16),
                                                    FilledButton.icon(
                                                        onPressed: () =>
                                                            setState(() {
                                                              form = true;
                                                              error = null;
                                                            }),
                                                        style: FilledButton.styleFrom(
                                                            backgroundColor:
                                                                Colors.white,
                                                            foregroundColor:
                                                                Colors.black,
                                                            shape: RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            10))),
                                                        icon: const Icon(
                                                            Icons.add),
                                                        label: const Text(
                                                            'Add Network Storage',
                                                            style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold)))
                                                  ])))
                                      : ListView.separated(
                                          padding: const EdgeInsets.all(14),
                                          itemCount: saved.length,
                                          separatorBuilder: (_, i) =>
                                              const SizedBox(height: 8),
                                          itemBuilder: (context, i) {
                                            final location = saved[i];
                                            return Container(
                                                decoration: BoxDecoration(
                                                    color: Colors.white
                                                        .withValues(alpha: .05),
                                                    borderRadius: BorderRadius.circular(
                                                        12),
                                                    border: Border.all(
                                                        color: Colors.white12)),
                                                child: ListTile(
                                                    contentPadding:
                                                        const EdgeInsets.symmetric(
                                                            horizontal: 14,
                                                            vertical: 2),
                                                    leading: CircleAvatar(
                                                        backgroundColor:
                                                            Colors.white.withValues(
                                                                alpha: .2),
                                                        child: Icon(
                                                            location.protocol == DesktopNetworkProtocol.windowsShare ? Icons.folder_shared : Icons.storage,
                                                            color: Colors.white,
                                                            size: 18)),
                                                    title: Text(location.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                                    subtitle: Text(location.display, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white38, fontSize: 11.5)),
                                                    trailing: IconButton(tooltip: 'Remove saved connection (does not delete files)', onPressed: saving ? null : () => remove(i), icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 20)),
                                                    onTap: saving ? null : () => connect(location)));
                                          })),
                              const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: Text(
                                      'Saved names, hosts and paths are stored locally without encryption. Windows share/codec/server access must be verified on your PC.',
                                      style: TextStyle(
                                          color: Colors.white38,
                                          fontSize: 11.5,
                                          height: 1.4))),
                            ]))));
}

class NetworkFolderScreen extends StatefulWidget {
  final String path;
  const NetworkFolderScreen({super.key, required this.path});
  @override
  State<NetworkFolderScreen> createState() => _NetworkFolderScreenState();
}

class _NetworkFolderScreenState extends State<NetworkFolderScreen> {
  late Future<NetworkBrowseResult> entries;
  @override
  void initState() {
    super.initState();
    entries = browseNetworkDirectory(widget.path);
  }

  Future<void> child(String path) async {
    final source = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => NetworkFolderScreen(path: path)));
    if (mounted && source != null) Navigator.pop(context, source);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: const Color(0xff14141c),
      appBar: AppBar(
          backgroundColor: const Color(0xff14141c),
          title:
              Text(labelFor(widget.path), style: const TextStyle(fontSize: 17)),
          actions: [
            IconButton(
                tooltip: 'Refresh folder',
                onPressed: () => setState(
                    () => entries = browseNetworkDirectory(widget.path)),
                icon: const Icon(Icons.refresh_rounded))
          ]),
      body: FutureBuilder<NetworkBrowseResult>(
          future: entries,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || snapshot.data == null) {
              return Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.wifi_off_rounded,
                            size: 42, color: Colors.white24),
                        const SizedBox(height: 12),
                        const Text(
                            'Could not open this folder. Check the server and sign in through Windows File Explorer first.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: Colors.white54, fontSize: 13)),
                        TextButton(
                            onPressed: () => setState(() =>
                                entries = browseNetworkDirectory(widget.path)),
                            child: const Text('Retry'))
                      ])));
            }
            final result = snapshot.data!;
            return ListView(padding: const EdgeInsets.all(14), children: [
              Text(widget.path,
                  style:
                      const TextStyle(color: Colors.white38, fontSize: 11.5)),
              const SizedBox(height: 8),
              if (result.truncated)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                        'First 5,000 directory entries only. Open a smaller subfolder for more.',
                        style: TextStyle(
                            color: Colors.orangeAccent, fontSize: 12))),
              if (result.folders.isEmpty && result.files.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                        child: Text('No supported media or folders here.',
                            style: TextStyle(color: Colors.white54)))),
              for (final path in result.folders)
                ListTile(
                    leading: const Icon(Icons.folder_shared_rounded),
                    title: Text(labelFor(path)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => child(path)),
              for (final path in result.files)
                ListTile(
                    leading: const Icon(Icons.video_file_outlined),
                    title: Text(labelFor(path)),
                    subtitle: const Text('Play from Windows network share',
                        style:
                            TextStyle(color: Colors.white38, fontSize: 11.5)),
                    onTap: () => Navigator.pop(context, path)),
            ]);
          }));
}
