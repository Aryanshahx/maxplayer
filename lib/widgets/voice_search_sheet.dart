import 'dart:async';
import 'package:flutter/material.dart';

import '../services/native_bridge.dart';
import '../state/theme_state.dart';

/// v71: High-performance, resilient in-app voice search sheet.
/// Features real-time voice volume ripples, live partial transcription,
/// interactive retry on silence/no-match, direct search submission, and keyboard fallback.
class VoiceSearchSheet extends StatefulWidget {
  const VoiceSearchSheet({super.key});

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
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
  late final TextEditingController _textCtrl;
  String _status = 'Listening… speak now';
  double _rms = 0.0;
  bool _isListening = false;
  bool _isEditing = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _startListening();
  }

  void _startListening() {
    if (_finished) return;
    setState(() {
      _isListening = true;
      _status = 'Listening… speak now';
      _rms = 0.0;
    });
    if (!_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    }

    NativeBridge.configureCallbacks(
      onVoiceState: (state) {
        if (!mounted || _finished) return;
        setState(() {
          if (state == 'speaking') {
            _status = 'Listening…';
          } else if (state == 'processing') {
            _status = 'Processing…';
          }
        });
      },
      onVoiceRms: (rms) {
        if (!mounted || _finished || !_isListening) return;
        setState(() => _rms = rms.clamp(0.0, 10.0));
      },
      onVoicePartial: (text) {
        if (!mounted || _finished) return;
        setState(() {
          _textCtrl.text = text;
        });
      },
      onVoiceResult: (result) {
        if (!mounted || _finished) return;
        final clean = result.trim();
        if (clean.isNotEmpty) {
          _finished = true;
          _textCtrl.text = clean;
          Navigator.of(context).pop(clean);
        } else if (_textCtrl.text.trim().isNotEmpty) {
          _finished = true;
          Navigator.of(context).pop(_textCtrl.text.trim());
        } else {
          setState(() {
            _isListening = false;
            _status = "Didn't catch that. Tap microphone to try again.";
            _rms = 0.0;
          });
        }
      },
      onVoiceError: (err) {
        if (!mounted || _finished) return;
        setState(() {
          _isListening = false;
          _rms = 0.0;
          if (_textCtrl.text.trim().isNotEmpty) {
            _status = 'Tap "Search" or tap mic to speak again';
          } else {
            _status = "Didn't catch that. Tap microphone to try again.";
          }
        });
      },
    );

    unawaited(NativeBridge.startVoiceSearch());
  }

  void _stopListening() {
    setState(() {
      _isListening = false;
      _rms = 0.0;
      _status = 'Tap microphone to speak';
    });
    unawaited(NativeBridge.stopVoiceSearch());
  }

  void _toggleMic() {
    if (_isListening) {
      if (_textCtrl.text.trim().isNotEmpty) {
        _finished = true;
        Navigator.of(context).pop(_textCtrl.text.trim());
      } else {
        _stopListening();
      }
    } else {
      _startListening();
    }
  }

  void _submit() {
    final query = _textCtrl.text.trim();
    if (query.isNotEmpty) {
      _finished = true;
      Navigator.of(context).pop(query);
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _textCtrl.dispose();
    unawaited(NativeBridge.stopVoiceSearch());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    final scale = _isListening
        ? 1.0 + (_rms / 10.0) * 0.35 + (_pulseCtrl.value * 0.08)
        : 1.0;
    final hasText = _textCtrl.text.trim().isNotEmpty;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
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
            const SizedBox(height: 20),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 20),
            if (_isEditing)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textCtrl,
                        autofocus: true,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Type or edit search query…',
                          hintStyle: TextStyle(color: Colors.white38),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.check_circle, color: accent),
                      onPressed: _submit,
                    ),
                  ],
                ),
              )
            else if (hasText)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '"${_textCtrl.text}"',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.white54, size: 18),
                      tooltip: 'Edit text',
                      onPressed: () => setState(() => _isEditing = true),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _toggleMic,
              child: AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, _) {
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isListening
                            ? accent.withValues(alpha: 0.22)
                            : Colors.white.withValues(alpha: 0.08),
                        border: Border.all(
                          color: _isListening
                              ? accent.withValues(alpha: 0.8)
                              : Colors.white24,
                          width: 2.8,
                        ),
                        boxShadow: _isListening
                            ? [
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.4),
                                  blurRadius: 22 * scale,
                                  spreadRadius: 6 * scale,
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: _isListening ? accent : Colors.white70,
                        size: 38,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.keyboard_outlined, size: 18),
                  label: const Text('Keyboard'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white60,
                  ),
                  onPressed: () => setState(() => _isEditing = true),
                ),
                if (hasText) ...[
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    onPressed: _submit,
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text(
                      'Search',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                const SizedBox(width: 16),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
