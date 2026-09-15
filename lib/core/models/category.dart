/// A home-page row. `list` is heterogeneous (Movie/TvShow/Genre/People
/// depending on the row), matching Category.ts's `list: AppItem[]`.
/// Mirrors core/models/Category.ts.
class Category {
  Category(this.name, {List<Object> list = const []}) : list = List.of(list);

  final String name;
  final List<Object> list;

  static const featured = 'In evidenza';
  static const continueWatching = 'Continua a guardare';
  static const favoriteMovies = 'Film preferiti';
  static const favoriteTvShows = 'Serie TV preferite';

  Category copyWith({String? name, List<Object>? list}) {
    return Category(name ?? this.name, list: list ?? this.list);
  }

  @override
  bool operator ==(Object other) => other is Category && other.name == name;

  @override
  int get hashCode => name.hashCode;
}
