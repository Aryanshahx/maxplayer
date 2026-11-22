import '../utils/app_language.dart';

import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/settings.dart';
import '../utils/sort.dart';

/// Display Settings — layout & view mode, sorting, grouping & actions,
/// theme accent wheel. Design mirrors the reference screenshot.
class DisplaySettingsScreen extends StatelessWidget {
  const DisplaySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final s = AppSettings.instance;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: LText('Display Settings'),
        leading: BackButton(),
      ),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(
          padding: EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 32),
          children: [
            const _SectionTitle('LAYOUT & VIEW MODE'),
            Row(
              children: [
                Expanded(
                  child: _ModeCard(
                    icon: Icons.grid_view_rounded,
                    title: 'Grid View',
                    subtitle: 'Visual cards',
                    selected: s.viewMode == ViewMode.grid,
                    onTap: () => s.setViewMode(ViewMode.grid),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _ModeCard(
                    icon: Icons.view_list_rounded,
                    title: 'List View',
                    subtitle: 'Compact rows',
                    selected: s.viewMode == ViewMode.list,
                    onTap: () => s.setViewMode(ViewMode.list),
                  ),
                ),
              ],
            ),
            const _SectionTitle('SORTING'),
            Card(
              child: Column(
                children: [
                  for (final f in SortField.values) ...[
                    _SortRow(field: f),
                    if (f != SortField.values.last)
                      Divider(height: 1, indent: 16, endIndent: 16),
                  ],
                ],
              ),
            ),
            const _SectionTitle('GROUPING & ACTIONS'),
            Card(
              child: Column(
                children: [
                  _DropdownRow<GroupBy>(
                    icon: Icons.photo_library_outlined,
                    label: 'Group videos by',
                    value: s.groupBy,
                    values: GroupBy.values,
                    labelOf: groupByLabel,
                    onChanged: s.setGroupBy,
                  ),
                  Divider(height: 1, indent: 16, endIndent: 16),
                  _DropdownRow<bool>(
                    icon: Icons.play_circle_outline_rounded,
                    label: 'Playback action',
                    value: s.queueAll,
                    values: [true, false],
                    labelOf: (v) => v ? 'Queue All' : 'Play Single',
                    onChanged: s.setQueueAll,
                  ),
                  Divider(height: 1, indent: 16, endIndent: 16),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.favorite_border_rounded,
                          color: AppColors.accent,
                          size: 22,
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: LText(
                            'Show only favourites',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        Switch(value: s.onlyFavs, onChanged: s.setOnlyFavs),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const _SectionTitle('THEME ACCENT COLOR'),
            const _CustomAccentSliders(),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: 22, bottom: 10, left: 4),
      child: LText(
        text,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? AppColors.accent : AppColors.border,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 22, horizontal: 16),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected ? AppColors.accent : AppColors.textSecondary,
                size: 26,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LText(
                      title,
                      style: TextStyle(
                        color: selected
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    LText(
                      subtitle,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortRow extends StatelessWidget {
  const _SortRow({required this.field});

  final SortField field;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final s = AppSettings.instance;
    final selected = s.sortField == field;
    return InkWell(
      onTap: () {
        if (selected) {
          s.setSortAsc(!s.sortAsc); // tap again → flip direction
        } else {
          s.setSortField(field);
        }
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              switch (field) {
                SortField.name => Icons.sort_by_alpha_rounded,
                SortField.dateAdded => Icons.history_rounded,
                SortField.size => Icons.donut_small_rounded,
                SortField.length => Icons.timer_outlined,
              },
              color: selected ? AppColors.accent : AppColors.textSecondary,
              size: 21,
            ),
            SizedBox(width: 14),
            Expanded(
              child: LText(
                sortFieldLabel(field),
                style: TextStyle(
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontSize: 14.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (selected)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LText(
                      sortDirectionLabel(field, s.sortAsc),
                      style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.check_rounded,
                      color: AppColors.accent,
                      size: 14,
                    ),
                  ],
                ),
              )
            else
              LText(
                sortDirectionLabel(field, s.sortAsc),
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}

class _DropdownRow<T> extends StatelessWidget {
  const _DropdownRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final void Function(T) onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accent, size: 22),
          SizedBox(width: 14),
          Expanded(
            child: LText(
              label,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
            ),
          ),
          DropdownButton<T>(
            value: value,
            dropdownColor: AppColors.surfaceAlt,
            underline: SizedBox.shrink(),
            iconEnabledColor: AppColors.textSecondary,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
            items: [
              for (final v in values)
                DropdownMenuItem(value: v, child: LText(labelOf(v))),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

/// RGB channels cover the full opaque sRGB colour range, including greys.
class _CustomAccentSliders extends StatelessWidget {
  const _CustomAccentSliders();
  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final c = s.accentColor;
    final channels = [c.r, c.g, c.b];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LText('Custom colour — slide Red, Green and Blue'),
        const SizedBox(height: 8),
        Container(
          height: 30,
          color: c,
          alignment: Alignment.center,
          child: Text(
            '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
            style: TextStyle(color: contrastForeground(c)),
          ),
        ),
        for (var i = 0; i < 3; i++)
          Row(
            children: [
              SizedBox(width: 52, child: LText(['Red', 'Green', 'Blue'][i])),
              Expanded(
                child: Slider(
                  key: ValueKey('accent-channel-$i'),
                  value: channels[i] * 255,
                  max: 255,
                  divisions: 255,
                  label: (channels[i] * 255).round().toString(),
                  semanticFormatterCallback: (v) =>
                      '${['Red', 'Green', 'Blue'][i]} ${v.round()}',
                  onChanged: (v) async {
                    final rgb = channels.map((v) => (v * 255).round()).toList();
                    rgb[i] = v.round();
                    try {
                      await s.setCustomAccent(
                        Color.fromARGB(255, rgb[0], rgb[1], rgb[2]),
                      );
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not save accent colour. Please try again.',
                            ),
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        LText(
          'Text contrast adapts automatically. Very dark or pale accents adjust for readability.',
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
