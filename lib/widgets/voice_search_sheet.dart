import 'dart:async';
import 'package:flutter/material.dart';

import '../services/native_bridge.dart';
import '../state/theme_state.dart';

/// v70: Custom in-app microphone speech recognition popup (no Google dialog).
/// Displays real-time voice volume ripples, live transcription, and one-tap submit.
class VoiceSearchSheet extends StatefulWidget {
  const VoiceSearchSheet({super.key});

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF14141c),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const VoiceSearchSheet(),
    );
  }

  @override
  State<VoiceSearchSheet> createState() => _VoiceSearchSheetState();
}

class _VoiceSearchSheetState extends State<VoiceSearchSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  String _status = 'Listening… speak now';
  String _partialText = '';
  double _rms = 0.0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    NativeBridge.configureCallbacks(
      onVoiceState: (state) {
        if (!mounted || _finished) return;
        setState(() {
          if (state == 'speaking') {
            _status = 'Listening…';
          } else if (state == 'processing') {
            _status = 'Searching…';
          }
        });
      },
      onVoiceRms: (rms) {
        if (!mounted || _finished) return;
        setState(() => _rms = rms.clamp(0.0, 10.0));
      },
      onVoicePartial: (text) {
        if (!mounted || _finished) return;
        setState(() => _partialText = text);
      },
      onVoiceResult: (result) {
        if (!mounted || _finished) return;
        _finished = true;
        Navigator.of(context).pop(result);
      },
      onVoiceError: (err) {
        if (!mounted || _finished) return;
        _finished = true;
        Navigator.of(context).pop(_partialText.isNotEmpty ? _partialText : null);
      },
    );

    unawaited(NativeBridge.startVoiceSearch());
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    unawaited(NativeBridge.stopVoiceSearch());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    final scale = 1.0 + (_rms / 10.0) * 0.4 + (_pulseCtrl.value * 0.1);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _status,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 20),
            if (_partialText.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '"$_partialText"',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            GestureDetector(
              onTap: () {
                if (_partialText.isNotEmpty) {
                  Navigator.of(context).pop(_partialText);
                }
              },
              child: AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, _) {
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withValues(alpha: 0.2),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.6),
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.35),
                            blurRadius: 18 * scale,
                            spreadRadius: 4 * scale,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.mic,
                        color: accent,
                        size: 34,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.of(context).pop(
                _partialText.isNotEmpty ? _partialText : null,
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
