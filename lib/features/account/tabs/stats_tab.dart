import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/async_states.dart';
import '../../../shared/widgets/tv_focusable.dart';
import '../account_providers.dart';

/// Account → Stats: your viewing numbers and the badges they earn.
///
/// Mirrors the web account page's Stats tab, down to the card order, so the
/// two clients read the same. Both endpoints are private to the account — the
/// router takes the user id from the token — so nothing here is anyone else's.
class StatsTab extends ConsumerWidget {
  const StatsTab({super.key});

  /// Category ids in the order the badge grid shows them, with their labels.
  /// A category the server adds later is unknown here rather than broken: it
  /// renders last, under its raw id.
  static const _categories = <String, String>{
    'time': 'Watch time',
    'episodes': 'Episodes',
    'movies': 'Movies',
    'shows': 'Shows',
    'streak': 'Streaks',
    'library': 'Library',
    'ratings': 'Ratings',
    'social': 'Social',
    'explorer': 'Discovery',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(accountStatsProvider);

    Future<void> refresh() async {
      ref.invalidate(accountStatsProvider);
      await ref.read(accountStatsProvider.future);
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: async.when(
        loading: () => const LoadingState(),
        error: (error, _) {
          // A server predating the feature 404s here. That isn't a failure
          // worth an error message and a Retry button — retrying can only 404
          // again — so it gets its own copy naming the actual situation.
          if (_isNotFound(error)) {
            return const EmptyState(
              message: 'Your server doesn\'t have stats yet. Update it to see '
                  'your watch stats and badges.',
              icon: Icons.insights_outlined,
            );
          }
          return ErrorState(error: error, onRetry: refresh);
        },
        data: (data) => _StatsBody(data: data, categories: _categories),
      ),
    );
  }

  /// Riverpod 3 wraps whatever a provider threw, so the exception worth
  /// inspecting is one level down — the same unwrap [ErrorState.messageFor]
  /// does.
  static bool _isNotFound(Object error) {
    if (error is ProviderException) return _isNotFound(error.exception);
    return error is ApiException && error.isNotFound;
  }
}

class _StatsBody extends StatelessWidget {
  const _StatsBody({required this.data, required this.categories});

  final AccountStats data;
  final Map<String, String> categories;

  @override
  Widget build(BuildContext context) {
    final stats = data.stats;
    final theme = Theme.of(context);

    final cards = <_Stat>[
      _Stat('Watch time', formatWatchTime(stats.totalWatchSeconds)),
      _Stat('Episodes finished', '${stats.episodesCompleted}'),
      _Stat('Movies finished', '${stats.moviesCompleted}'),
      _Stat('Shows finished', '${stats.showsCompleted}',
          hint: 'Nothing left unfinished'),
      _Stat('Titles started', '${stats.titlesStarted}'),
      _Stat('Still watching', '${stats.episodesInProgress}'),
      _Stat('Current streak', '${stats.currentStreakDays}d',
          hint: 'Best: ${stats.longestStreakDays}d'),
      _Stat('Active days', '${stats.activeDays}'),
      _Stat('In watchlist', '${stats.watchlistCount}'),
      _Stat('Favorites', '${stats.favoritesCount}'),
      _Stat('Titles rated', '${stats.ratingsCount}',
          hint: stats.averageRating == null
              ? 'No ratings yet'
              : 'Avg ${stats.averageRating!.toStringAsFixed(1)}/10'),
      _Stat('Providers used', '${stats.providersUsed}',
          hint: stats.topProvider == null ? null : 'Most: ${stats.topProvider}'),
      _Stat('Followers', '${stats.followersCount}',
          hint: 'Following ${stats.followingCount}'),
      _Stat('Shares sent', '${stats.sharesSent}',
          hint: '${stats.reactionsReceived} reactions received'),
    ];

    final earned = data.badges.where((b) => b.earned).length;
    final grouped = _group(data.badges);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(_summaryLine(stats),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            // Fixed-width cards in a Wrap rather than a shrink-wrapped
            // GridView: no intrinsic-height pass, and it adapts from a phone
            // to a ten-foot layout without a breakpoint table.
            const spacing = 10.0;
            final columns = (constraints.maxWidth ~/ 180).clamp(2, 6);
            final width =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final card in cards)
                  SizedBox(width: width, child: _StatCard(stat: card)),
              ],
            );
          },
        ),
        const SizedBox(height: 28),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('Badges', style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            Text('$earned of ${data.badges.length} earned',
                style:
                    theme.textTheme.labelSmall?.copyWith(color: theme.hintColor)),
          ],
        ),
        const SizedBox(height: 12),
        for (final entry in grouped) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Text(
              categories[entry.key] ?? entry.key,
              style: theme.textTheme.labelLarge,
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final badge in entry.value) _BadgeCard(badge: badge),
            ],
          ),
        ],
      ],
    );
  }

  /// Known categories first, in the catalogue's own order, then anything the
  /// server added that this build doesn't know about. Badges inside a category
  /// are a ladder, so they only read correctly sorted by tier.
  List<MapEntry<String, List<BadgeStatus>>> _group(List<BadgeStatus> badges) {
    final byCategory = <String, List<BadgeStatus>>{};
    for (final badge in badges) {
      byCategory.putIfAbsent(badge.category, () => []).add(badge);
    }
    for (final list in byCategory.values) {
      list.sort((a, b) => a.tier.compareTo(b.tier));
    }
    final ordered = <MapEntry<String, List<BadgeStatus>>>[];
    for (final id in categories.keys) {
      final list = byCategory.remove(id);
      if (list != null && list.isNotEmpty) ordered.add(MapEntry(id, list));
    }
    ordered.addAll(byCategory.entries);
    return ordered;
  }

  String _summaryLine(UserStats stats) {
    final parts = <String>[
      if (stats.memberSince != null) 'Member since ${_month(stats.memberSince!)}',
      if (stats.lastWatchAt != null) 'Last watched ${_ago(stats.lastWatchAt!)}',
    ];
    return parts.isEmpty ? 'Nothing watched yet' : parts.join(' · ');
  }
}

/// Seconds → "3d 4h" / "4h 20m" / "20m". Same buckets as the web page's
/// `formatWatchTime`, so a user comparing the two sees the same figure.
String formatWatchTime(int seconds) {
  if (seconds <= 0) return '0m';
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _month(DateTime date) => '${_monthNames[date.month - 1]} ${date.year}';

String _ago(DateTime date) {
  final days = DateTime.now().difference(date).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 30) return '$days days ago';
  return _month(date);
}

class _Stat {
  const _Stat(this.label, this.value, {this.hint});
  final String label;
  final String value;
  final String? hint;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.stat});

  final _Stat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(stat.value,
              style: theme.textTheme.headlineSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(stat.label,
              style: theme.textTheme.labelSmall, maxLines: 2),
          if (stat.hint != null) ...[
            const SizedBox(height: 4),
            Text(stat.hint!,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.hintColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

/// One badge. Earned ones are lit; unearned ones are dimmed and carry a
/// progress bar toward their threshold.
///
/// [TvFocusable] rather than a bare tap target because the badge grid would
/// otherwise hold nothing focusable — a remote could neither reach it nor
/// scroll through it — and it brings `Scrollable.ensureVisible` with it.
class _BadgeCard extends StatelessWidget {
  const _BadgeCard({required this.badge});

  final BadgeStatus badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final earned = badge.earned;

    return SizedBox(
      width: 150,
      child: TvFocusable(
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('${badge.icon}  ${badge.name}'),
            content: Text(
              earned && badge.earnedAt != null
                  ? '${badge.description}\n\nEarned ${_month(badge.earnedAt!)}'
                  : '${badge.description}\n\n'
                      '${badge.progress} of ${badge.threshold}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: earned
                  ? theme.colorScheme.primary.withValues(alpha: 0.6)
                  : theme.dividerColor,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: earned ? 1 : 0.45,
                child: Text(badge.icon, style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(height: 6),
              Text(badge.name,
                  style: theme.textTheme.labelLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(badge.description,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.hintColor),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              if (earned)
                Text(
                  badge.earnedAt == null
                      ? 'Earned'
                      : 'Earned ${_month(badge.earnedAt!)}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.primary),
                )
              else ...[
                LinearProgressIndicator(value: badge.fraction, minHeight: 3),
                const SizedBox(height: 4),
                Text('${badge.progress} / ${badge.threshold}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.hintColor)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
