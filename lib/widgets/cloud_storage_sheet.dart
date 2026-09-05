import 'dart:async';

import 'package:flutter/material.dart';

import '../services/native_bridge.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';

/// v111: Cloud Storage is IMPORT-ONLY now. "The Easy Way" taken all the way:
/// the Google Sign-In / Drive-API path is gone completely - Android's own
/// document picker lists every installed storage provider app (Google Drive,
/// Dropbox, OneDrive, ...) plus this device, videos only. The picked file is
/// copied into the app with a live progress bar; cloud imports can then be
/// kept permanently with "Save to device" (Movies/Max Player).
class CloudStorageSheet extends StatefulWidget {
  final Future<void> Function(String url, String title,
      [Map<String, String>? httpHeaders]) onPlay;

  const CloudStorageSheet({super.key, required this.onPlay});

  static Future<void> show(
    BuildContext context, {
    required Future<void> Function(String url, String title,
            [Map<String, String>? httpHeaders])
        onPlay,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141c),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => CloudStorageSheet(onPlay: onPlay),
    );
  }

  @override
  State<CloudStorageSheet> createState() => _CloudStorageSheetState();
}

class _CloudStorageSheetState extends State<CloudStorageSheet> {
  bool _importing = false;
  bool _progressVisible = false;
  final ValueNotifier<int> _progDone = ValueNotifier<int>(0);
  final ValueNotifier<int> _progTotal = ValueNotifier<int>(0);
  Timer? _progressTimer;

  @override
  void dispose() {
    _progressTimer?.cancel();
    NativeBridge.pickProgressListener = null;
    _progDone.dispose();
    _progTotal.dispose();
    super.dispose();
  }

  /// The one action of this sheet: open Android's picker, copy the chosen
  /// video in (progress bar), then play it or save a permanent copy.
  Future<void> _importVideo() async {
    if (_importing) return;
    setState(() => _importing = true);
    _progDone.value = 0;
    _progTotal.value = 0;
    // Copy progress streams in while a cloud file imports; a device file
    // resolves silently without any events.
    NativeBridge.pickProgressListener = (done, total) {
      if (!mounted) return;
      _progDone.value = done;
      _progTotal.value = total;
      if (!_progressVisible) _showImportProgress();
    };
    // Unknown-size copies emit their first event late; open the bar after a
    // grace delay so big imports never look frozen.
    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted && _importing && !_progressVisible) _showImportProgress();
    });

    Map<String, dynamic>? picked;
    try {
      picked = await NativeBridge.pickVideoDocument();
    } finally {
      _progressTimer?.cancel();
      NativeBridge.pickProgressListener = null;
    }
    if (!mounted) return;
    if (_progressVisible) {
      // showDialog defaults to the root navigator; pop only that dialog,
      // not this bottom sheet.
      Navigator.of(context, rootNavigator: true).pop();
      _progressVisible = false;
    }
    setState(() => _importing = false);
    if (picked == null) return; // picker canceled, or copy aborted

    final messenger = ScaffoldMessenger.maybeOf(context);
    final path = picked['path']?.toString() ?? '';
    final name = picked['name']?.toString() ?? 'video';
    if (path.isEmpty) {
      _showInfoDialog(
        "Couldn't import that file",
        'The selected video could not be read. Try another one.',
      );
      return;
    }
    if (picked['cached'] != true) {
      // A plain local file: already on the device, import is unnecessary.
      _playPicked(path, name);
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Already on this device - opening it'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1b1b24),
        title: const Text('Play or keep?',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: Text(
          '"$name" came from a cloud app and is stored only as a temporary '
          'copy. Keep a permanent copy on this device?',
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('play'),
            child: const Text('Play once'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: themeState.accent,
              foregroundColor: themeState.onAccent,
            ),
            onPressed: () => Navigator.of(ctx).pop('save'),
            child: const Text('Save to device'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'play') {
      _playPicked(path, name);
      return;
    }
    final saved = await NativeBridge.savePickedVideoToDevice(
      sourceUri: picked['sourceUri']?.toString(),
      cachePath: path,
      name: name,
    );
    if (!mounted) return;
    if (saved == null) {
      _showInfoDialog(
        "Couldn't save",
        'The copy could not be written to Movies/Max Player. Playing the '
            'temporary copy is still possible.',
      );
      return;
    }
    final savedPath = saved['path']?.toString() ?? '';
    final location = saved['location']?.toString() ?? 'Movies/Max Player';
    _playPicked(savedPath.isNotEmpty ? savedPath : path, name);
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Saved to $location'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _playPicked(String path, String name) {
    Navigator.of(context).pop();
    // Same onPlay pipeline other local files use: libmpv opens local
    // absolute paths exactly like stream URLs.
    widget.onPlay(path, name);
  }

  void _showImportProgress() {
    _progressVisible = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1b1b24),
        title: const Text('Importing video…',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: AnimatedBuilder(
          animation: Listenable.merge([_progDone, _progTotal]),
          builder: (_, __) {
            final done = _progDone.value;
            final total = _progTotal.value;
            final double? pct =
                total > 0 ? (done / total).clamp(0.0, 1.0) : null;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: pct,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 10),
                Text(
                  total > 0
                      ? '${formatFileSize(done)} of ${formatFileSize(total)}'
                      : '${formatFileSize(done)} copied…',
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
                const Text(
                  'The video is being copied from the storage app.',
                  style: TextStyle(color: Colors.white38, fontSize: 11.5),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              NativeBridge.abortPickCopy();
              Navigator.of(ctx).pop();
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    ).then((_) => _progressVisible = false);
  }

  void _showInfoDialog(String title, String body) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1b1b24),
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontSize: 17)),
        content: Text(
          body,
          style:
              const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.cloud_download_outlined, color: accent, size: 24),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Import from cloud storage',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                    child: Icon(Icons.drive_folder_upload_outlined,
                        size: 38, color: accent),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Import a video',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Android's file picker opens with Google Drive, Dropbox, "
                    'OneDrive or any storage app you use - videos only. The '
                    'picked file is copied into Max Player with a live '
                    'progress bar; keep it forever with Save to device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white54, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: themeState.onAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.file_open_outlined),
                      label: Text(
                        _importing
                            ? 'Importing…'
                            : 'Choose a video to import',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14.5),
                      ),
                      onPressed: _importing ? null : _importVideo,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No sign-in at all - the picker hands Max Player one '
                    'file at a time, read-only.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white38, fontSize: 11.5, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
