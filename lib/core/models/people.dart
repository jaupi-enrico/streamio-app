import 'show.dart';

/// Mirrors core/models/People.ts.
class People {
  People({
    required this.id,
    required this.name,
    this.image,
    this.biography,
    this.placeOfBirth,
    String? birthdayStr,
    String? deathdayStr,
    List<Show> filmography = const [],
  })  : birthday = birthdayStr != null ? DateTime.parse(birthdayStr) : null,
        deathday = deathdayStr != null ? DateTime.parse(deathdayStr) : null,
        filmography = List.unmodifiable(filmography);

  final String id;
  final String name;
  final String? image;
  final String? biography;
  final String? placeOfBirth;
  final DateTime? birthday;
  final DateTime? deathday;
  final List<Show> filmography;

  People copyWith({
    String? id,
    String? name,
    String? image,
    String? biography,
    String? placeOfBirth,
    String? birthdayStr,
    String? deathdayStr,
    List<Show>? filmography,
  }) {
    return People(
      id: id ?? this.id,
      name: name ?? this.name,
      image: image ?? this.image,
      biography: biography ?? this.biography,
      placeOfBirth: placeOfBirth ?? this.placeOfBirth,
      birthdayStr: birthdayStr ?? _dateOnly(birthday),
      deathdayStr: deathdayStr ?? _dateOnly(deathday),
      filmography: filmography ?? this.filmography,
    );
  }

  static String? _dateOnly(DateTime? d) =>
      d?.toIso8601String().split('T').first;

  @override
  bool operator ==(Object other) =>
      other is People &&
      other.id == id &&
      other.name == name &&
      other.image == image &&
      other.biography == biography &&
      other.placeOfBirth == placeOfBirth &&
      other.birthday == birthday &&
      other.deathday == deathday;

  @override
  int get hashCode =>
      Object.hash(id, name, image, biography, placeOfBirth, birthday, deathday);
}
