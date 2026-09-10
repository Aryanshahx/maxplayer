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
    final s = AppSettings.instance;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: const Text('Display Settings'),
        leading: const BackButton(),
      ),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(
          padding:
              const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 32),
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
                const SizedBox(width: 12),
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
                      const Divider(height: 1, indent: 16, endIndent: 16),
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
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _DropdownRow<bool>(
                    icon: Icons.play_circle_outline_rounded,
                    label: 'Playback action',
                    value: s.queueAll,
                    values: const [true, false],
                    labelOf: (v) => v ? 'Queue All' : 'Play Single',
                    onChanged: s.setQueueAll,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Icon(Icons.favorite_border_rounded,
                            color: AppColors.accent, size: 22),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text('Show only favourites',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14.5)),
                        ),
                        Switch(
                          value: s.onlyFavs,
                          activeThumbColor: AppColors.accent,
                          onChanged: s.setOnlyFavs,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const _SectionTitle('THEME ACCENT COLOR'),
            Wrap(
              spacing: 14,
              runSpacing: 12,
              children: [
                for (var i = 0; i < accentPalette.length; i++)
                  _AccentDot(
                    color: accentPalette[i],
                    selected: s.accentIndex == i,
                    onTap: () => s.setAccentIndex(i),
                  ),
              ],
            ),
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
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10, left: 4),
      child: Text(text,
          style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1)),
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
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: selected ? AppColors.accent : AppColors.border,
            width: selected ? 1.6 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
          child: Row(
            children: [
              Icon(icon,
                  color: selected ? AppColors.accent : AppColors.textSecondary,
                  size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: selected
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
            const SizedBox(width: 14),
            Expanded(
              child: Text(sortFieldLabel(field),
                  style: TextStyle(
                      color: selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 14.5,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400)),
            ),
            if (selected)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(sortDirectionLabel(field, s.sortAsc),
                        style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(width: 4),
                    Icon(Icons.check_rounded, color: AppColors.accent, size: 14),
                  ],
                ),
              )
            else
              Text(sortDirectionLabel(field, s.sortAsc),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accent, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14.5)),
          ),
          DropdownButton<T>(
            value: value,
            dropdownColor: AppColors.surfaceAlt,
            underline: const SizedBox.shrink(),
            iconEnabledColor: AppColors.textSecondary,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600),
            items: [
              for (final v in values)
                DropdownMenuItem(value: v, child: Text(labelOf(v))),
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

class _AccentDot extends StatelessWidget {
  const _AccentDot(
      {required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(
                      color: ThemeData.estimateBrightnessForColor(color) ==
                              Brightness.light
                          ? Colors.black
                          : Colors.white,
                      width: 3)
              : Border.all(color: Colors.transparent, width: 3),
          boxShadow: const [
            BoxShadow(
                color: Colors.black45, blurRadius: 6, offset: Offset(0, 2))
          ],
        ),
        child: selected
            ? Icon(Icons.check_rounded,
                color: ThemeData.estimateBrightnessForColor(color) ==
                        Brightness.light
                    ? Colors.black
                    : Colors.white,
                size: 22)
            : null,
      ),
    );
  }
}
