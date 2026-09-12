import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:photo_manager/photo_manager.dart';

import '../services/native_bridge.dart';
import '../state/private_vault.dart';
import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/format.dart';
import '../utils/local_store.dart';
import '../utils/storage_permission.dart';
import '../widgets/video_picker_sheet.dart';
import 'player_screen.dart';

/// Private folder — old-app parity: a PIN gate guards the vault list; the
/// videos themselves live inside the app's private directory (invisible to
/// Gallery and file managers). "+" moves library videos in; "Move out"
/// restores them to Movies.
class PrivateScreen extends StatefulWidget {
  /// The home screen's video list, used by the "+" picker.
  final List<AssetEntity> libraryVideos;

  const PrivateScreen({super.key, this.libraryVideos = const []});

  @override
  State<PrivateScreen> createState() => _PrivateScreenState();
}

class _PrivateScreenState extends State<PrivateScreen> {
  final PrivateVault _vault = PrivateVault();
  final LocalStore _store = LocalStore();

  final _pinCtrl = TextEditingController();
  final _pin2Ctrl = TextEditingController();

  bool? _hasPin;
  bool _unlocked = false;
  bool _busy = false;
  String? _error;
  List<File>? _videos;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _pin2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final hasPin = await _vault.hasPin();
    if (mounted) setState(() => _hasPin = hasPin);
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final creating = _hasPin == false;
      final pin = _pinCtrl.text;
      if (creating) {
        if (pin.length < 4) {
          setState(() => _error = 'PIN must be at least 4 digits');
          return;
        }
        if (pin != _pin2Ctrl.text) {
          setState(() => _error = 'PINs do not match');
          return;
        }
        await _vault.setPin(pin);
        CrashLog.crumb('private.pin_created');
        setState(() {
          _hasPin = true;
          _unlocked = true;
        });
      } else {
        if (await _vault.verifyPin(pin)) {
          CrashLog.crumb('private.unlocked');
          _unlocked = true;
        } else {
          CrashLog.crumb('private.wrong_pin');
          setState(() => _error = 'Wrong PIN');
          return;
        }
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Forgot PIN: FIRST the phone's own screen lock (device password /
  /// pattern / PIN / fingerprint) must be passed — only the phone's owner
  /// may reset the vault PIN. The hidden videos are NOT wiped either way.
  Future<void> _forgotPin() async {
    setState(() => _busy = true);
    bool unlocked;
    try {
      final auth = LocalAuthentication();
      final supported = await auth.isDeviceSupported();
      if (!supported) {
        CrashLog.crumb('private.recovery_unsupported');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'No device lock found — set a screen lock in Android settings first')));
        }
        return;
      }
      unlocked = await auth.authenticate(
        localizedReason: 'Unlock to reset the Private folder PIN',
        biometricOnly: false,
      );
    } catch (e) {
      CrashLog.error('private.recovery_failed', e);
      unlocked = false;
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
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
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
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          path: file.path,
          title: file.path.split('/').last,
        ),
      ),
    );
  }

  /// "+" — select library videos and move them into the vault.
  Future<void> _addVideos() async {
    if (!await ensureStorageAccess()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Adding videos needs storage permission: allow it, then '
            'tap + again',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    final selected = await VideoPickerSheet.show(
      context,
      widget.libraryVideos,
      title: 'Add to Private folder',
      actionLabel: 'Hide',
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    setState(() => _busy = true);
    var moved = 0;
    try {
      for (final a in selected) {
        try {
          final f = await a.file;
          final path = f?.path;
          if (path == null || path.isEmpty) continue;
          await _vault.hide(path);
          await _store.scrubId(a.id);
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
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Moved back to Movies: ${moved.path.split('/').last}')),
        );
      }
    } catch (e) {
      CrashLog.error('private.unhide_failed', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not move the video out')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accent;
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text('Private folder'),
        actions: [
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
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: AppColors.onAccent,
                ),
                onPressed: _busy ? null : _submit,
                icon: Icon(creating ? Icons.check : Icons.lock_open),
                label: Text(creating ? 'Create & open' : 'Unlock'),
              ),
            ),
            if (!creating) ...[
              const SizedBox(height: 6),
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
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: AppColors.onAccent,
                ),
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
            leading: _VaultThumb(path: f.path, accent: accent),
            title: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: accent),
            ),
            subtitle: Text(
              formatBytes(size),
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

/// Thumbnail for a hidden video: resolves the native thumbnail cache (the
/// native pipeline builds one on demand), falling back to a lock tile.
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
      final made = await NativeBridge.videoThumbnail(widget.path);
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
                errorBuilder: (_, _, _) => _fallback(),
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
