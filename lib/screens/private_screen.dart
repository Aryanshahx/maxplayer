import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/video_track.dart';
import '../services/native_bridge.dart';
import '../state/media_player_state.dart';
import '../state/private_vault.dart';
import '../state/theme_state.dart';
import '../state/video_library_state.dart';
import '../utils/formatters.dart';
import '../widgets/fade_in_image.dart';
import '../widgets/video_picker_sheet.dart';
import 'player_screen.dart';

/// Private folder screen (v21): PIN gate -> list of hidden videos with
/// play / move-out actions. Files themselves live in the app's private
/// directory (see [PrivateVault]). v29: a "+" button moves selected
/// library videos straight into the vault.
class PrivateScreen extends StatefulWidget {
  final MediaPlayerState player;

  /// Source list for the v29 "+" picker (library videos only - hidden
  /// files never appear in it since the scanner skips app-private dirs).
  final VideoLibraryState library;

  const PrivateScreen({
    super.key,
    required this.player,
    required this.library,
  });

  @override
  State<PrivateScreen> createState() => _PrivateScreenState();
}

class _PrivateScreenState extends State<PrivateScreen> {
  final _vault = PrivateVault();
  final _pinCtrl = TextEditingController();
  final _pin2Ctrl = TextEditingController();

  bool? _hasPin; // null = still loading
  bool _unlocked = false;
  String? _error;
  bool _busy = false;
  List<File>? _videos;

  /// v24: a vault-storage failure (denied mkdir on some devices) is shown
  /// here instead of crashing the app (was an unhandled zone error).
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final has = await _vault.hasPin();
    if (mounted) setState(() => _hasPin = has);
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _pin2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pinCtrl.text.trim();
    if (pin.length < 4 || pin.length > 8) {
      setState(() => _error = 'PIN must be 4-8 digits');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_hasPin == false) {
        // First visit: create the PIN (enter twice to avoid typos).
        if (_pin2Ctrl.text.trim() != pin) {
          setState(() => _error = 'PINs do not match');
          return;
        }
        await _vault.setPin(pin);
        _hasPin = true;
        _unlocked = true;
      } else {
        if (await _vault.verifyPin(pin)) {
          _unlocked = true;
        } else {
          setState(() => _error = 'Wrong PIN');
          return;
        }
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// v25: user forgot their PIN. v26: FIRST the phone's own screen lock
  /// (device password / pattern / PIN / fingerprint) must be passed -
  /// only the phone's owner may reset the vault PIN.
  ///
  /// The hidden videos are NOT wiped either way (they live in the
  /// app-private folder regardless of the PIN); only the door code
  /// resets, then the normal "create PIN" flow re-secures it.
  Future<void> _forgotPin() async {
    setState(() => _busy = true);
    bool unlocked;
    try {
      unlocked = await NativeBridge.confirmDeviceCredential(
        title: 'Unlock to reset the Private folder PIN',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (!unlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Phone unlock failed or cancelled - PIN not reset'),
        ),
      );
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text('Forgot your PIN?',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: const Text(
          'Your hidden videos are SAFE - they stay in the app\'s private '
          'folder either way.\n\nResetting removes the old PIN so you can '
          'create a new one. You just unlocked the phone, so we know it\'s '
          'really you.',
          style:
              TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep trying'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reset PIN'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await _vault.resetPin();
      setState(() {
        _hasPin = false;
        _unlocked = false;
        _error = null;
        _pinCtrl.clear();
        _pin2Ctrl.clear();
      });
    }
  }

  Future<void> _refresh() async {
    try {
      final vids = await _vault.listVideos();
      if (mounted) {
        setState(() {
          _videos = vids;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = e
            .toString()
            .replaceAll('FileSystemException: ', '')
            .replaceAll('Exception: ', ''));
      }
    }
  }

  Future<void> _play(File file) async {
    final files = _videos ?? const <File>[];
    final tracks = [
      for (final f in files)
        VideoTrack(
          id: f.path,
          title: f.path.split('/').last,
          path: f.path,
        ),
    ];
    final idx = tracks.indexWhere((t) => t.path == file.path);
    await widget.player.setPlaylistAndPlay(tracks, idx < 0 ? 0 : idx);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(player: widget.player)),
    );
  }

  /// v29: "+" - select library videos and move them into the vault.
  /// Same "All files access" pre-check as the library's long-press flow.
  Future<void> _addVideos() async {
    if (!await Permission.manageExternalStorage.isGranted) {
      final status = await Permission.manageExternalStorage.request();
      if (!mounted) return;
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Adding videos needs "All files access": allow it, then '
              'tap + again',
            ),
          ),
        );
        return;
      }
    }
    if (!mounted) return;
    final selected = await VideoPickerSheet.show(
      context,
      widget.library.videos,
      title: 'Add to Private folder',
      actionLabel: 'Hide',
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    setState(() => _busy = true);
    var moved = 0;
    try {
      for (final t in selected) {
        try {
          await _vault.hide(t.path);
          widget.player.removeHistoryEntry(t.path);
          moved++;
        } catch (_) {
          // Keep going with the rest of the selection.
        }
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            moved > 0
                ? 'Moved $moved video(s) to the Private folder'
                : 'Could not hide the videos',
          ),
        ),
      );
    }
  }

  Future<void> _unhide(File file) async {
    try {
      final moved = await _vault.unhide(file.path);
      widget.player.removeHistoryEntry(file.path);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Moved back to Movies: ${moved.path.split('/').last}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not move the video out')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text('Private folder'),
        actions: [
          // v29: add videos to the vault from right here.
          if (_unlocked)
            IconButton(
              tooltip: 'Add videos',
              icon: const Icon(Icons.add),
              onPressed: _busy ? null : _addVideos,
            ),
        ],
      ),
      body: _hasPin == null
          ? const Center(child: CircularProgressIndicator())
          : !_unlocked
              ? _pinGate(accent)
              : _videoList(accent),
    );
  }

  Widget _pinGate(Color accent) {
    final creating = _hasPin == false;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 56, color: accent),
            const SizedBox(height: 14),
            Text(
              creating ? 'Create a PIN' : 'Private folder',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              creating
                  ? 'Choose 4-8 digits. Hidden videos stay inside the app\'s '
                      'private folder - invisible to Gallery and file managers.'
                  : 'Enter your PIN to see hidden videos.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 18),
            _pinField(_pinCtrl, creating ? 'New PIN (4-8 digits)' : 'PIN'),
            if (creating) ...[
              const SizedBox(height: 10),
              _pinField(_pin2Ctrl, 'Repeat PIN'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: Icon(creating ? Icons.check : Icons.lock_open),
                label: Text(creating ? 'Create & open' : 'Unlock'),
              ),
            ),
            if (!creating) ...[
              const SizedBox(height: 6),
              // v25: forgotten PIN path - keeps the videos, only clears
              // the door code (the folder location is the real hiding).
              TextButton(
                onPressed: _busy ? null : _forgotPin,
                child: Text(
                  'Forgot PIN?',
                  style: TextStyle(
                      color: accent.withValues(alpha: 0.6), fontSize: 12.5),
                ),
              ),
            ],
            if (creating) ...[
              const SizedBox(height: 14),
              const Text(
                'Warning: uninstalling the app also deletes hidden videos. '
                'Move them out first.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.amberAccent, fontSize: 11.5),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pinField(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      obscureText: true,
      maxLength: 8,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(color: Colors.white, letterSpacing: 4),
      decoration: InputDecoration(
        counterText: '',
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onSubmitted: (_) => _submit(),
    );
  }

  Widget _videoList(Color accent) {
    final loadError = _loadError;
    if (loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 40, color: accent.withValues(alpha: 0.7)),
              const SizedBox(height: 12),
              Text(
                'Private folder could not open:\n$loadError',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: accent.withValues(alpha: 0.8), height: 1.5),
              ),
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final vids = _videos;
    if (vids == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vids.isEmpty) {
      // v22 (user request): the how-to line belongs ON this screen.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline,
                  size: 44, color: accent.withValues(alpha: 0.65)),
              const SizedBox(height: 12),
              const Text(
                'Hold on a video in the Library to add it to the Private folder',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white70, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 6),
              const Text(
                'Nothing is hidden yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, height: 1.5),
              ),
              const SizedBox(height: 14),
              // v29: same as the "+" in the top bar.
              FilledButton.icon(
                onPressed: _busy ? null : _addVideos,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add videos'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        itemCount: vids.length,
        itemBuilder: (context, i) {
          final f = vids[i];
          final name = f.path.split('/').last;
          final size = f.lengthSync();
          return ListTile(
            // v25: real thumbnails (generated via the same native pipeline
            // the library uses) instead of a bare lock icon.
            leading: _VaultThumb(path: f.path, accent: accent),
            title: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // v25: the private screen follows the picked theme colour.
              style: TextStyle(color: accent),
            ),
            subtitle: Text(
              formatFileSize(size),
              style: TextStyle(
                  color: accent.withValues(alpha: 0.5), fontSize: 12),
            ),
            onTap: () => _play(f),
            trailing: TextButton.icon(
              onPressed: () => _confirmUnhide(f),
              icon: const Icon(Icons.lock_open, size: 16),
              label: const Text('Move out'),
            ),
          );
        },
      ),
    );
  }

  void _confirmUnhide(File f) {
    final name = f.path.split('/').last;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text('Move out of Private?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          '"$name" will move to the Movies folder and become visible to '
          'Gallery and other apps again.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _unhide(f);
            },
            child: const Text('Move out'),
          ),
        ],
      ),
    );
  }
}

/// v25: thumbnail for a hidden video. Hidden files skip the library scan,
/// so the tile resolves the cached image itself - and if the cache has no
/// entry (video hidden before it had a thumb), it asks the native metadata
/// pipeline to build one into the shared thumbs cache.
class _VaultThumb extends StatefulWidget {
  final String path;
  final Color accent;
  const _VaultThumb({required this.path, required this.accent});

  @override
  State<_VaultThumb> createState() => _VaultThumbState();
}

class _VaultThumbState extends State<_VaultThumb> {
  String? _thumbPath;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final cached = await NativeBridge.thumbnailPathFor(widget.path);
      if (cached != null && File(cached).existsSync()) {
        if (mounted) setState(() => _thumbPath = cached);
        return;
      }
      // Not cached: build one through the native pipeline.
      final meta = await NativeBridge.fetchMetadata(widget.path);
      final made = meta.thumbnailPath;
      if (made != null && File(made).existsSync() && mounted) {
        setState(() => _thumbPath = made);
      }
    } catch (_) {
      // No thumbnail - the lock fallback shows.
    }
  }

  @override
  Widget build(BuildContext context) {
    final thumb = _thumbPath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 56,
        height: 34,
        child: thumb != null
            ? Image.file(
                File(thumb),
                fit: BoxFit.cover,
                cacheWidth: 160,
                frameBuilder: fadeInImageFrame,
                errorBuilder: (_, __, ___) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() => Container(
        color: widget.accent.withValues(alpha: 0.12),
        child: Icon(Icons.lock, size: 15, color: widget.accent),
      );
}
