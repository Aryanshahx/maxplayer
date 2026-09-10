import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/local_store.dart';
import '../widgets/video_grid.dart';

/// PIN-gated Private Space. Videos marked private are hidden from the
/// main grid and folder views; they only appear here after the PIN.
class PrivateScreen extends StatefulWidget {
  const PrivateScreen({super.key});

  @override
  State<PrivateScreen> createState() => _PrivateScreenState();
}

class _PrivateScreenState extends State<PrivateScreen> {
  final _store = LocalStore();
  bool _unlocked = false;
  bool _checking = true;
  List<AssetEntity> _videos = [];

  @override
  void initState() {
    super.initState();
    _gate();
  }

  Future<void> _gate() async {
    final pin = await _store.pin();
    if (!mounted) return;
    if (pin == null) {
      final created = await _askPin(
          title: 'Create a PIN', hint: 'Choose a PIN for Private Space');
      if (created == null || created.length < 4) {
        if (mounted) Navigator.of(context).maybePop();
        return;
      }
      await _store.setPin(created);
      CrashLog.crumb('private.pin_created');
      _unlock();
    } else {
      final entered = await _askPin(title: 'Enter PIN', hint: 'PIN');
      if (entered == pin) {
        CrashLog.crumb('private.unlocked');
        _unlock();
      } else {
        CrashLog.crumb('private.wrong_pin');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Wrong PIN')));
          Navigator.of(context).maybePop();
        }
      }
    }
  }

  Future<String?> _askPin({required String title, required String hint}) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Text(title,
            style:
                const TextStyle(color: AppColors.textPrimary, fontSize: 17)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 12,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textSecondary),
            counterText: '',
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
  }

  Future<void> _unlock() async {
    await _reload();
    if (mounted) {
      setState(() {
        _unlocked = true;
        _checking = false;
      });
    }
  }

  Future<void> _reload() async {
    final ids = await _store.privateIds();
    final list = <AssetEntity>[];
    for (final id in ids) {
      final a = await AssetEntity.fromId(id);
      if (a != null) list.add(a);
    }
    _videos = list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Private Space')),
      body: _checking
          ? Center(
              child: CircularProgressIndicator(color: AppColors.accent))
          : !_unlocked
              ? const SizedBox.shrink()
              : _videos.isEmpty
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Nothing here yet.\nLong-press any video → "Move to Private Space".',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  : VideoGrid(videos: _videos, onChanged: () async {
                      await _reload();
                      setState(() {});
                    }),
    );
  }
}
