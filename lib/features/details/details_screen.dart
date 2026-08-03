import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../shared/widgets/async_states.dart';
import '../../shared/widgets/tv_focusable.dart';
import '../../state/api_providers.dart';
import '../../state/auth_providers.dart';
import '../downloads/download_sheet.dart';
import '../social/share_sheet.dart';
import 'details_providers.dart';

/// `details.html` / `details.js`: artwork, metadata, cast, the library
/// actions (watchlist / favorite / rating / share / watch party), a per-season
/// episode list, and the download buttons.
class DetailsScreen extends ConsumerStatefulWidget {
  const DetailsScreen(
      {super.key, required this.provider, required this.showId});

  final String provider;
  final String showId;

  @override
  ConsumerState<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends ConsumerState<DetailsScreen> {
  int _selectedSeasonIndex = 0;

  ShowRef get _showRef => (provider: widget.provider, showId: widget.showId);

  void _play(
    String id, {
    required String contentType,
    String? title,
    String? episodeLabel,
    int? startSeconds,
  }) {
    final query = {
      'contentType': contentType,
      'showId': widget.showId,
      if (title != null) 'title': title,
      if (episodeLabel != null) 'episodeLabel': episodeLabel,
      if (startSeconds != null && startSeconds > 0) 't': '$startSeconds',
    };
    context.push(
        '/watch/${widget.provider}/${Uri.encodeComponent(id)}?${Uri(queryParameters: query).query}');
  }

  Future<void> _requireSignIn(Future<void> Function() action) async {
    if (!ref.read(isSignedInProvider)) {
      showToast(context, 'Sign in to use your library.', isError: true);
      context.push('/login');
      return;
    }
    await action();
  }

  Future<void> _toggleWatchlist() => _requireSignIn(() async {
        final api = ref.read(accountApiProvider);
        final inList =
            ref.read(inWatchlistProvider(_showRef)).valueOrNull ?? false;
        final ok = await runGuarded(
          context,
          () => inList
              ? api.removeFromWatchlist(widget.provider, widget.showId)
              : api.addToWatchlist(widget.provider, widget.showId),
          successMessage:
              inList ? 'Removed from watchlist' : 'Added to watchlist',
        );
        if (ok) ref.invalidate(inWatchlistProvider(_showRef));
      });

  Future<void> _toggleFavorite() => _requireSignIn(() async {
        final api = ref.read(accountApiProvider);
        final isFavorite =
            ref.read(isFavoriteProvider(_showRef)).valueOrNull ?? false;
        final ok = await runGuarded(
          context,
          () => isFavorite
              ? api.removeFavorite(widget.provider, widget.showId)
              : api.addFavorite(widget.provider, widget.showId),
          successMessage:
              isFavorite ? 'Removed from favorites' : 'Added to favorites',
        );
        if (ok) ref.invalidate(isFavoriteProvider(_showRef));
      });

  Future<void> _rate() => _requireSignIn(() async {
        final current = ref.read(myRatingProvider(_showRef)).valueOrNull;
        final picked = await showModalBottomSheet<int>(
          context: context,
          builder: (context) => _RatingSheet(current: current?.round()),
        );
        if (picked == null || !mounted) return;

        final api = ref.read(accountApiProvider);
        final ok = await runGuarded(
          context,
          () => picked == 0
              ? api.deleteRating(widget.provider, widget.showId)
              : api.setRating(widget.provider, widget.showId, picked),
          successMessage: picked == 0 ? 'Rating removed' : 'Rated $picked/10',
        );
        if (ok) ref.invalidate(myRatingProvider(_showRef));
      });

  Future<void> _share(String title) => _requireSignIn(() async {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (context) => ShareSheet(
            provider: widget.provider,
            showId: widget.showId,
            title: title,
          ),
        );
      });

  /// Creates a room for this title and deep-links into the player with it —
  /// the same flow as the "Watch Party" button on `details.html`.
  Future<void> _startWatchParty(Show show) => _requireSignIn(() async {
        final episodeId = show is TvShow ? show.episodeToWatch?.id : null;
        final contentType = show is TvShow ? 'episode' : 'movie';

        try {
          final room = await ref.read(roomsApiProvider).create(
                provider: widget.provider,
                showId: widget.showId,
                episodeId: episodeId,
                contentType: contentType,
              );
          if (!mounted) return;

          final playbackId = episodeId ?? widget.showId;
          final query = {
            'contentType': contentType,
            'showId': widget.showId,
            'title': show.title,
            'room': room.code,
          };
          context.push(
              '/watch/${widget.provider}/${Uri.encodeComponent(playbackId)}?${Uri(queryParameters: query).query}');
        } catch (err) {
          if (mounted) {
            showToast(context, ErrorState.messageFor(err), isError: true);
          }
        }
      });

  Future<void> _download(String contentId, String contentType, String title,
      {String? episodeLabel}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DownloadSheet(
        provider: widget.provider,
        showId: widget.showId,
        contentId: contentId,
        contentType: contentType,
        title: title,
        episodeLabel: episodeLabel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detailsAsync = ref.watch(showDetailsProvider(_showRef));

    return Scaffold(
      body: detailsAsync.when(
        loading: () => const LoadingState(),
        error: (error, _) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(showDetailsProvider(_showRef)),
        ),
        data: (show) {
          if (show == null) {
            return const EmptyState(message: 'This title could not be found.');
          }
          if (show is Movie) return _movieBody(show);
          if (show is TvShow) return _tvShowBody(show);
          return const EmptyState(message: 'Unsupported content type.');
        },
      ),
    );
  }

  // ── Movie ─────────────────────────────────────────────────

  Widget _movieBody(Movie movie) {
    final progressAsync = ref.watch(episodeProgressProvider(
        (provider: widget.provider, showId: widget.showId, episodeId: null)));
    final resumeAt = progressAsync.valueOrNull?.progressSeconds ?? 0;

    return CustomScrollView(
      slivers: [
        _header(banner: movie.banner ?? movie.poster, title: movie.title),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _metaLine(
                  year: movie.released?.year,
                  runtime: movie.runtime,
                  rating: movie.rating,
                  quality: movie.quality,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _play(
                          movie.id,
                          contentType: 'movie',
                          title: movie.title,
                          startSeconds: resumeAt,
                        ),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(resumeAt > 0 ? 'Resume' : 'Play'),
                        style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      onPressed: () =>
                          _download(movie.id, 'movie', movie.title),
                      icon: const Icon(Icons.download_outlined),
                      tooltip: 'Download for offline',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _actionRow(movie),
                const SizedBox(height: 16),
                if (movie.overview != null) Text(movie.overview!),
                const SizedBox(height: 14),
                _genreChips(movie.genres),
                _peopleSection('Cast', movie.cast),
                _peopleSection('Directed by', movie.directors),
                _recommendations(movie.recommendations),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── TV show ───────────────────────────────────────────────

  Widget _tvShowBody(TvShow tvShow) {
    final seasons = tvShow.seasons;
    final selectedSeason = seasons.isNotEmpty
        ? seasons[_selectedSeasonIndex.clamp(0, seasons.length - 1)]
        : null;
    final next = tvShow.episodeToWatch;

    return CustomScrollView(
      slivers: [
        _header(banner: tvShow.banner ?? tvShow.poster, title: tvShow.title),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _metaLine(
                  year: tvShow.released?.year,
                  runtime: tvShow.runtime,
                  rating: tvShow.rating,
                  quality: tvShow.quality,
                  seasons: seasons.length,
                ),
                const SizedBox(height: 16),
                if (next != null)
                  FilledButton.icon(
                    onPressed: () => _play(
                      next.id,
                      contentType: 'episode',
                      title: tvShow.title,
                      episodeLabel: _episodeLabel(next),
                    ),
                    icon: const Icon(Icons.play_arrow),
                    label: Text('Play ${_episodeLabel(next)}'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                const SizedBox(height: 12),
                _actionRow(tvShow),
                const SizedBox(height: 16),
                if (tvShow.overview != null) Text(tvShow.overview!),
                const SizedBox(height: 14),
                _genreChips(tvShow.genres),
                if (seasons.length > 1) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 40,
                    child: FocusTraversalGroup(
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: seasons.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) => ChoiceChip(
                          label: Text(seasons[i].title ??
                              'Season ${seasons[i].number}'),
                          selected: i == _selectedSeasonIndex,
                          onSelected: (_) =>
                              setState(() => _selectedSeasonIndex = i),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (selectedSeason != null)
          _EpisodesSliver(
            provider: widget.provider,
            showId: widget.showId,
            season: selectedSeason,
            onPlay: (episode, resumeAt) => _play(
              episode.id,
              contentType: 'episode',
              title: tvShow.title,
              episodeLabel: _episodeLabel(episode, season: selectedSeason),
              startSeconds: resumeAt,
            ),
            onDownload: (episode) => _download(
              episode.id,
              'episode',
              tvShow.title,
              episodeLabel: _episodeLabel(episode, season: selectedSeason),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _peopleSection('Cast', tvShow.cast),
                _recommendations(tvShow.recommendations),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _episodeLabel(Episode episode, {Season? season}) {
    final seasonNumber = season?.number ?? episode.season?.number;
    final prefix = seasonNumber != null
        ? 'S${seasonNumber.toString().padLeft(2, '0')}'
        : '';
    return '${prefix}E${episode.number.toString().padLeft(2, '0')}';
  }

  // ── Shared pieces ─────────────────────────────────────────

  Widget _header({String? banner, required String title}) {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (banner != null)
              CachedNetworkImage(
                imageUrl: banner,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    Container(color: const Color(0xFF1E2430)),
              )
            else
              Container(color: const Color(0xFF1E2430)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                  stops: [0.4, 1],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaLine({
    int? year,
    int? runtime,
    double? rating,
    String? quality,
    int? seasons,
  }) {
    final parts = <String>[
      if (year != null) '$year',
      if (seasons != null && seasons > 0)
        '$seasons season${seasons == 1 ? '' : 's'}',
      if (runtime != null && runtime > 0) '$runtime min',
      if (quality != null && quality.isNotEmpty) quality,
    ];

    return Row(
      children: [
        if (rating != null) ...[
          const Icon(Icons.star, size: 16, color: Color(0xFFE8A33D)),
          const SizedBox(width: 4),
          Text(rating.toStringAsFixed(1)),
          if (parts.isNotEmpty) const SizedBox(width: 12),
        ],
        Expanded(
          child: Text(
            parts.join(' · '),
            style: TextStyle(color: Theme.of(context).hintColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _actionRow(Show show) {
    final inWatchlist =
        ref.watch(inWatchlistProvider(_showRef)).valueOrNull ?? false;
    final isFavorite =
        ref.watch(isFavoriteProvider(_showRef)).valueOrNull ?? false;
    final myRating = ref.watch(myRatingProvider(_showRef)).valueOrNull;

    return FocusTraversalGroup(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ActionButton(
              icon: inWatchlist ? Icons.bookmark : Icons.bookmark_border,
              label: inWatchlist ? 'In list' : 'Watchlist',
              active: inWatchlist,
              onTap: _toggleWatchlist,
            ),
            _ActionButton(
              icon: isFavorite ? Icons.favorite : Icons.favorite_border,
              label: 'Favorite',
              active: isFavorite,
              onTap: _toggleFavorite,
            ),
            _ActionButton(
              icon: myRating != null ? Icons.star : Icons.star_border,
              label: myRating != null ? '${myRating.round()}/10' : 'Rate',
              active: myRating != null,
              onTap: _rate,
            ),
            _ActionButton(
              icon: Icons.ios_share,
              label: 'Share',
              onTap: () => _share(show.title),
            ),
            _ActionButton(
              icon: Icons.groups_outlined,
              label: 'Watch party',
              onTap: () => _startWatchParty(show),
            ),
          ],
        ),
      ),
    );
  }

  Widget _genreChips(List<Genre> genres) {
    if (genres.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final genre in genres)
          ActionChip(
            label: Text(genre.name),
            onPressed: () =>
                context.push('/catalog?genre=${Uri.encodeComponent(genre.id)}'),
          ),
      ],
    );
  }

  Widget _peopleSection(String title, List<People> people) {
    if (people.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          SizedBox(
            height: 128,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: people.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final person = people[i];
                return SizedBox(
                  width: 76,
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: const Color(0xFF1E2430),
                        backgroundImage: person.image != null
                            ? CachedNetworkImageProvider(person.image!)
                            : null,
                        child: person.image == null
                            ? const Icon(Icons.person, color: Colors.white24)
                            : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        person.name,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _recommendations(List<Show> shows) {
    if (shows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('More like this',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          SizedBox(
            height: 200,
            child: FocusTraversalGroup(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: shows.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final show = shows[i];
                  return SizedBox(
                    width: 110,
                    child: TvFocusable(
                      // replace(), not push(): following recommendations
                      // shouldn't build an unbounded back stack of details pages.
                      onTap: () => context.replace(
                          '/details/${show.providerName ?? widget.provider}/${Uri.encodeComponent(show.id)}'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: show.poster != null
                                  ? CachedNetworkImage(
                                      imageUrl: show.poster!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      errorWidget: (_, __, ___) => Container(
                                          color: const Color(0xFF1E2430)),
                                    )
                                  : Container(color: const Color(0xFF1E2430)),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(show.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).hintColor;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TvFocusable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 4),
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RatingSheet extends StatelessWidget {
  const _RatingSheet({this.current});

  final int? current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your rating', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // The backend only accepts whole numbers 1–10.
                for (var value = 1; value <= 10; value++)
                  ChoiceChip(
                    label: Text('$value'),
                    selected: value == current,
                    onSelected: (_) => Navigator.of(context).pop(value),
                  ),
              ],
            ),
            if (current != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(0),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove my rating'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EpisodesSliver extends ConsumerWidget {
  const _EpisodesSliver({
    required this.provider,
    required this.showId,
    required this.season,
    required this.onPlay,
    required this.onDownload,
  });

  final String provider;
  final String showId;
  final Season season;
  final void Function(Episode episode, int resumeAt) onPlay;
  final void Function(Episode episode) onDownload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Seasons from `/api/shows/:id` sometimes arrive with their episodes
    // already inlined; only go back to the network when they didn't.
    if (season.episodes.isNotEmpty) {
      return _list(context, ref, season.episodes);
    }

    final episodesAsync = ref.watch(
        seasonEpisodesProvider((provider: provider, seasonId: season.id)));

    return episodesAsync.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Text('Could not load episodes: ${ErrorState.messageFor(error)}'),
        ),
      ),
      data: (episodes) => _list(context, ref, episodes),
    );
  }

  Widget _list(BuildContext context, WidgetRef ref, List<Episode> episodes) {
    if (episodes.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No episodes listed for this season.'),
        ),
      );
    }

    return SliverList.separated(
      itemCount: episodes.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final episode = episodes[i];
        final progress = ref
            .watch(episodeProgressProvider(
                (provider: provider, showId: showId, episodeId: episode.id)))
            .valueOrNull;
        final resumeAt =
            progress?.completed == true ? 0 : (progress?.progressSeconds ?? 0);

        return ListTile(
          onTap: () => onPlay(episode, resumeAt),
          leading: SizedBox(
            width: 64,
            height: 40,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: episode.poster != null
                  ? CachedNetworkImage(
                      imageUrl: episode.poster!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          Container(color: const Color(0xFF1E2430)),
                    )
                  : Container(
                      color: const Color(0xFF1E2430),
                      alignment: Alignment.center,
                      child: Text('${episode.number}'),
                    ),
            ),
          ),
          title: Text(
              '${episode.number}. ${episode.title ?? 'Episode ${episode.number}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (episode.overview != null)
                Text(episode.overview!,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              if (progress != null && progress.progressFraction != null) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: progress.completed ? 1 : progress.progressFraction,
                  minHeight: 2,
                ),
              ],
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Download for offline',
            onPressed: () => onDownload(episode),
          ),
        );
      },
    );
  }
}
