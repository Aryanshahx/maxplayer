import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/local_store.dart';
import '../widgets/video_grid.dart';

/// PIN-gated Private Space, with device-password recovery:
/// "Forgot PIN?" verifies the system lock (biometric/PIN/pattern)
/// via local_auth, then lets the user set a new PIN.
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
      final entered = await _askPin(
          title: 'Enter PIN', hint: 'PIN', allowForgot: true);
      if (entered == _kForgot) {
        await _recoverWithDeviceLock(); // device lock -> set new PIN
        return;
      }
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

  static const _kForgot = '__forgot__';

  Future<String?> _askPin(
      {required String title, required String hint, bool allowForgot = false}) {
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
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          if (allowForgot)
            TextButton(
              onPressed: () => Navigator.of(context).pop(_kForgot),
              child: Text('Forgot PIN?',
                  style: TextStyle(color: AppColors.accent, fontSize: 13)),
            )
          else
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (allowForgot)
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
                onPressed: () =>
                    Navigator.of(context).pop(ctrl.text.trim()),
                child: const Text('Unlock'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Device-lock verified PIN reset (biometric / system PIN / pattern).
  Future<void> _recoverWithDeviceLock() async {
    try {
      final auth = LocalAuthentication();
      final supported = await auth.isDeviceSupported();
      if (!supported) {
        CrashLog.crumb('private.recovery_unsupported');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'No device lock found — set a screen lock in Android settings first')));
          Navigator.of(context).maybePop();
        }
        return;
      }
      final ok = await auth.authenticate(
        localizedReason:
            'Verify your device identity to reset the Private Space PIN',
        biometricOnly: false, // device PIN/pattern allowed, not just biometrics
      );
      if (!mounted) return;
      if (ok) {
        await _store.clearPin();
        CrashLog.crumb('private.pin_reset');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Verified! Now set a new PIN.')));
        _gate(); // falls into "create PIN" path
      } else {
        CrashLog.crumb('private.recovery_cancelled');
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      CrashLog.error('private.recovery_failed', e);
      if (mounted) Navigator.of(context).maybePop();
    }
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
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : !_unlocked
              ? const SizedBox.shrink()
              : _videos.isEmpty
                  ? const Center(
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
