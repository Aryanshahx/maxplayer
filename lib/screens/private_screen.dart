import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/video_track.dart';
import '../state/media_player_state.dart';
import '../state/private_vault.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';
import 'player_screen.dart';

/// Private folder screen (v21): PIN gate -> list of hidden videos with
/// play / move-out actions. Files themselves live in the app's private
/// directory (see [PrivateVault]).
class PrivateScreen extends StatefulWidget {
  final MediaPlayerState player;

  const PrivateScreen({super.key, required this.player});

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
            leading: Icon(Icons.lock, color: accent, size: 20),
            title: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              formatFileSize(size),
              style:
                  const TextStyle(color: Colors.white38, fontSize: 12),
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
