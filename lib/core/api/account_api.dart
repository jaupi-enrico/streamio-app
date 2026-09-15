import '../models/models.dart';
import 'api_client.dart';
import 'paged_response.dart';

/// `routes/account.router.ts`. Everything here is behind `requireAuth`, so
/// every call passes `authenticated: true` and can raise
/// [SessionExpiredException].
class AccountApi {
  AccountApi(this._client);

  final ApiClient _client;

  String _seg(String value) => Uri.encodeComponent(value);

  /// `GET /api/account/stats` — the numbers *and* every badge.
  ///
  /// Reading this is what awards badges server-side (`StatsService.syncBadges`),
  /// so it must not be cached: someone who just crossed a threshold should see
  /// the badge on the read that made them cross it. There is a `/badges`
  /// endpoint too, but it returns a subset of this one, so nothing here needs
  /// it.
  Future<AccountStats> stats() async {
    final json = await _client.get<Map<String, dynamic>>('/api/account/stats',
        authenticated: true);
    return AccountStats.fromJson(json);
  }

  // ── Profile ───────────────────────────────────────────────

  Future<AppUser> me() async {
    final json =
        await _client.get<Map<String, dynamic>>('/api/account/me', authenticated: true);
    return AppUser.fromJson(json);
  }

  Future<void> updateProfile({String? displayName, String? avatarUrl}) =>
      _client.patch<dynamic>(
        '/api/account/me',
        authenticated: true,
        body: {
          if (displayName != null) 'display_name': displayName,
          if (avatarUrl != null) 'avatar_url': avatarUrl,
        },
      );

  Future<void> deleteAccount() =>
      _client.delete<dynamic>('/api/account/me', authenticated: true);

  // ── Watchlist ─────────────────────────────────────────────

  Future<List<LibraryEntry>> watchlist() async {
    final json = await _client.get<List<dynamic>>('/api/account/watchlist',
        authenticated: true);
    return json
        .whereType<Map>()
        .map((e) => LibraryEntry.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<List<LibraryEntry>> searchWatchlist({
    String? provider,
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    final json = await _client.get<List<dynamic>>(
      '/api/account/watchlist/search',
      authenticated: true,
      query: {
        if (provider != null) 'provider': provider,
        if (search != null && search.isNotEmpty) 'search': search,
        'limit': limit,
        'offset': offset,
      },
    );
    return json
        .whereType<Map>()
        .map((e) => LibraryEntry.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// One page of the watchlist.
  ///
  /// The unpaged [watchlist] stays for callers that genuinely want the lot —
  /// the details screen tests membership against it. Both hit the same
  /// endpoint; omitting `limit` is what makes it answer unbounded.
  Future<PagedResponse<LibraryEntry>> watchlistPage({
    required int limit,
    required int offset,
  }) =>
      _client.getPaged<LibraryEntry>(
        '/api/account/watchlist',
        LibraryEntry.fromJson,
        authenticated: true,
        query: {'limit': limit, 'offset': offset},
      );

  Future<PagedResponse<LibraryEntry>> searchWatchlistPage({
    String? provider,
    String? search,
    required int limit,
    required int offset,
  }) =>
      _client.getPaged<LibraryEntry>(
        '/api/account/watchlist/search',
        LibraryEntry.fromJson,
        authenticated: true,
        query: {
          if (provider != null) 'provider': provider,
          if (search != null && search.isNotEmpty) 'search': search,
          'limit': limit,
          'offset': offset,
        },
      );

  Future<void> addToWatchlist(String provider, String showId) =>
      _client.post<dynamic>('/api/account/watchlist',
          authenticated: true, body: {'provider': provider, 'show_id': showId});

  Future<void> removeFromWatchlist(String provider, String showId) =>
      _client.delete<dynamic>(
          '/api/account/watchlist/${_seg(provider)}/${_seg(showId)}',
          authenticated: true);

  // ── Favorites ─────────────────────────────────────────────

  Future<List<LibraryEntry>> favorites() async {
    final json = await _client.get<List<dynamic>>('/api/account/favorites',
        authenticated: true);
    return json
        .whereType<Map>()
        .map((e) => LibraryEntry.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<List<LibraryEntry>> searchFavorites({
    String? provider,
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    final json = await _client.get<List<dynamic>>(
      '/api/account/favorites/search',
      authenticated: true,
      query: {
        if (provider != null) 'provider': provider,
        if (search != null && search.isNotEmpty) 'search': search,
        'limit': limit,
        'offset': offset,
      },
    );
    return json
        .whereType<Map>()
        .map((e) => LibraryEntry.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<PagedResponse<LibraryEntry>> favoritesPage({
    required int limit,
    required int offset,
  }) =>
      _client.getPaged<LibraryEntry>(
        '/api/account/favorites',
        LibraryEntry.fromJson,
        authenticated: true,
        query: {'limit': limit, 'offset': offset},
      );

  Future<PagedResponse<LibraryEntry>> searchFavoritesPage({
    String? provider,
    String? search,
    required int limit,
    required int offset,
  }) =>
      _client.getPaged<LibraryEntry>(
        '/api/account/favorites/search',
        LibraryEntry.fromJson,
        authenticated: true,
        query: {
          if (provider != null) 'provider': provider,
          if (search != null && search.isNotEmpty) 'search': search,
          'limit': limit,
          'offset': offset,
        },
      );

  Future<bool> isFavorite(String provider, String showId) async {
    final json = await _client.get<Map<String, dynamic>>(
        '/api/account/favorites/${_seg(provider)}/${_seg(showId)}',
        authenticated: true);
    return json['is_favorite'] == true || json['favorite'] == true;
  }

  Future<void> addFavorite(String provider, String showId) =>
      _client.post<dynamic>('/api/account/favorites',
          authenticated: true, body: {'provider': provider, 'show_id': showId});

  Future<void> removeFavorite(String provider, String showId) =>
      _client.delete<dynamic>(
          '/api/account/favorites/${_seg(provider)}/${_seg(showId)}',
          authenticated: true);

  // ── Ratings ───────────────────────────────────────────────

  Future<List<RatingEntry>> ratings() async {
    final json =
        await _client.get<List<dynamic>>('/api/account/ratings', authenticated: true);
    return json
        .whereType<Map>()
        .map((e) => RatingEntry.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<double?> rating(String provider, String showId) async {
    final json = await _client.get<Map<String, dynamic>>(
        '/api/account/ratings/${_seg(provider)}/${_seg(showId)}',
        authenticated: true);
    final value = json['rating'];
    if (value == null) return null;
    return (value as num?)?.toDouble() ?? double.tryParse(value.toString());
  }

  /// The backend only accepts whole numbers 1–10.
  Future<void> setRating(String provider, String showId, int rating) =>
      _client.put<dynamic>(
          '/api/account/ratings/${_seg(provider)}/${_seg(showId)}',
          authenticated: true,
          body: {'rating': rating});

  Future<void> deleteRating(String provider, String showId) =>
      _client.delete<dynamic>(
          '/api/account/ratings/${_seg(provider)}/${_seg(showId)}',
          authenticated: true);

  // ── History ───────────────────────────────────────────────

  Future<List<HistoryEntry>> history({int limit = 50, int offset = 0}) async {
    final json = await _client.get<List<dynamic>>(
      '/api/account/history',
      authenticated: true,
      query: {'limit': limit, 'offset': offset},
    );
    return json
        .whereType<Map>()
        .map((e) => HistoryEntry.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<List<HistoryEntry>> searchHistory({
    String? provider,
    bool? completed,
    DateTime? from,
    DateTime? to,
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    final json = await _client.get<List<dynamic>>(
      '/api/account/history/search',
      authenticated: true,
      query: {
        if (provider != null) 'provider': provider,
        if (completed != null) 'completed': completed ? 'true' : 'false',
        if (from != null) 'date_from': from.toIso8601String(),
        if (to != null) 'date_to': to.toIso8601String(),
        if (search != null && search.isNotEmpty) 'search': search,
        'limit': limit,
        'offset': offset,
      },
    );
    return json
        .whereType<Map>()
        .map((e) => HistoryEntry.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<PagedResponse<HistoryEntry>> historyPage({
    required int limit,
    required int offset,
  }) =>
      _client.getPaged<HistoryEntry>(
        '/api/account/history',
        HistoryEntry.fromJson,
        authenticated: true,
        query: {'limit': limit, 'offset': offset},
      );

  Future<PagedResponse<HistoryEntry>> searchHistoryPage({
    String? provider,
    bool? completed,
    DateTime? from,
    DateTime? to,
    String? search,
    required int limit,
    required int offset,
  }) =>
      _client.getPaged<HistoryEntry>(
        '/api/account/history/search',
        HistoryEntry.fromJson,
        authenticated: true,
        query: {
          if (provider != null) 'provider': provider,
          if (completed != null) 'completed': completed ? 'true' : 'false',
          if (from != null) 'date_from': from.toIso8601String(),
          if (to != null) 'date_to': to.toIso8601String(),
          if (search != null && search.isNotEmpty) 'search': search,
          'limit': limit,
          'offset': offset,
        },
      );

  Future<void> saveProgress({
    required String provider,
    required String showId,
    String? episodeId,
    String? episodeLabel,
    required int progressSeconds,
    int? durationSeconds,
    bool completed = false,
  }) =>
      _client.post<dynamic>(
        '/api/account/history',
        authenticated: true,
        body: {
          'provider': provider,
          'show_id': showId,
          if (episodeId != null) 'episode_id': episodeId,
          if (episodeLabel != null) 'episode_label': episodeLabel,
          'progress_seconds': progressSeconds,
          if (durationSeconds != null) 'duration_seconds': durationSeconds,
          'completed': completed,
        },
      );

  /// Resume point for a title/episode. Returns null when nothing is stored
  /// (the backend answers `{progress_seconds: null}` rather than 404).
  Future<HistoryEntry?> progress({
    required String provider,
    required String showId,
    String? episodeId,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/api/account/history/progress/',
      authenticated: true,
      body: {
        'provider': provider,
        'showId': showId,
        if (episodeId != null) 'episodeId': episodeId,
      },
    );
    if (json['progress_seconds'] == null) return null;
    return HistoryEntry.fromJson({
      'provider': provider,
      'show_id': showId,
      'episode_id': episodeId,
      ...json,
    });
  }

  Future<void> markComplete({
    required String provider,
    required String showId,
    required String episodeId,
  }) =>
      _client.put<dynamic>(
        '/api/account/history/complete',
        authenticated: true,
        body: {'provider': provider, 'show_id': showId, 'episode_id': episodeId},
      );

  Future<void> deleteHistoryEntry(String provider, String showId,
          {String? episodeId}) =>
      _client.delete<dynamic>(
        episodeId == null
            ? '/api/account/history/${_seg(provider)}/${_seg(showId)}'
            : '/api/account/history/${_seg(provider)}/${_seg(showId)}/${_seg(episodeId)}',
        authenticated: true,
      );

  Future<void> clearHistory() =>
      _client.delete<dynamic>('/api/account/history', authenticated: true);

  // ── Preferences ───────────────────────────────────────────

  /// Free-form key/value bag (`app_settings`-style per-user rows), used by
  /// the web account page for things like preferred subtitle language.
  Future<Map<String, dynamic>> preferences() async {
    final json = await _client.get<dynamic>('/api/account/preferences',
        authenticated: true);
    if (json is Map) return json.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  Future<void> setPreference(String key, Object value) => _client.put<dynamic>(
        '/api/account/preferences/${_seg(key)}',
        authenticated: true,
        body: {'value': value},
      );

  Future<void> deletePreference(String key) => _client.delete<dynamic>(
        '/api/account/preferences/${_seg(key)}',
        authenticated: true,
      );
}
