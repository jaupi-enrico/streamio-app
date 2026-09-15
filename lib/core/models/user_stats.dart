/// Your own viewing statistics and badges, as `GET /api/account/stats`
/// returns them (`../web/services/stats.service.ts`).
///
/// Snake_case Postgres-derived rows with no TypeScript domain counterpart, so
/// they parse themselves here rather than through `json_mappers.dart` — same
/// split as [LibraryEntry] and the rest of the account types.
///
/// Both endpoints are private to the account: the router reads the user id
/// from the token, so there is no shape of the URL that reads someone else's
/// numbers.
class UserStats {
  const UserStats({
    this.totalWatchSeconds = 0,
    this.episodesCompleted = 0,
    this.moviesCompleted = 0,
    this.episodesInProgress = 0,
    this.titlesStarted = 0,
    this.showsCompleted = 0,
    this.watchlistCount = 0,
    this.favoritesCount = 0,
    this.ratingsCount = 0,
    this.averageRating,
    this.providersUsed = 0,
    this.topProvider,
    this.activeDays = 0,
    this.currentStreakDays = 0,
    this.longestStreakDays = 0,
    this.followersCount = 0,
    this.followingCount = 0,
    this.sharesSent = 0,
    this.sharesReceived = 0,
    this.reactionsReceived = 0,
    this.memberSince,
    this.firstWatchAt,
    this.lastWatchAt,
  });

  factory UserStats.fromJson(Map<String, dynamic> json) {
    return UserStats(
      totalWatchSeconds: _int(json['total_watch_seconds']),
      episodesCompleted: _int(json['episodes_completed']),
      moviesCompleted: _int(json['movies_completed']),
      episodesInProgress: _int(json['episodes_in_progress']),
      titlesStarted: _int(json['titles_started']),
      showsCompleted: _int(json['shows_completed']),
      watchlistCount: _int(json['watchlist_count']),
      favoritesCount: _int(json['favorites_count']),
      ratingsCount: _int(json['ratings_count']),
      averageRating: _double(json['average_rating']),
      providersUsed: _int(json['providers_used']),
      topProvider: _nonEmpty(json['top_provider']),
      activeDays: _int(json['active_days']),
      currentStreakDays: _int(json['current_streak_days']),
      longestStreakDays: _int(json['longest_streak_days']),
      followersCount: _int(json['followers_count']),
      followingCount: _int(json['following_count']),
      sharesSent: _int(json['shares_sent']),
      sharesReceived: _int(json['shares_received']),
      reactionsReceived: _int(json['reactions_received']),
      memberSince: _date(json['member_since']),
      firstWatchAt: _date(json['first_watch_at']),
      lastWatchAt: _date(json['last_watch_at']),
    );
  }

  /// Lifetime seconds of playback. Accumulated per progress report rather than
  /// summed out of `watch_history`, which keeps one row per title and so
  /// forgets rewatches.
  final int totalWatchSeconds;

  final int episodesCompleted;
  final int moviesCompleted;
  final int episodesInProgress;
  final int titlesStarted;

  /// Shows where every episode *in your history* is completed — not "every
  /// episode that exists", which lives upstream and would cost a fetch per
  /// show to learn.
  final int showsCompleted;

  final int watchlistCount;
  final int favoritesCount;
  final int ratingsCount;

  /// Mean of your own ratings, or null if you haven't rated anything.
  final double? averageRating;

  final int providersUsed;

  /// The provider slug you've watched most, or null.
  final String? topProvider;

  final int activeDays;
  final int currentStreakDays;
  final int longestStreakDays;

  final int followersCount;
  final int followingCount;
  final int sharesSent;
  final int sharesReceived;
  final int reactionsReceived;

  final DateTime? memberSince;
  final DateTime? firstWatchAt;
  final DateTime? lastWatchAt;
}

/// A badge plus where this account stands on it.
///
/// [id] is a permanent slug — the server treats renaming one as breaking,
/// since it orphans everything already earned under the old name — so it is
/// safe to key widgets on.
class BadgeStatus {
  const BadgeStatus({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.category,
    this.tier = 1,
    this.threshold = 0,
    this.progress = 0,
    this.earned = false,
    this.earnedAt,
  });

  factory BadgeStatus.fromJson(Map<String, dynamic> json) {
    return BadgeStatus(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      icon: json['icon']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      tier: _int(json['tier']),
      threshold: _int(json['threshold']),
      progress: _int(json['progress']),
      earned: json['earned'] == true,
      earnedAt: _date(json['earned_at']),
    );
  }

  final String id;
  final String name;
  final String description;

  /// An emoji, straight from `badges.catalog.ts`.
  final String icon;

  /// One of time/episodes/movies/shows/streak/library/ratings/social/explorer.
  /// Deliberately a bare string: the catalogue is content the server owns, and
  /// an enum here would fail to parse the first time a category is added.
  final String category;

  /// Rank within [category], 1 upwards — thresholds increase with it.
  final int tier;

  final int threshold;

  /// Your current value of the stat this badge measures.
  final int progress;

  final bool earned;

  /// When it was first earned. Badges are never revoked, so this only ever
  /// goes from null to set.
  final DateTime? earnedAt;

  /// How far along this badge is, 0–1. Earned badges are always full, even if
  /// the underlying stat later fell back below the threshold.
  double get fraction {
    if (earned) return 1;
    if (threshold <= 0) return 0;
    return (progress / threshold).clamp(0, 1).toDouble();
  }
}

/// `GET /api/account/stats` — the numbers and every badge, earned or not.
class AccountStats {
  const AccountStats({required this.stats, required this.badges});

  factory AccountStats.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'];
    final badges = json['badges'];
    return AccountStats(
      stats: UserStats.fromJson(
          stats is Map ? stats.cast<String, dynamic>() : const {}),
      badges: badges is List
          ? badges
              .whereType<Map>()
              .map((e) => BadgeStatus.fromJson(e.cast<String, dynamic>()))
              .toList(growable: false)
          : const [],
    );
  }

  final UserStats stats;
  final List<BadgeStatus> badges;

  Iterable<BadgeStatus> get earned => badges.where((b) => b.earned);
}

/// The counts arrive as numbers, but Postgres `bigint`s come back through
/// `pg` as strings — the same trap [Share.reactionCount] hit — so parse both.
int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double? _double(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

String? _nonEmpty(Object? value) {
  final text = value?.toString();
  return (text == null || text.isEmpty) ? null : text;
}

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());
