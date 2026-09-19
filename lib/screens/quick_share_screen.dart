import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../services/native_bridge.dart';
import '../services/quick_share_client.dart';
import '../services/quick_share_server.dart';
import '../theme.dart';
import '../utils/badges.dart';
import '../utils/crash_log.dart';
import '../utils/format.dart';

/// v1.0.21 Quick Share — two fully self-contained paths:
///  • DIRECT SEND: this device hosts the files over local HTTP (+QR/link);
///    the receiver needs NOTHING installed — Max Player's Receive mode or
///    any browser on the same Wi-Fi downloads them.
///  • RECEIVE: type/paste the sender address, pick files, they land in
///    the video library (Movies/MaxPlayer via MediaStore insert).
/// The old "other apps" sheet (share_plus) stays as a fallback mode.
class QuickShareScreen extends StatefulWidget {
  const QuickShareScreen({super.key});

  @override
  State<QuickShareScreen> createState() => _QuickShareScreenState();
}

class _QuickShareScreenState extends State<QuickShareScreen> {
  List<AssetEntity>? _videos;
  final Set<String> _selected = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final perm = await PhotoManager.requestPermissionExtend();
    if (!perm.hasAccess || !mounted) return;
    final all = await PhotoManager.getAssetPathList(
        type: RequestType.video, hasAll: true);
    if (all.isEmpty) {
      if (mounted) setState(() => _videos = []);
      return;
    }
    final vids = await all.first.getAssetListPaged(page: 0, size: 200);
    if (mounted) setState(() => _videos = vids);
  }

  Future<List<QuickShareFileEntry>> _resolveSelected() async {
    final out = <QuickShareFileEntry>[];
    for (final v in _videos!) {
      if (!_selected.contains(v.id)) continue;
      final f = await v.file;
      if (f != null && f.existsSync()) {
        out.add(QuickShareFileEntry(
          name: v.title ?? f.path.split('/').last,
          size: f.lengthSync(),
          path: f.path,
        ));
      }
    }
    return out;
  }

  // ------------------------------------------------ fallback: system sheet
  Future<void> _shareViaApps() async {
    setState(() => _busy = true);
    CrashLog.crumb('quickshare.send', {'count': _selected.length});
    try {
      final entries = await _resolveSelected();
      if (entries.isNotEmpty) {
        await SharePlus.instance.share(ShareParams(
            files: [for (final e in entries) XFile(e.path)],
            text: entries.length == 1
                ? 'Shared from Max Player'
                : '${entries.length} videos from Max Player'));
      }
    } catch (e) {
      CrashLog.error('quickshare.failed', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Share failed')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  // ------------------------------------------------ direct send (server)
  Future<void> _directSend() async {
    setState(() => _busy = true);
    try {
      final entries = await _resolveSelected();
      if (entries.isEmpty) return;
      if (!mounted) return;
      await _DirectSendSheet.show(context, entries);
    } catch (e) {
      CrashLog.error('quickshare.direct_failed', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not start the direct-share server')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------ receive (client)
  Future<void> _receive() async {
    await _ReceiveSheet.show(context);
    // Library rescan happens on the home screen's refresh when returning.
  }

  @override
  Widget build(BuildContext context) {
    final vids = _videos;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Share'),
        actions: [
          IconButton(
            tooltip: 'Receive from another device',
            icon: Icon(Icons.download_rounded, color: AppColors.accent),
            onPressed: _receive,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: vids == null
                ? Center(
                    child: CircularProgressIndicator(color: AppColors.accent))
                : vids.isEmpty
                    ? const Center(
                        child: Text('No videos on this device.',
                            style:
                                TextStyle(color: AppColors.textSecondary)))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: vids.length,
                        separatorBuilder: (_, i) => const SizedBox(height: 6),
                        itemBuilder: (context, i) {
                          final v = vids[i];
                          final sel = _selected.contains(v.id);
                          return Card(
                            child: CheckboxListTile(
                              value: sel,
                              activeColor: AppColors.accent,
                              checkColor: AppColors.onAccent,
                              title: Text(v.title ?? 'Video',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 13.5)),
                              subtitle: FutureBuilder<String>(
                                future: resolvedQualityBadge(v),
                                builder: (context, snap) => Text(
                                  '${snap.data ?? qualityBadge(v.width, v.height)} · '
                                  '${formatDuration(Duration(seconds: v.duration))}',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11.5),
                                ),
                              ),
                              onChanged: (_) => setState(() => sel
                                  ? _selected.remove(v.id)
                                  : _selected.add(v.id)),
                            ),
                          );
                        },
                      ),
          ),
          if (_selected.isNotEmpty)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _directSend,
                        icon: const Icon(Icons.wifi_tethering_rounded,
                            size: 18),
                        label: const Text('Direct send'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _shareViaApps,
                        icon: const Icon(Icons.ios_share_rounded, size: 18),
                        label: const Text('Via other apps'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Direct send sheet: runs the HTTP host while open; receiver downloads
/// with Max Player Receive or ANY browser — no dependency on a third app.
class _DirectSendSheet extends StatefulWidget {
  const _DirectSendSheet(this.entries);

  final List<QuickShareFileEntry> entries;

  static Future<void> show(
      BuildContext context, List<QuickShareFileEntry> entries) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _DirectSendSheet(entries),
    );
  }

  @override
  State<_DirectSendSheet> createState() => _DirectSendSheetState();
}

class _DirectSendSheetState extends State<_DirectSendSheet> {
  QuickShareSession? _session;
  final List<String> _log = [];
  String? _error;

  /// v1.0.2: which of the device's IPs the QR/link shows (multi-network
  /// phones — e.g. hotspot + wifi — often showed the wrong one, and the
  /// receiver then spun forever on an unreachable address).
  int _hostIndex = 0;

  /// Self-test result (null = still pinging / no hosts): proves the server
  /// answers through its advertised IP so "link not reachable" gets a
  /// precise culprit instead of guesswork.
  bool? _selfOk;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final s = await QuickShareSession.start(
        widget.entries,
        onEvent: (e) {
          if (!mounted) return;
          setState(() {
            _log.add(e);
            if (_log.length > 8) _log.removeAt(0);
          });
        },
      );
      if (!mounted) {
        await s.stop();
        return;
      }
      setState(() => _session = s);
      // Prove the server answers through its own advertised IP (fix 3).
      final ok = await s
          .selfTest()
          .timeout(const Duration(seconds: 7), onTimeout: () => false);
      if (mounted) setState(() => _selfOk = ok);
    } catch (e) {
      CrashLog.error('quickshare.server_failed', e);
      if (mounted) {
        setState(() => _error =
            'Could not start the share server — close other share/download '
            'apps and try again.');
      }
    }
  }

  @override
  void dispose() {
    _session?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    final sel = (s != null && s.hosts.isNotEmpty)
        ? _hostIndex.clamp(0, s.hosts.length - 1)
        : 0;
    final url = (s != null && s.hosts.isNotEmpty)
        ? quickShareBaseUrl(s.hosts[sel], s.port)
        : s?.primaryUrl ?? '';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Direct send (${widget.entries.length})',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'Receiver must be on the same Wi-Fi. Open this link there — '
              'with Max Player Receive or any browser.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColors.danger))
            else if (s == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )
            else ...[
              if (s.hosts.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      for (var hi = 0; hi < s.hosts.length; hi++)
                        ChoiceChip(
                          label: Text(s.hosts[hi],
                              style: const TextStyle(fontSize: 11.5)),
                          selected: sel == hi,
                          onSelected: (_) => setState(() => _hostIndex = hi),
                        ),
                    ],
                  ),
                ),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(10),
                child: QrImageView(
                  data: url,
                  version: QrVersions.auto,
                  size: 170,
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied')));
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(url,
                            style: TextStyle(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w700,
                                fontSize: 16)),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.copy_rounded, size: 16),
                    ],
                  ),
                ),
              ),
              if (_selfOk != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _selfOk!
                        ? '✓ Server live and answering (port ${s.port}). If '
                            'the receiver\'s browser still can\'t open it, the '
                            'receiver is NOT on this network: wrong Wi-Fi, '
                            'VPN, or the router blocks device-to-device '
                            '("AP isolation").'
                        : '✗ The server is not answering even locally — '
                            'toggle Wi-Fi OFF/ON (or restart the hotspot) '
                            'and share again.',
                    style: TextStyle(
                        color: _selfOk!
                            ? Colors.greenAccent
                            : AppColors.danger,
                        fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'If the page opens slowly: both phones must be on the SAME '
                  'Wi-Fi • turn OFF VPN / "data saver" on the receiving phone '
                  '• large videos crawl on busy 2.4GHz Wi-Fi — keep both '
                  'phones near the router.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              if (_log.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in _log)
                        Text('• $line',
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11.5)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Receive sheet: sender address → manifest → pick → download → gallery.
class _ReceiveSheet extends StatefulWidget {
  const _ReceiveSheet();

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: const _ReceiveSheet(),
      ),
    );
  }

  @override
  State<_ReceiveSheet> createState() => _ReceiveSheetState();
}

class _ReceiveSheetState extends State<_ReceiveSheet> {
  final TextEditingController _addr = TextEditingController();
  final QuickShareClient _client = QuickShareClient();
  List<RemoteShareFile>? _manifest;
  final Set<int> _picked = {};
  String? _error;
  bool _busy = false;
  final Map<int, double> _progress = {};
  String _base = '';

  Future<void> _fetch() async {
    setState(() {
      _busy = true;
      _error = null;
      _manifest = null;
    });
    try {
      _base = QuickShareClient.normalizeBase(_addr.text);
      final m = await _client.fetchManifest(_base);
      if (!mounted) return;
      setState(() {
        _manifest = m;
        _picked.addAll(m.map((e) => e.index));
      });
    } catch (e) {
      CrashLog.error('quickshare.fetch_failed', e);
      if (mounted) {
        setState(() => _error =
            'No sender found there — check the address and same Wi-Fi.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadPicked() async {
    if (_manifest == null) return;
    setState(() => _busy = true);
    var ok = 0, fail = 0;
    for (final remote in _manifest!) {
      if (!_picked.contains(remote.index)) continue;
      try {
        final temp = await _client.download(
          _base,
          remote,
          onProgress: (r, t) {
            if (!mounted || t <= 0) return;
            setState(() => _progress[remote.index] = r / t);
          },
        );
        final saved = await NativeBridge.saveToGallery(
            path: temp.path, name: remote.name, kind: 'video');
        try {
          await temp.delete();
        } catch (_) {}
        if (saved) {
          ok++;
        } else {
          fail++;
        }
      } catch (e) {
        CrashLog.error('quickshare.receive_one_failed', e);
        fail++;
      }
      if (!mounted) return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    // SnackBar FIRST: after pop() this State's context is deactivated and
    // ScaffoldMessenger.of(context) would throw.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(fail == 0
            ? 'Received $ok video(s) — saved to Movies/MaxPlayer'
            : '$ok saved, $fail failed')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final m = _manifest;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Receive videos',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addr,
                    keyboardType: TextInputType.url,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Sender address, e.g. 192.168.1.5:4747',
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _busy ? null : _fetch(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _fetch,
                  child: const Text('Find'),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.danger)),
              ),
            if (m != null) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final f in m)
                      CheckboxListTile(
                        value: _picked.contains(f.index),
                        activeColor: AppColors.accent,
                        checkColor: AppColors.onAccent,
                        dense: true,
                        title: Text(f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 13)),
                        subtitle: _progress.containsKey(f.index)
                            ? LinearProgressIndicator(
                                value: _progress[f.index])
                            : Text(formatBytes(f.size),
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11.5)),
                        onChanged: _busy
                            ? null
                            : (_) => setState(() => _picked.contains(f.index)
                                ? _picked.remove(f.index)
                                : _picked.add(f.index)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      _busy || _picked.isEmpty ? null : _downloadPicked,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(_busy
                      ? 'Downloading…'
                      : 'Download ${_picked.length} to library'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
