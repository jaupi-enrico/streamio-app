import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../shared/widgets/poster_card.dart';

/// Mirrors home.js's `.row` / `renderRow()`.
class CategoryRail extends StatelessWidget {
  const CategoryRail({super.key, required this.category, required this.onTap});

  final Category category;
  final void Function(Show show) onTap;

  @override
  Widget build(BuildContext context) {
    final shows = category.list.whereType<Show>().toList();
    if (shows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(category.name, style: Theme.of(context).textTheme.headlineSmall),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: shows.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) =>
                  PosterCard(show: shows[i], onTap: () => onTap(shows[i])),
            ),
          ),
        ],
      ),
    );
  }
}
