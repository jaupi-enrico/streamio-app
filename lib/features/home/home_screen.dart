import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../shared/widgets/async_states.dart';
import '../../shared/widgets/provider_picker.dart';
import '../../state/core_providers.dart';
import '../watch/now_casting_button.dart';
import 'home_providers.dart';
import 'widgets/category_rail.dart';
import 'widgets/continue_watching_rail.dart';
import 'widgets/hero_carousel.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// Routes on the provider the listing was fetched with, never on
  /// `show.providerName`. That field is whatever the provider calls itself
  /// (`Provider.getName()` in `../web/core/models/Provider.ts`), and only a
  /// server new enough to have had those names aligned with the registry slugs
  /// sends something `?provider=` will accept: an older install answers with
  /// the site's own display name, and labels a language mirror's items with
  /// the name of the provider it was mirrored from.
  /// Since the app has no way to tell which kind of server it is talking to,
  /// the field is never routed on. `home.js` uses the slug for the same reason
  /// and renders `providerName` only as a badge.
  void _openDetails(BuildContext context, Show show, String activeProvider) {
    context.push('/details/$activeProvider/${Uri.encodeComponent(show.id)}');
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
        child: Stack(
          children: [
            _body(context, ref, categoriesAsync, continueAsync, activeProvider,
                refresh),
            // Top right, above the hero: the way back to a cast that is
            // already running. It draws nothing unless a receiver is actually
            // playing something, so the corner is empty the rest of the time
            // — see [NowCastingButton].
            const Positioned(
              top: 8,
              right: 12,
              child: NowCastingButton(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Category>> categoriesAsync,
    AsyncValue<List<HistoryEntry>> continueAsync,
    String activeProvider,
    Future<void> Function() refresh,
  ) {
    return RefreshIndicator(
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
              const SliverToBoxAdapter(child: ProviderPicker()),
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
    );
  }
}
