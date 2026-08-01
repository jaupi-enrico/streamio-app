import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../shared/widgets/async_states.dart';
import '../../shared/widgets/provider_chips.dart';
import '../../state/core_providers.dart';
import 'home_providers.dart';
import 'widgets/category_rail.dart';
import 'widgets/continue_watching_rail.dart';
import 'widgets/hero_carousel.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  void _openDetails(BuildContext context, Show show, String activeProvider) {
    final provider = show.providerName ?? activeProvider;
    context.push('/details/$provider/${Uri.encodeComponent(show.id)}');
  }

  /// Continue Watching goes straight to the player at the stored position,
  /// skipping the details page — the same shortcut `home.js` takes.
  void _resume(BuildContext context, HistoryEntry entry, String title) {
    final id = entry.episodeId ?? entry.showId;
    final query = {
      'contentType': entry.episodeId != null ? 'episode' : 'movie',
      'showId': entry.showId,
      'title': title,
      if (entry.episodeLabel != null) 'episodeLabel': entry.episodeLabel!,
      't': '${entry.progressSeconds}',
    };
    final search = Uri(queryParameters: query).query;
    context.push('/watch/${entry.provider}/${Uri.encodeComponent(id)}?$search');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(homeCategoriesProvider);
    final continueAsync = ref.watch(continueWatchingProvider);
    final activeProvider = ref.watch(activeProviderNameProvider);

    Future<void> refresh() async {
      ref.invalidate(homeCategoriesProvider);
      ref.invalidate(continueWatchingProvider);
      await ref.read(homeCategoriesProvider.future);
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: refresh,
          child: categoriesAsync.when(
            loading: () => const LoadingState(),
            error: (error, _) => ErrorState(error: error, onRetry: refresh),
            data: (categories) {
              if (categories.isEmpty) {
                return EmptyState(
                  message: 'This provider returned nothing to show.',
                  icon: Icons.movie_filter_outlined,
                  action: FilledButton.tonal(
                    onPressed: () => context.push('/providers'),
                    child: const Text('Try another provider'),
                  ),
                );
              }

              final featured = categories
                  .firstWhere((c) => c.name == Category.featured,
                      orElse: () => categories.first)
                  .list
                  .whereType<Show>()
                  .toList();

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: HeroCarousel(
                      items: featured,
                      onTap: (show) => _openDetails(context, show, activeProvider),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  const SliverToBoxAdapter(child: ProviderChips()),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  SliverToBoxAdapter(
                    child: continueAsync.maybeWhen(
                      data: (entries) => ContinueWatchingRail(
                        entries: entries,
                        onResume: (entry, title) => _resume(context, entry, title),
                      ),
                      orElse: () => const SizedBox.shrink(),
                    ),
                  ),
                  SliverList.list(
                    children: categories
                        .map((category) => CategoryRail(
                              category: category,
                              onTap: (show) =>
                                  _openDetails(context, show, activeProvider),
                            ))
                        .toList(),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
