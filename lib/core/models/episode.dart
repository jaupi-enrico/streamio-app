import 'season.dart';
import 'tv_show.dart';
import 'watch_item.dart';

/// Mirrors core/models/Episode.ts. `tvShow`/`season` are mutable because
/// TvShow.episodeToWatch back-fills them while flattening seasons (same as
/// the TS getter does) — avoid relying on these for equality/serialization,
/// they're a convenience back-reference, not source-of-truth data.
class Episode implements WatchItem {
  Episode({
    this.id = '',
    this.number = 0,
    this.title,
    String? releasedStr,
    this.poster,
    this.overview,
    this.tvShow,
    this.season,
    this.isWatched = false,
    this.watchedDate,
    this.watchHistory,
  }) : released = releasedStr != null ? DateTime.parse(releasedStr) : null;

  final String id;
  final int number;
  final String? title;
  final String? poster;
  final String? overview;
  TvShow? tvShow;
  Season? season;
  final DateTime? released;

  @override
  final bool isWatched;
  @override
  final DateTime? watchedDate;
  @override
  final WatchHistory? watchHistory;

  Episode copyWith({
    String? id,
    int? number,
    String? title,
    String? releasedStr,
    String? poster,
    String? overview,
    TvShow? tvShow,
    Season? season,
    bool? isWatched,
    DateTime? watchedDate,
    WatchHistory? watchHistory,
  }) {
    return Episode(
      id: id ?? this.id,
      number: number ?? this.number,
      title: title ?? this.title,
      releasedStr: releasedStr ?? _dateOnly(released),
      poster: poster ?? this.poster,
      overview: overview ?? this.overview,
      tvShow: tvShow ?? this.tvShow,
      season: season ?? this.season,
      isWatched: isWatched ?? this.isWatched,
      watchedDate: watchedDate ?? this.watchedDate,
      watchHistory: watchHistory ?? this.watchHistory,
    );
  }

  Episode mergeUserState(Episode other) => copyWith(
        isWatched: other.isWatched,
        watchedDate: other.watchedDate,
        watchHistory: other.watchHistory,
      );

  bool isSameUserState(Episode other) =>
      isWatched == other.isWatched &&
      watchedDate == other.watchedDate &&
      watchHistory == other.watchHistory;

  static String? _dateOnly(DateTime? d) =>
      d?.toIso8601String().split('T').first;

  @override
  bool operator ==(Object other) =>
      other is Episode &&
      other.id == id &&
      other.number == number &&
      other.title == title &&
      other.poster == poster &&
      other.overview == overview &&
      other.isWatched == isWatched &&
      other.released == released;

  @override
  int get hashCode =>
      Object.hash(id, number, title, poster, overview, isWatched, released);
}
