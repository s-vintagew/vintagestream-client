import 'package:flutter/material.dart';
import 'package:vs_core/vs_core.dart';
import 'package:vs_ui/vs_ui.dart';

class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.item,
    required this.posterUrl,
    required this.onTap,
    this.showKind = false,
  });

  final MediaItem item;
  final String posterUrl;
  final VoidCallback onTap;
  final bool showKind;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: VsTheme.card,
              child: posterUrl.isEmpty
                  ? const Center(child: Icon(Icons.movie_outlined, color: VsTheme.muted))
                  : Image.network(
                      posterUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Center(
                        child: Icon(Icons.broken_image_outlined, color: VsTheme.muted),
                      ),
                    ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC000000)],
                ),
              ),
            ),
            if (showKind)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.isShow ? 'SERIES' : 'MOVIE',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFFE08A),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
