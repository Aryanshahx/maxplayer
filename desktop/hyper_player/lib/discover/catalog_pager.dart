import 'package:flutter/foundation.dart';
import 'tmdb.dart';

typedef CatalogLoader = Future<TmdbPage> Function(int page, bool force);

/// Appending, deduplicating category data. Failed pages retain earlier results
/// and the same retry page; a late empty response exhausts without wiping cards.
class CatalogPager extends ChangeNotifier {
  final CatalogLoader loader;
  CatalogPager(this.loader);
  final List<TmdbMovie> items = [];
  final Set<String> _seen = {};
  bool loading = false, failed = false, disposed = false;
  int page = 0, totalPages = 1;
  bool get hasMore => page < totalPages;
  Future<void> load({bool refresh = false, bool force = false}) async {
    if (loading || disposed || (!refresh && !hasMore)) return;
    final next = refresh ? 1 : page + 1;
    loading = true;
    failed = false;
    notifyListeners();
    try {
      final result = await loader(next, force);
      if (disposed) return;
      if (result.items.isEmpty && next == 1) {
        failed = true;
        return;
      }
      if (refresh) {
        items.clear();
        _seen.clear();
      }
      if (result.items.isEmpty) {
        totalPages = page;
        return;
      }
      for (final movie in result.items) {
        if (_seen.add('${movie.kind}:${movie.id}')) items.add(movie);
      }
      page = next;
      totalPages = result.totalPages.clamp(page, 500);
    } catch (_) {
      if (!disposed) failed = true;
    } finally {
      if (!disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
