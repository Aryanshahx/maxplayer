import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Touch + remote activation for artwork and cards that used to be gesture-only.
/// The ring is painted over the child, so focus never changes layout geometry.
class RemoteTap extends StatefulWidget {
  const RemoteTap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onTapDown,
    this.onTapUp,
    this.onTapCancel,
    this.behavior,
    this.borderRadius,
    this.onFocusChange,
  });
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final GestureTapDownCallback? onTapDown;
  final GestureTapUpCallback? onTapUp;
  final GestureTapCancelCallback? onTapCancel;
  final HitTestBehavior? behavior;
  final BorderRadius? borderRadius;
  final ValueChanged<bool>? onFocusChange;
  @override
  State<RemoteTap> createState() => _RemoteTapState();
}

class _RemoteTapState extends State<RemoteTap> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      enabled: widget.onTap != null,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.contextMenu): _RemoteMenuIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
        _RemoteMenuIntent: CallbackAction<_RemoteMenuIntent>(
          onInvoke: (_) {
            widget.onLongPress?.call();
            return null;
          },
        ),
      },
      onFocusChange: (focused) {
        widget.onFocusChange?.call(focused);
        if (focused) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Scrollable.ensureVisible(
                context,
                alignment: .5,
                duration: const Duration(milliseconds: 180),
              );
            }
          });
        }
      },
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      child: Semantics(
        button: true,
        child: GestureDetector(
          behavior: widget.behavior ?? HitTestBehavior.opaque,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onTapDown: widget.onTapDown,
          onTapUp: widget.onTapUp,
          onTapCancel: widget.onTapCancel,
          child: Container(
            foregroundDecoration: _focused
                ? BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 3,
                    ),
                    borderRadius:
                        widget.borderRadius ?? BorderRadius.circular(12),
                  )
                : null,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _RemoteMenuIntent extends Intent {
  const _RemoteMenuIntent();
}
