import 'show.dart';

/// Mirrors core/models/Genre.ts (ItemType/adapter fields dropped, not
/// relevant to a Flutter client — see plan's "not ported" list).
class Genre {
  Genre({
    required this.id,
    required this.name,
    List<Show> shows = const [],
  }) : shows = List.unmodifiable(shows);

  final String id;
  final String name;
  final List<Show> shows;

  Genre copyWith({String? id, String? name, List<Show>? shows}) {
    return Genre(
      id: id ?? this.id,
      name: name ?? this.name,
      shows: shows ?? this.shows,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Genre && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}
