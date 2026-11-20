import 'package:flutter/material.dart';

/// Shared desktop adapter for the actual Android cinematic widgets.
/// URLs originate from TMDB helpers; finite decode width bounds GPU memory.
class TmdbImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  const TmdbImage({super.key, required this.url, this.fit = BoxFit.cover});
  @override
  Widget build(BuildContext context) {
    const fallback = ColoredBox(
        color: Color(0xff1a1a26),
        child: Center(
            child:
                Icon(Icons.movie_outlined, color: Colors.white24, size: 42)));
    if (url.isEmpty) return fallback;
    return Image.network(url,
        fit: fit,
        cacheWidth: 1280,
        errorBuilder: (_, error, stack) => fallback,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const ColoredBox(
                color: Color(0xff1a1a26),
                child: Center(
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white24)))));
  }
}
