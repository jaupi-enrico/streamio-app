import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import 'tv_focusable.dart';

class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.show,
    required this.onTap,
    this.width = 120,
  });

  final Show show;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: show.poster != null
                    ? CachedNetworkImage(
                        imageUrl: show.poster!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const _PosterPlaceholder(),
                        errorWidget: (_, __, ___) => const _PosterPlaceholder(),
                      )
                    : const _PosterPlaceholder(),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              show.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E2430),
      child: const Icon(Icons.movie_outlined, color: Colors.white24),
    );
  }
}
