import 'episode.dart';
import 'genre.dart';
import 'people.dart';
import 'season.dart';
import 'show.dart';

/// Mirrors core/models/TvShow.ts, including the `episodeToWatch`
/// continue-watching selection getter (priority: in-progress ->
/// next-after-last-watched -> first of first regular season -> fallback).
class TvShow implements Show {
  TvShow({
    this.id = '',
    this.title = '',
    this.overview,
    String? releasedStr,
    this.runtime,
    this.trailer,
    this.quality,
    this.rating,
    this.poster,
    this.banner,
    this.imdbId,
    this.providerName,
    List<Season> seasons = const [],
    List<Genre> genres = const [],
    List<People> directors = const [],
    List<People> cast = const [],
    List<Show> recommendations = const [],
    this.isFavorite = false,
    this.favoritedAtMillis,
    this.isWatching = true,
  })  : released = releasedStr != null ? DateTime.parse(releasedStr) : null,
        seasons = List.of(seasons),
        genres = List.unmodifiable(genres),
        directors = List.unmodifiable(directors),
        cast = List.unmodifiable(cast),
        recommendations = List.unmodifiable(recommendations);

  @override
  final String id;
  @override
  final String title;
  final String? overview;
  final int? runtime;
  final String? trailer;
  final String? quality;
  final double? rating;
  @override
  final String? poster;
  final String? banner;
  final String? imdbId;
  @override
  @override
  final String? providerName;
  final List<Season> seasons;
  final List<Genre> genres;
  final List<People> directors;
  final List<People> cast;
  final List<Show> recommendations;

  @override
  final bool isFavorite;
  final DateTime? released;
  final int? favoritedAtMillis;
  final bool isWatching;

  /// Same priority logic as TvShow.ts's `episodeToWatch` getter:
  /// A. last in-progress episode (most recent watchHistory engagement)
  /// B. episode right after the last one marked fully watched
  /// C. first episode of the first non-special (number != 0) season
  /// D. absolute fallback: first episode found at all
  Episode? get episodeToWatch {
    final sortedSeasons = List<Season>.of(seasons)
      ..sort((a, b) {
        if (a.number == 0) return 1;
        if (b.number == 0) return -1;
        return a.number.compareTo(b.number);
      });

    final allEpisodes = <Episode>[];
    for (final season in sortedSeasons) {
      final sortedEpisodes = List<Episode>.of(season.episodes)
        ..sort((a, b) => a.number.compareTo(b.number));
      for (final episode in sortedEpisodes) {
        episode.season = season;
        episode.tvShow = this;
        allEpisodes.add(episode);
      }
    }

    final inProgress = allEpisodes.where((e) => e.watchHistory != null).toList()
      ..sort((a, b) => (b.watchHistory?.lastEngagementTimeUtcMillis ?? 0)
          .compareTo(a.watchHistory?.lastEngagementTimeUtcMillis ?? 0));
    if (inProgress.isNotEmpty) return inProgress.first;

    final lastWatchedIndex =
        allEpisodes.lastIndexWhere((e) => e.isWatched == true);
    if (lastWatchedIndex != -1 && lastWatchedIndex + 1 < allEpisodes.length) {
      return allEpisodes[lastWatchedIndex + 1];
    }

    final firstRegularSeason =
        sortedSeasons.where((s) => s.number != 0).cast<Season?>().firstWhere(
              (s) => s!.episodes.isNotEmpty,
              orElse: () => null,
            );
    if (firstRegularSeason != null) {
      final firstEpisode = List<Episode>.of(firstRegularSeason.episodes)
        ..sort((a, b) => a.number.compareTo(b.number));
      if (firstEpisode.isNotEmpty) return firstEpisode.first;
    }

    return allEpisodes.isNotEmpty ? allEpisodes.first : null;
  }

  TvShow copyWith({
    String? id,
    String? title,
    String? overview,
    String? releasedStr,
    int? runtime,
    String? trailer,
    String? quality,
    double? rating,
    String? poster,
    String? banner,
    String? imdbId,
    String? providerName,
    List<Season>? seasons,
    List<Genre>? genres,
    List<People>? directors,
    List<People>? cast,
    List<Show>? recommendations,
    bool? isFavorite,
    int? favoritedAtMillis,
    bool? isWatching,
  }) {
    return TvShow(
      id: id ?? this.id,
      title: title ?? this.title,
      overview: overview ?? this.overview,
      releasedStr: releasedStr ?? _dateOnly(released),
      runtime: runtime ?? this.runtime,
      trailer: trailer ?? this.trailer,
      quality: quality ?? this.quality,
      rating: rating ?? this.rating,
      poster: poster ?? this.poster,
      banner: banner ?? this.banner,
      imdbId: imdbId ?? this.imdbId,
      providerName: providerName ?? this.providerName,
      seasons: seasons ?? this.seasons,
      genres: genres ?? this.genres,
      directors: directors ?? this.directors,
      cast: cast ?? this.cast,
      recommendations: recommendations ?? this.recommendations,
      isFavorite: isFavorite ?? this.isFavorite,
      favoritedAtMillis: favoritedAtMillis ?? this.favoritedAtMillis,
      isWatching: isWatching ?? this.isWatching,
    );
  }

  TvShow mergeUserState(TvShow other) => copyWith(
        isFavorite: other.isFavorite,
        favoritedAtMillis: other.favoritedAtMillis,
        isWatching: other.isWatching,
      );

  bool isSameUserState(TvShow other) =>
      isFavorite == other.isFavorite &&
      favoritedAtMillis == other.favoritedAtMillis &&
      isWatching == other.isWatching;

  static String? _dateOnly(DateTime? d) =>
      d?.toIso8601String().split('T').first;

  @override
  bool operator ==(Object other) =>
      other is TvShow &&
      other.id == id &&
      other.isWatching == isWatching &&
      other.isFavorite == isFavorite;

  @override
  int get hashCode => Object.hash(id, isWatching, isFavorite);
}
