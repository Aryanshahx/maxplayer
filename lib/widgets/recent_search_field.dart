import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/recent_searches.dart';

/// Search field with compact, in-layout history. No overlay, popup or follower.
/// Fixed-height headers pass showHistory:false and place RecentSearchHistory
/// in their scrollable body, so suggestions never cover nearby content.
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
    this.showHistory = true,
  });
  final String scope;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final TextStyle? style;
  final InputDecoration decoration;
  final ValueChanged<String>? onChanged, onSubmitted;
  final bool autofocus, showHistory;
  @override
  State<RecentSearchField> createState() => _RecentSearchFieldState();
}

class _RecentSearchFieldState extends State<RecentSearchField> {
  final ownController = TextEditingController();
  final ownFocus = FocusNode();
  TextEditingController get text => widget.controller ?? ownController;
  FocusNode get focus => widget.focusNode ?? ownFocus;
  Timer? timer;
  String lastQuery = '';
  bool pending = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    lastQuery = text.text;
    text.addListener(_controllerChanged);
    focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(RecentSearchField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? ownController).removeListener(_controllerChanged);
      lastQuery = text.text;
      text.addListener(_controllerChanged);
    }
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? ownFocus).removeListener(_focusChanged);
      focus.addListener(_focusChanged);
    }
  }

  void _controllerChanged() {
    if (lastQuery == text.text) return;
    lastQuery = text.text;
    pending = true;
    generation = RecentSearches.generation(widget.scope);
    timer?.cancel();
    timer = Timer(const Duration(seconds: 1), _remember);
  }

  void _focusChanged() {
    if (!focus.hasFocus) {
      timer?.cancel();
      _remember();
    }
  }

  void _remember() {
    if (!pending) return;
    pending = false;
    unawaited(
      RecentSearches.record(
        widget.scope,
        lastQuery,
        generation,
      ).catchError((Object _) {}),
    );
  }

  void _choose(String value) {
    text.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    widget.onChanged?.call(value);
    timer?.cancel();
    _remember();
  }

  @override
  void dispose() {
    timer?.cancel();
    text.removeListener(_controllerChanged);
    focus.removeListener(_focusChanged);
    _remember();
    ownController.dispose();
    ownFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: text,
      focusNode: focus,
      autofocus: widget.autofocus,
      style: widget.style,
      decoration: widget.decoration,
      onChanged: widget.onChanged,
      onSubmitted: (value) {
        timer?.cancel();
        _remember();
        widget.onSubmitted?.call(value);
      },
    );
    if (!widget.showHistory) return field;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field,
        RecentSearchHistory(
          scope: widget.scope,
          controller: text,
          onSelected: _choose,
        ),
      ],
    );
  }
}

class RecentSearchHistory extends StatefulWidget {
  const RecentSearchHistory({
    super.key,
    required this.scope,
    required this.controller,
    required this.onSelected,
  });
  final String scope;
  final TextEditingController controller;
  final ValueChanged<String> onSelected;
  @override
  State<RecentSearchHistory> createState() => _RecentSearchHistoryState();
}

class _RecentSearchHistoryState extends State<RecentSearchHistory> {
  List<String> recent = [];
  int request = 0;
  @override
  void initState() {
    super.initState();
    RecentSearches.revision.addListener(_reload);
    widget.controller.addListener(_queryChanged);
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final id = ++request;
    try {
      final values = await RecentSearches.load(widget.scope);
      if (mounted && id == request) setState(() => recent = values);
    } catch (_) {
      /* history is optional */
    }
  }

  void _queryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(RecentSearchHistory old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_queryChanged);
      widget.controller.addListener(_queryChanged);
    }
    if (old.scope != widget.scope) unawaited(_reload());
  }

  @override
  void dispose() {
    request++;
    RecentSearches.revision.removeListener(_reload);
    widget.controller.removeListener(_queryChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (recent.isEmpty || widget.controller.text.trim().isNotEmpty) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Recent searches',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Clear recent searches',
                visualDensity: VisualDensity.compact,
                iconSize: 19,
                icon: const Icon(Icons.close),
                onPressed: () async {
                  setState(() => recent = []);
                  await RecentSearches.clear(widget.scope);
                },
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, bounds) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final value in recent.take(3))
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: bounds.maxWidth.clamp(120, 280),
                        ),
                        // Colours are set explicitly: the global chip theme
                        // prefers the accent for labels, which made these
                        // chips render near-white text on a near-white fill.
                        child: ActionChip(
                          avatar: Icon(
                            Icons.north_west,
                            size: 15,
                            color: scheme.onSurfaceVariant,
                          ),
                          label: Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          backgroundColor: scheme.surfaceContainerLow,
                          side: BorderSide(color: scheme.outlineVariant),
                          shape: const StadiumBorder(),
                          onPressed: () => widget.onSelected(value),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
