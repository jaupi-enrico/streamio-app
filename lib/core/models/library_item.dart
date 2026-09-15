/// Rows of the account library tables (`watchlist`, `favorites`, `ratings`,
/// `watch_history`) as `account.router.ts` returns them. These are snake_case
/// Postgres rows, not the camelCase domain models the content endpoints
/// return, so they get their own types rather than being forced into
/// [Movie]/[TvShow].
class LibraryEntry {
  const LibraryEntry({
    required this.provider,
    required this.showId,
    this.title,
    this.poster,
    this.contentType,
    this.addedAt,
  });

  factory LibraryEntry.fromJson(Map<String, dynamic> json) {
    return LibraryEntry(
      provider: json['provider']?.toString() ?? '',
      showId: json['show_id']?.toString() ?? '',
      title: json['title']?.toString(),
      poster: json['poster']?.toString(),
      contentType: json['content_type']?.toString(),
      addedAt: DateTime.tryParse(
          (json['added_at'] ?? json['created_at'] ?? '').toString()),
    );
  }

  final String provider;
  final String showId;
  final String? title;
  final String? poster;
  final String? contentType;
  final DateTime? addedAt;

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'show_id': showId,
        if (title != null) 'title': title,
        if (poster != null) 'poster': poster,
        if (contentType != null) 'content_type': contentType,
      };
}

/// A row of `watch_history` (`GET /api/account/history`), also what the Home
/// screen's "Continue Watching" rail is built from.
class HistoryEntry {
  const HistoryEntry({
    required this.provider,
    required this.showId,
    this.episodeId,
    this.episodeLabel,
    this.title,
    this.poster,
    this.progressSeconds = 0,
    this.durationSeconds,
    this.completed = false,
    this.watchedAt,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      provider: json['provider']?.toString() ?? '',
      showId: json['show_id']?.toString() ?? '',
      episodeId: json['episode_id']?.toString(),
      episodeLabel: json['episode_label']?.toString(),
      title: json['title']?.toString(),
      poster: json['poster']?.toString(),
      progressSeconds: _toInt(json['progress_seconds']) ?? 0,
      durationSeconds: _toInt(json['duration_seconds']),
      completed: json['completed'] == true,
      watchedAt: DateTime.tryParse(
          (json['watched_at'] ?? json['updated_at'] ?? '').toString()),
    );
  }

  final String provider;
  final String showId;
  final String? episodeId;
  final String? episodeLabel;
  final String? title;
  final String? poster;
  final int progressSeconds;
  final int? durationSeconds;
  final bool completed;
  final DateTime? watchedAt;

  /// 0..1 watched fraction, or null when the duration was never recorded.
  double? get progressFraction {
    final total = durationSeconds;
    if (total == null || total <= 0) return null;
    return (progressSeconds / total).clamp(0.0, 1.0);
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString());
  }
}

/// A row of `ratings` (`GET /api/account/ratings`).
class RatingEntry {
  const RatingEntry({
    required this.provider,
    required this.showId,
    required this.rating,
    this.title,
    this.poster,
    this.ratedAt,
  });

  factory RatingEntry.fromJson(Map<String, dynamic> json) {
    return RatingEntry(
      provider: json['provider']?.toString() ?? '',
      showId: json['show_id']?.toString() ?? '',
      rating: (json['rating'] as num?)?.toDouble() ??
          double.tryParse(json['rating']?.toString() ?? '') ??
          0,
      title: json['title']?.toString(),
      poster: json['poster']?.toString(),
      ratedAt: DateTime.tryParse(
          (json['rated_at'] ?? json['created_at'] ?? '').toString()),
    );
  }

  final String provider;
  final String showId;
  final double rating;
  final String? title;
  final String? poster;
  final DateTime? ratedAt;
}
