import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/recent_searches.dart';

/// A normal search TextField plus a maximum-three local history dropdown.
/// Supports existing controllers/callbacks. No queries are sent to analytics.
class RecentSearchField extends StatefulWidget {
  const RecentSearchField({
    super.key,
    required this.scope,
    this.controller,
    this.focusNode,
    this.style,
    this.decoration = const InputDecoration(),
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });
  final String scope;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final TextStyle? style;
  final InputDecoration decoration;
  final ValueChanged<String>? onChanged, onSubmitted;
  final bool autofocus;
  @override
  State<RecentSearchField> createState() => _RecentSearchFieldState();
}

class _RecentSearchFieldState extends State<RecentSearchField> {
  late final ownController = TextEditingController();
  late final ownFocus = FocusNode();
  TextEditingController get text => widget.controller ?? ownController;
  FocusNode get focus => widget.focusNode ?? ownFocus;
  final portal = OverlayPortalController();
  final link = LayerLink();
  final fieldKey = GlobalKey();
  List<String> recent = [];
  Timer? timer;
  bool ready = false, pending = false;
  String lastQuery = '';
  void _controllerChanged() {
    if (lastQuery == text.text) return; // Caret changes are not new searches.
    lastQuery = text.text;
    pending = true;
    if (mounted) {
      setState(() {});
      _visibility();
    }
  }

  Future<void> writes = Future<void>.value();
  @override
  void initState() {
    super.initState();
    lastQuery = text.text;
    text.addListener(_controllerChanged);
    focus.addListener(_focusChanged);
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final values = await RecentSearches.load(widget.scope);
      if (mounted) {
        setState(() {
          recent = values;
          ready = true;
        });
        _visibility();
      }
    } catch (_) {
      if (mounted) ready = true;
    }
  }

  @override
  void didUpdateWidget(RecentSearchField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? ownController).removeListener(_controllerChanged);
      text.addListener(_controllerChanged);
      lastQuery = text.text;
    }
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? ownFocus).removeListener(_focusChanged);
      focus.addListener(_focusChanged);
    }
  }

  List<String> get suggestions => recent
      .where(
        (v) =>
            text.text.trim().isEmpty ||
            (v.toLowerCase().contains(text.text.trim().toLowerCase()) &&
                v.toLowerCase() != text.text.trim().toLowerCase()),
      )
      .toList();
  void _visibility() {
    if (!mounted) return;
    if (focus.hasFocus && suggestions.isNotEmpty) {
      portal.show();
    } else {
      portal.hide();
    }
  }

  void _focusChanged() {
    if (!focus.hasFocus) {
      timer?.cancel();
      _remember();
    }
    _visibility();
  }

  void _persist() {
    final snapshot = List<String>.of(recent), scope = widget.scope;
    writes = writes
        .catchError((Object _) {})
        .then((_) => RecentSearches.save(scope, snapshot))
        .catchError((Object _) {});
  }

  void _remember() {
    if (!ready || !pending) return;
    pending = false;
    recent = RecentSearches.prepend(recent, lastQuery);
    _persist();
  }

  void _change(String value) {
    widget.onChanged?.call(value);
    timer?.cancel();
    timer = Timer(const Duration(seconds: 1), () {
      _remember();
      if (mounted) {
        setState(() {});
        _visibility();
      }
    });
    setState(() {});
    _visibility();
  }

  void _choose(String value) {
    timer?.cancel();
    text.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    widget.onChanged?.call(value);
    _remember();
    portal.hide();
    setState(() {});
  }

  @override
  void dispose() {
    timer?.cancel();
    text.removeListener(_controllerChanged);
    focus.removeListener(_focusChanged);
    // Capture the final query if the screen is popped before its debounce.
    _remember();
    ownFocus.dispose();
    ownController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CompositedTransformTarget(
    link: link,
    child: OverlayPortal(
      controller: portal,
      overlayChildBuilder: (context) {
        final box = fieldKey.currentContext?.findRenderObject() as RenderBox?;
        final width = box?.size.width ?? 280;
        return Positioned(
          left: 0,
          top: 0,
          width: width,
          child: CompositedTransformFollower(
            link: link,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            showWhenUnlinked: false,
            child: TextFieldTapRegion(
              child: Material(
                elevation: 8,
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const SizedBox(width: 12),
                            const Expanded(child: Text('Recent searches')),
                            IconButton(
                              tooltip: 'Clear recent searches',
                              icon: const Icon(Icons.delete_sweep_outlined),
                              onPressed: () {
                                timer?.cancel();
                                setState(() {
                                  recent = [];
                                  pending = false;
                                });
                                _persist();
                                portal.hide();
                              },
                            ),
                          ],
                        ),
                        for (final value in suggestions)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.history, size: 18),
                            title: Text(
                              value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _choose(value),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: TextField(
        key: fieldKey,
        controller: text,
        focusNode: focus,
        autofocus: widget.autofocus,
        style: widget.style,
        decoration: widget.decoration,
        onChanged: _change,
        onTapOutside: (_) => focus.unfocus(),
        onSubmitted: (value) {
          timer?.cancel();
          _remember();
          portal.hide();
          widget.onSubmitted?.call(value);
        },
      ),
    ),
  );
}
