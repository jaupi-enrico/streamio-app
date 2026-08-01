/// Marker for anything that can appear in a mixed Movie/TvShow list
/// (search results, recommendations, category rows, genre/people filmographies).
/// Mirrors core/models/Show.ts (there: `interface Show extends AppAdapter { isFavorite }`).
abstract class Show {
  String get id;
  String get title;
  String? get poster;
  String? get providerName;
  bool get isFavorite;
}
