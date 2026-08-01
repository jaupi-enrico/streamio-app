/// Client-local watch progress, kept separate from the server's
/// seconds-based `watch_history` table (see data/sync/sync_mappers.dart
/// for the ms<->s conversion at the sync boundary).
/// Mirrors core/models/WatchItem.ts.
class WatchHistory {
  const WatchHistory({
    required this.lastEngagementTimeUtcMillis,
    required this.lastPlaybackPositionMillis,
    required this.durationMillis,
  });

  final int lastEngagementTimeUtcMillis;
  final int lastPlaybackPositionMillis;
  final int durationMillis;

  WatchHistory copyWith({
    int? lastEngagementTimeUtcMillis,
    int? lastPlaybackPositionMillis,
    int? durationMillis,
  }) {
    return WatchHistory(
      lastEngagementTimeUtcMillis:
          lastEngagementTimeUtcMillis ?? this.lastEngagementTimeUtcMillis,
      lastPlaybackPositionMillis:
          lastPlaybackPositionMillis ?? this.lastPlaybackPositionMillis,
      durationMillis: durationMillis ?? this.durationMillis,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WatchHistory &&
      other.lastEngagementTimeUtcMillis == lastEngagementTimeUtcMillis &&
      other.lastPlaybackPositionMillis == lastPlaybackPositionMillis &&
      other.durationMillis == durationMillis;

  @override
  int get hashCode => Object.hash(
      lastEngagementTimeUtcMillis, lastPlaybackPositionMillis, durationMillis);
}

/// Implemented by Movie/Episode. Mirrors core/models/WatchItem.ts.
abstract class WatchItem {
  bool get isWatched;
  DateTime? get watchedDate;
  WatchHistory? get watchHistory;
}
