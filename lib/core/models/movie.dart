import 'genre.dart';
import 'people.dart';
import 'show.dart';
import 'watch_item.dart';

/// Mirrors core/models/Movie.ts. Adapter/list-diffing fields (itemType,
/// states, click listeners) are dropped — Flutter uses its own widgets.
class Movie implements Show, WatchItem {
  Movie({
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
    List<Genre> genres = const [],
    List<People> directors = const [],
    List<People> cast = const [],
    List<Show> recommendations = const [],
    this.isFavorite = false,
    this.favoritedAtMillis,
    this.isWatched = false,
    this.watchedDate,
    this.watchHistory,
  })  : released = releasedStr != null ? DateTime.parse(releasedStr) : null,
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
  final List<Genre> genres;
  final List<People> directors;
  final List<People> cast;
  final List<Show> recommendations;

  @override
  final bool isFavorite;
  final DateTime? released;
  final int? favoritedAtMillis;
  @override
  final bool isWatched;
  @override
  final DateTime? watchedDate;
  @override
  final WatchHistory? watchHistory;

  /// Unique identity across providers, since show_id is only opaque
  /// per-provider (there is no canonical cross-provider id).
  String get itemIdentity => '${providerName ?? "unknown"}_$id';

  Movie copyWith({
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
    List<Genre>? genres,
    List<People>? directors,
    List<People>? cast,
    List<Show>? recommendations,
    bool? isFavorite,
    int? favoritedAtMillis,
    bool? isWatched,
    DateTime? watchedDate,
    WatchHistory? watchHistory,
  }) {
    return Movie(
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
      genres: genres ?? this.genres,
      directors: directors ?? this.directors,
      cast: cast ?? this.cast,
      recommendations: recommendations ?? this.recommendations,
      isFavorite: isFavorite ?? this.isFavorite,
      favoritedAtMillis: favoritedAtMillis ?? this.favoritedAtMillis,
      isWatched: isWatched ?? this.isWatched,
      watchedDate: watchedDate ?? this.watchedDate,
      watchHistory: watchHistory ?? this.watchHistory,
    );
  }

  /// Applies another instance's user-state (favorite/watched) onto a copy.
  Movie mergeUserState(Movie other) => copyWith(
        isFavorite: other.isFavorite,
        favoritedAtMillis: other.favoritedAtMillis,
        isWatched: other.isWatched,
        watchedDate: other.watchedDate,
        watchHistory: other.watchHistory,
      );

  bool isSameUserState(Movie other) =>
      isFavorite == other.isFavorite &&
      favoritedAtMillis == other.favoritedAtMillis &&
      isWatched == other.isWatched &&
      watchedDate == other.watchedDate &&
      watchHistory == other.watchHistory;

  static String? _dateOnly(DateTime? d) =>
      d?.toIso8601String().split('T').first;

  @override
  bool operator ==(Object other) =>
      other is Movie &&
      other.id == id &&
      other.title == title &&
      other.isFavorite == isFavorite &&
      other.isWatched == isWatched &&
      other.released == released;

  @override
  int get hashCode => Object.hash(id, title, isFavorite, isWatched, released);
}
