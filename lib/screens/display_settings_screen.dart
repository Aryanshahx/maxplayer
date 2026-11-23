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

/// Own listener is intentional: this const child must update its slider/hex
/// even when the parent reuses the same widget instance.
class _CustomAccentSliders extends StatelessWidget {
  const _CustomAccentSliders();
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppSettings.instance,
    builder: (context, _) {
      final s = AppSettings.instance;
      final c = s.accentColor;
      final applied = adaptiveAccent(c, Theme.of(context).brightness);
      final hue = HSVColor.fromColor(c).hue;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LText('Theme colour'),
          const SizedBox(height: 6),
          const LText(
            'White is the default look. Your five most recent colours stay '
            'below the wheel for quick switching.',
            style: TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                key: const ValueKey('theme-colour-preview'),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SelectableText(
                  accentHex(c),
                  key: const ValueKey('theme-colour-hex'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Stack(
            alignment: Alignment.center,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: SizedBox(
                  height: 6,
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                      gradient: LinearGradient(
                        colors: [
                          Colors.red,
                          Colors.yellow,
                          Colors.green,
                          Colors.cyan,
                          Colors.blue,
                          Colors.purple,
                          Colors.red,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Slider(
                key: const ValueKey('theme-colour-slider'),
                value: hue,
                max: 360,
                divisions: 360,
                activeColor: Colors.transparent,
                inactiveColor: Colors.transparent,
                thumbColor: applied,
                label: accentHex(c),
                semanticFormatterCallback: (v) =>
                    'Theme colour ${accentHex(colourFromHue(v))}',
                onChanged: (v) async {
                  try {
                    await s.setCustomAccent(colourFromHue(v));
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
            ],
          ),
          Text(
            'Theme accent: ${accentHex(applied)}',
            key: const ValueKey('theme-applied-hex'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          const LText(
            'Slide to choose a colour. The theme adjusts contrast for readability.',
          ),
          const SizedBox(height: 14),
          const LText(
            'RECENT COLOURS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (index, preset) in s.accentPresets.indexed)
                _PresetSwatch(
                  key: ValueKey(
                    index == 0 ? 'accent-preset-white' : 'accent-preset-$index',
                  ),
                  colour: preset,
                  selected: index == 0
                      ? s.usingWhitePreset
                      : s.customAccent?.toARGB32() == preset.toARGB32(),
                  isWhitePreset: index == 0,
                  onTap: () async {
                    try {
                      if (index == 0) {
                        await s.useWhitePreset();
                      } else {
                        await s.setCustomAccent(preset);
                      }
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
            ],
          ),
          const SizedBox(height: 16),
        ],
      );
    },
  );
}

/// One tappable preset dot. Index 0 is the white "return to default" swatch,
/// which is always present even when no custom colours were picked yet.
class _PresetSwatch extends StatelessWidget {
  const _PresetSwatch({
    super.key,
    required this.colour,
    required this.selected,
    required this.isWhitePreset,
    required this.onTap,
  });

  final Color colour;
  final bool selected;
  final bool isWhitePreset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ring = selected ? scheme.primary : scheme.outlineVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: isWhitePreset
          ? 'White theme preset (default) ${accentHex(colour)}'
          : 'Recent theme colour ${accentHex(colour)}',
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colour,
            shape: BoxShape.circle,
            border: Border.all(color: ring, width: selected ? 3 : 1.5),
          ),
          child: selected
              ? Icon(
                  Icons.check,
                  size: 18,
                  color: contrastForeground(colour),
                )
              : null,
        ),
      ),
    );
  }
}

String accentHex(Color colour) =>
    '#${colour.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

Color colourFromHue(double hue) =>
    HSVColor.fromAHSV(1, hue.clamp(0, 360), .8, .9).toColor();
