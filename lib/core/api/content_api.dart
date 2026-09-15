import '../models/models.dart';
import 'api_client.dart';
import 'json_mappers.dart';

/// The content pipeline: `routes/content.router.ts` + `provider.router.ts`.
/// None of it *requires* auth — browsing and playback work logged out, same as
/// the web frontend.
///
/// Both routers are nevertheless mounted under `optionalAuth` server-side, and
/// every call here sends the bearer token when there is one
/// (`optionalAuth: true`), because that is what the 18+ gates are resolved
/// from: `AdultService` reads `req.user`, and no user means both gates shut.
/// Sent anonymously, these endpoints answer perfectly successfully — with the
/// adult-only sources missing from the catalogue and every 18+ title filtered
/// out of every listing — so the failure is silent, and looks like the
/// preferences not working rather than like an auth problem.
class ContentApi {
  ContentApi(this._client);

  final ApiClient _client;

  /// The install this API talks to, so callers that have to build a URL the
  /// *server* will serve rather than one this client will fetch — the
  /// Chromecast proxy prefix, when `/api/cast-config` didn't answer — can do
  /// it without reaching for the Riverpod graph.
  String get baseUrl => _client.baseUrl;

  Map<String, dynamic> _providerQuery(String? provider,
          [Map<String, dynamic>? extra]) =>
      {
        if (provider != null && provider.isNotEmpty) 'provider': provider,
        ...?extra,
      };

  Future<List<Category>> home({String? provider}) async {
    final json = await _client.get<Map<String, dynamic>>('/api/home',
        query: _providerQuery(provider), optionalAuth: true);
    return (json['data'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => categoryFromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// An empty query is rejected by the backend (400), so callers must guard.
  Future<List<Object>> search(String query,
      {String? provider, int page = 1}) async {
    final json = await _client.get<Map<String, dynamic>>('/api/search',
        query: _providerQuery(provider, {'query': query, 'page': page}),
        optionalAuth: true);
    return (json['data'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => categoryItemFromJson(e.cast<String, dynamic>()))
        .whereType<Object>()
        .toList();
  }

  /// The provider's genre *catalogue* — `{id, name}` each, **no titles**. Use
  /// [genre] to browse one; the shows are a separate request.
  Future<List<Genre>> genres({String? provider}) async {
    final json = await _client.get<Map<String, dynamic>>('/api/genres',
        query: _providerQuery(provider), optionalAuth: true);
    return (json['data'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => genreFromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// One page of titles inside a genre (`GET /api/genres/:genreId`), on the
  /// returned `Genre`'s `shows`.
  ///
  /// Genre ids are the upstream site's own and mean nothing across providers,
  /// so this must be asked with the same provider the id came from. The route
  /// answers **400** if the provider has no genre filter and **403** if the
  /// genre is 18+ and the user's gate is closed; both arrive as an
  /// `ApiException` carrying the server's own wording.
  Future<Genre> genre(String genreId, {String? provider, int page = 1}) async {
    final json = await _client.get<Map<String, dynamic>>(
      '/api/genres/${Uri.encodeComponent(genreId)}',
      query: _providerQuery(provider, {'page': page}),
      optionalAuth: true,
    );
    final data = json['data'];
    return genreFromJson(
        data is Map ? data.cast<String, dynamic>() : const <String, dynamic>{});
  }

  /// Movie or TvShow — see [showFromJson] for how the two are told apart.
  Future<Show?> showDetails(String showId, {String? provider}) async {
    final json = await _client.get<Map<String, dynamic>>(
        '/api/shows/${Uri.encodeComponent(showId)}',
        query: _providerQuery(provider),
        optionalAuth: true);
    final data = json['data'];
    if (data is! Map) return null;
    return showFromJson(data.cast<String, dynamic>());
  }

  Future<List<Episode>> episodes(String seasonId, {String? provider}) async {
    final json = await _client.get<Map<String, dynamic>>(
        '/api/seasons/${Uri.encodeComponent(seasonId)}/episodes',
        query: _providerQuery(provider),
        optionalAuth: true);
    return (json['data'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => episodeFromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<List<VideoServer>> servers(String contentId,
      {String? provider, String contentType = 'episode'}) async {
    final json = await _client.get<Map<String, dynamic>>(
        '/api/episodes/${Uri.encodeComponent(contentId)}/servers',
        query: _providerQuery(provider, {'contentType': contentType}),
        optionalAuth: true);
    return (json['data'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => VideoServer.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// Resolves a playable stream. The resolved URL is signed and short-lived
  /// (minutes) — never cache the result, re-resolve per playback attempt.
  ///
  /// [fresh] sets `fresh=1`, which makes the server skip its own cached
  /// resolve (`PlatformHandler.resolveVideo`) and ask the extractor again.
  /// Only for a retry *after* a playback failure: without it the cache hands
  /// back the identical dead URL for the rest of its TTL, so every retry
  /// fails the same way. The web player passes it from `retryCurrentStream()`
  /// for exactly this reason.
  Future<PlaybackSource> resolveVideo(String contentId, VideoServer server,
      {String? provider,
      String contentType = 'episode',
      bool fresh = false}) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/api/episodes/${Uri.encodeComponent(contentId)}/video',
      query: _providerQuery(provider, {
        'contentType': contentType,
        if (fresh) 'fresh': '1',
      }),
      body: {'server': server.toJson()},
      optionalAuth: true,
    );
    final data = json['data'];
    if (data is! Map) {
      throw const ApiException('The server did not return a playable stream.');
    }
    return playbackSourceFromJson(data.cast<String, dynamic>());
  }

  /// Skip Intro/Recap/Credits/Preview timestamps for one title (TheIntroDB),
  /// via `GET /api/intro-segments` — a port of `loadIntroSegments()` in
  /// `../../../../web/public/scripts/watch.js`. Pure third-party metadata:
  /// unauthenticated and never dispatches through a provider, so `provider`/
  /// `showId` here are only the server's title-match cache key, not a
  /// playback target.
  ///
  /// `tmdbId`/`imdbId` are opportunistic — most providers here carry neither
  /// and the server transparently falls back to a fuzzy `title`(+`year`)
  /// match, which is why `title` is required. `season`/`episode` are
  /// required when [type] is `"tv"`; the server 400s without them.
  Future<IntroDbMedia?> introSegments({
    required String type,
    required String provider,
    required String showId,
    required String title,
    int? year,
    int? tmdbId,
    String? imdbId,
    int? season,
    int? episode,
    int? durationMs,
  }) async {
    final json = await _client.get<Map<String, dynamic>>(
      '/api/intro-segments',
      query: {
        'type': type,
        'provider': provider,
        'showId': showId,
        'title': title,
        if (year != null) 'year': year,
        if (tmdbId != null) 'tmdbId': tmdbId,
        if (imdbId != null && imdbId.isNotEmpty) 'imdbId': imdbId,
        if (season != null) 'season': season,
        if (episode != null) 'episode': episode,
        if (durationMs != null) 'durationMs': durationMs,
      },
      optionalAuth: true,
    );
    final data = json['data'];
    if (data is! Map) return null;
    return IntroDbMedia.fromJson(data.cast<String, dynamic>());
  }

  Future<CastConfig> castConfig() async {
    final json = await _client.get<Map<String, dynamic>>('/api/cast-config');
    return CastConfig.fromJson(json);
  }

  /// The sources this server offers the signed-in user, with their labels.
  ///
  /// `catalog` is the metadata-bearing field; installs older than it send only
  /// `providers` (bare names), which still have to render — hence the fallback
  /// per name rather than a table of names this build happens to know.
  Future<ProviderCatalog> providers() async {
    final json = await _client.get<Map<String, dynamic>>('/api/providers',
        optionalAuth: true);

    final catalog = json['catalog'];
    final names = (json['providers'] as List? ?? const [])
        .map((e) => e.toString())
        .where((name) => name.isNotEmpty);

    return ProviderCatalog(
      providers: catalog is List && catalog.isNotEmpty
          ? catalog
              .whereType<Map<String, dynamic>>()
              .map(providerInfoFromJson)
              .where((info) => info.name.isNotEmpty)
              .toList()
          : names.map(ProviderInfo.fallback).toList(),
      defaultProvider: (json['default'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['default'] as String).trim(),
    );
  }
}
