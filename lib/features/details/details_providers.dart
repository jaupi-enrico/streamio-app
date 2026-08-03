import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../state/api_providers.dart';
import '../../state/auth_providers.dart';

typedef ShowRef = ({String provider, String showId});
typedef SeasonEpisodesArgs = ({String provider, String seasonId});

final showDetailsProvider =
    FutureProvider.autoDispose.family<Show?, ShowRef>((ref, args) async {
  return ref.watch(contentApiProvider).showDetails(args.showId, provider: args.provider);
});

final seasonEpisodesProvider = FutureProvider.autoDispose
    .family<List<Episode>, SeasonEpisodesArgs>((ref, args) async {
  return ref.watch(contentApiProvider).episodes(args.seasonId, provider: args.provider);
});

typedef NextEpisodeArgs = ({String provider, String showId, String episodeId});

/// The episode after [NextEpisodeArgs.episodeId] in show order, across season
/// boundaries — the same flatten `TvShow.episodeToWatch` uses, but anchored
/// on a specific episode rather than watch history. Powers the player's
/// autoplay-next-episode prompt; null for the finale, a movie, or an id it
/// doesn't recognize.
final nextEpisodeProvider =
    FutureProvider.autoDispose.family<Episode?, NextEpisodeArgs>((ref, args) async {
  final show = await ref
      .watch(showDetailsProvider((provider: args.provider, showId: args.showId)).future);
  if (show is! TvShow) return null;

  final sortedSeasons = List<Season>.of(show.seasons)
    ..sort((a, b) {
      if (a.number == 0) return 1;
      if (b.number == 0) return -1;
      return a.number.compareTo(b.number);
    });

  final api = ref.watch(contentApiProvider);
  final allEpisodes = <Episode>[];
  for (final season in sortedSeasons) {
    final episodes = season.episodes.isNotEmpty
        ? season.episodes
        : await api.episodes(season.id, provider: args.provider);
    final sorted = List<Episode>.of(episodes)..sort((a, b) => a.number.compareTo(b.number));
    for (final episode in sorted) {
      episode.season = season;
      allEpisodes.add(episode);
    }
  }

  final index = allEpisodes.indexWhere((e) => e.id == args.episodeId);
  if (index == -1 || index + 1 >= allEpisodes.length) return null;
  return allEpisodes[index + 1];
});

/// Whether this title is in the user's watchlist. There's no per-item
/// watchlist endpoint (unlike favorites), so it's derived from the list.
final inWatchlistProvider =
    FutureProvider.autoDispose.family<bool, ShowRef>((ref, args) async {
  if (!ref.watch(isSignedInProvider)) return false;
  final entries = await ref.watch(accountApiProvider).watchlist();
  return entries.any((e) => e.provider == args.provider && e.showId == args.showId);
});

final isFavoriteProvider =
    FutureProvider.autoDispose.family<bool, ShowRef>((ref, args) async {
  if (!ref.watch(isSignedInProvider)) return false;
  return ref.watch(accountApiProvider).isFavorite(args.provider, args.showId);
});

/// The user's own 1–10 rating, or null if they haven't rated it.
final myRatingProvider =
    FutureProvider.autoDispose.family<double?, ShowRef>((ref, args) async {
  if (!ref.watch(isSignedInProvider)) return null;
  return ref.watch(accountApiProvider).rating(args.provider, args.showId);
});

/// Resume position for a specific episode (or the movie itself), used to show
/// a progress bar on the episode list and to pass `t=` into the player.
final episodeProgressProvider = FutureProvider.autoDispose
    .family<HistoryEntry?, ({String provider, String showId, String? episodeId})>(
        (ref, args) async {
  if (!ref.watch(isSignedInProvider)) return null;
  return ref.watch(accountApiProvider).progress(
        provider: args.provider,
        showId: args.showId,
        episodeId: args.episodeId,
      );
});
