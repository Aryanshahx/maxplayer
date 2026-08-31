import 'package:flutter/material.dart';
import '../models/video_track.dart';
import '../state/video_library_state.dart';
import '../state/theme_state.dart';

/// v87: Redesigned modern card-based "Display settings" sheet.
class DisplaySettingsSheet extends StatelessWidget {
  final VideoLibraryState library;

  const DisplaySettingsSheet({super.key, required this.library});

  static const Color _surface = Color(0xFF14141c);

  static Future<void> show(BuildContext context, VideoLibraryState library) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DisplaySettingsSheet(library: library),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([library, themeState]),
      builder: (context, _) {
        final lib = library;
        final accent = themeState.accent;

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(Icons.tune, color: accent, size: 22),
                    const SizedBox(width: 8),
                    const Text(
                      'Display Settings',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Layout Mode Cards
                _sectionLabel('Layout & View Mode', accent),
                Row(
                  children: [
                    Expanded(
                      child: _layoutCard(
                        icon: Icons.grid_view_rounded,
                        title: 'Grid View',
                        subtitle: 'Visual cards',
                        selected: lib.viewMode == ViewMode.grid,
                        accent: accent,
                        onTap: () => lib.setViewMode(ViewMode.grid),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _layoutCard(
                        icon: Icons.view_list_rounded,
                        title: 'List View',
                        subtitle: 'Compact rows',
                        selected: lib.viewMode == ViewMode.list,
                        accent: accent,
                        onTap: () => lib.setViewMode(ViewMode.list),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Grouping & Sorting
                _sectionLabel('Sorting', accent),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                  ),
                  child: Column(
                    children: [
                      _sortTile(
                        icon: Icons.sort_by_alpha,
                        title: 'Name',
                        desc: lib.sortAscending ? 'A → Z' : 'Z → A',
                        selected: lib.sortMode == SortMode.name,
                        accent: accent,
                        onTap: () {
                          if (lib.sortMode == SortMode.name) {
                            lib.toggleSortDirection();
                          } else {
                            lib.setSort(SortMode.name, true);
                          }
                        },
                      ),
                      const Divider(height: 1, color: Colors.white10),
                      _sortTile(
                        icon: Icons.history,
                        title: 'Date Added',
                        desc: lib.sortAscending ? 'Oldest first' : 'Newest first',
                        selected: lib.sortMode == SortMode.date,
                        accent: accent,
                        onTap: () {
                          if (lib.sortMode == SortMode.date) {
                            lib.toggleSortDirection();
                          } else {
                            lib.setSort(SortMode.date, false);
                          }
                        },
                      ),
                      const Divider(height: 1, color: Colors.white10),
                      _sortTile(
                        icon: Icons.data_usage_rounded,
                        title: 'File Size',
                        desc: lib.sortAscending ? 'Smallest first' : 'Largest first',
                        selected: lib.sortMode == SortMode.size,
                        accent: accent,
                        onTap: () {
                          if (lib.sortMode == SortMode.size) {
                            lib.toggleSortDirection();
                          } else {
                            lib.setSort(SortMode.size, false);
                          }
                        },
                      ),
                      const Divider(height: 1, color: Colors.white10),
                      _sortTile(
                        icon: Icons.timer_outlined,
                        title: 'Video Length',
                        desc: lib.sortAscending ? 'Shortest first' : 'Longest first',
                        selected: lib.sortMode == SortMode.length,
                        accent: accent,
                        onTap: () {
                          if (lib.sortMode == SortMode.length) {
                            lib.toggleSortDirection();
                          } else {
                            lib.setSort(SortMode.length, false);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Grouping & Filtering
                _sectionLabel('Grouping & Actions', accent),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.collections_outlined, size: 20, color: accent),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Group videos by',
                              style: TextStyle(color: Colors.white, fontSize: 14),
                            ),
                          ),
                          DropdownButton<GroupMode>(
                            value: lib.groupMode,
                            dropdownColor: const Color(0xFF22222e),
                            underline: const SizedBox.shrink(),
                            style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.bold),
                            items: const [
                              DropdownMenuItem(value: GroupMode.none, child: Text('None')),
                              DropdownMenuItem(value: GroupMode.folder, child: Text('Folder')),
                              DropdownMenuItem(value: GroupMode.name, child: Text('Name (A-Z)')),
                            ],
                            onChanged: (m) => lib.setGroupMode(m ?? GroupMode.none),
                          ),
                        ],
                      ),
                      const Divider(height: 1, color: Colors.white10),
                      Row(
                        children: [
                          Icon(Icons.play_circle_outline, size: 20, color: accent),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Playback action',
                              style: TextStyle(color: Colors.white, fontSize: 14),
                            ),
                          ),
                          DropdownButton<PlaybackAction>(
                            value: lib.playbackAction,
                            dropdownColor: const Color(0xFF22222e),
                            underline: const SizedBox.shrink(),
                            style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.bold),
                            items: const [
                              DropdownMenuItem(value: PlaybackAction.all, child: Text('Queue All')),
                              DropdownMenuItem(value: PlaybackAction.single, child: Text('Single Video')),
                            ],
                            onChanged: (a) => lib.setPlaybackAction(a ?? PlaybackAction.all),
                          ),
                        ],
                      ),
                      const Divider(height: 1, color: Colors.white10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: Icon(Icons.favorite_border, size: 20, color: accent),
                        title: const Text('Show only favourites', style: TextStyle(color: Colors.white, fontSize: 14)),
                        value: lib.favoritesOnly,
                        activeThumbColor: accent,
                        onChanged: (v) => lib.setFavoritesOnly(v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Theme Palette
                _sectionLabel('Theme Accent Color', accent),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    for (final c in ThemeState.swatches)
                      GestureDetector(
                        onTap: () => themeState.setAccent(c),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: themeState.accent.toARGB32() == c.toARGB32()
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                            boxShadow: themeState.accent.toARGB32() == c.toARGB32()
                                ? [
                                    BoxShadow(
                                      color: c.withValues(alpha: 0.5),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                          child: themeState.accent.toARGB32() == c.toARGB32()
                              ? Icon(
                                  Icons.check,
                                  size: 18,
                                  color: c.computeLuminance() > 0.7 ? Colors.black87 : Colors.white,
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionLabel(String text, Color accent) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            color: accent,
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      );

  Widget _layoutCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool selected,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent : Colors.white.withValues(alpha: 0.07),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? accent : Colors.white60, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sortTile({
    required IconData icon,
    required String title,
    required String desc,
    required bool selected,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: Icon(icon, color: selected ? accent : Colors.white60, size: 20),
      title: Text(
        title,
        style: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontSize: 14,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              desc,
              style: TextStyle(
                color: selected ? accent : Colors.white38,
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 4),
              Icon(Icons.check, size: 14, color: accent),
            ],
          ],
        ),
      ),
    );
  }
}
