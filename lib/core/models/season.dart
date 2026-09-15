import 'episode.dart';
import 'tv_show.dart';

/// Mirrors core/models/Season.ts.
class Season {
  Season({
    this.id = '',
    this.number = 0,
    this.title,
    this.poster,
    this.tvShow,
    List<Episode> episodes = const [],
  }) : episodes = List.of(episodes);

  final String id;
  final int number;
  final String? title;
  final String? poster;
  TvShow? tvShow;
  final List<Episode> episodes;

  Season copyWith({
    String? id,
    int? number,
    String? title,
    String? poster,
    TvShow? tvShow,
    List<Episode>? episodes,
  }) {
    return Season(
      id: id ?? this.id,
      number: number ?? this.number,
      title: title ?? this.title,
      poster: poster ?? this.poster,
      tvShow: tvShow ?? this.tvShow,
      episodes: episodes ?? this.episodes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Season &&
      other.id == id &&
      other.number == number &&
      other.title == title &&
      other.poster == poster;

  @override
  int get hashCode => Object.hash(id, number, title, poster);
}
