import 'package:flutter/material.dart';

import '../screens/history_screen.dart' show timeAgo;
import '../theme.dart';
import '../utils/notifications.dart';

/// In-app notification centre, opened from the bell icon on the home
/// header. Matches the user-manual / about sheets (grab handle, hairline
/// cards, accent icons).
class NotificationsSheet extends StatelessWidget {
  final ScrollController? scrollController;

  const NotificationsSheet({super.key, this.scrollController});

  static Future<void> show(BuildContext context) {
    final store = NotificationsStore.instance;
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141c),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, controller) => ListenableBuilder(
          listenable: store,
          builder: (context, _) =>
              NotificationsSheet(scrollController: controller),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = NotificationsStore.instance;
    final items = store.items;
    final accent = AppColors.accent;

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            children: [
              // Grab handle.
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: const BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.all(Radius.circular(2)),
                  ),
                ),
              ),
              Row(
                children: [
                  Icon(Icons.notifications_none_outlined, color: accent),
                  const SizedBox(width: 10),
                  const Text(
                    'Notifications',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (items.isNotEmpty && store.unreadCount > 0)
                    TextButton(
                      onPressed: store.markAllRead,
                      child: Text('Mark all read',
                          style: TextStyle(color: accent, fontSize: 12.5)),
                    ),
                  if (items.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear all',
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Colors.white54, size: 20),
                      onPressed: store.clearAll,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 60, bottom: 60),
                  child: Column(
                    children: [
                      Icon(Icons.notifications_off_outlined,
                          size: 44, color: Colors.white24),
                      const SizedBox(height: 12),
                      const Text(
                        'No notifications yet',
                        style: TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                    ],
                  ),
                )
              else
                for (final n in items) _NotificationCard(item: n),
            ],
          ),
        ),
      ],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AppNotification item;
  const _NotificationCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accent;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: item.read
            ? AppColors.surface
            : AppColors.surfaceAlt.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: item.read ? AppColors.border : accent.withValues(alpha: 0.35),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          if (!item.read) {
            NotificationsStore.instance.markRead(item.id);
          }
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                notificationIconFor(item.iconKey),
                size: 20,
                color: accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: item.read
                                ? FontWeight.w500
                                : FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!item.read)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.body,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    timeAgo(item.ts),
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 10.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
