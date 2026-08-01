import '../models/models.dart';
import 'api_client.dart';
import 'json_mappers.dart';

/// The content pipeline: `routes/content.router.ts` + `provider.router.ts`.
/// None of it requires auth — browsing and playback work logged out, same as
/// the web frontend.
class ContentApi {
  ContentApi(this._client);

  final ApiClient _client;

  Map<String, dynamic> _providerQuery(String? provider,
          [Map<String, dynamic>? extra]) =>
      {
        if (provider != null && provider.isNotEmpty) 'provider': provider,
        ...?extra,
      };

  Future<List<Category>> home({String? provider}) async {
    final json = await _client.get<Map<String, dynamic>>('/api/home',
        query: _providerQuery(provider));
    return (json['data'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => categoryFromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// An empty query is rejected by the backend (400), so callers must guard.
  Future<List<Object>> search(String query,
      {String? provider, int page = 1}) async {
    final json = await _client.get<Map<String, dynamic>>('/api/search',
        query: _providerQuery(provider, {'query': query, 'page': page}));
    return (json['data'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => categoryItemFromJson(e.cast<String, dynamic>()))
        .whereType<Object>()
        .toList();
  }

  Future<List<Genre>> genres({String? provider}) async {
    final json = await _client.get<Map<String, dynamic>>('/api/genres',
        query: _providerQuery(provider));
    return (json['data'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => genreFromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// Movie or TvShow — see [showFromJson] for how the two are told apart.
  Future<Show?> showDetails(String showId, {String? provider}) async {
    final json = await _client.get<Map<String, dynamic>>(
        '/api/shows/${Uri.encodeComponent(showId)}',
        query: _providerQuery(provider));
    final data = json['data'];
    if (data is! Map) return null;
    return showFromJson(data.cast<String, dynamic>());
  }

  Future<List<Episode>> episodes(String seasonId, {String? provider}) async {
    final json = await _client.get<Map<String, dynamic>>(
        '/api/seasons/${Uri.encodeComponent(seasonId)}/episodes',
        query: _providerQuery(provider));
    return (json['data'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => episodeFromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<List<VideoServer>> servers(String contentId,
      {String? provider, String contentType = 'episode'}) async {
    final json = await _client.get<Map<String, dynamic>>(
        '/api/episodes/${Uri.encodeComponent(contentId)}/servers',
        query: _providerQuery(provider, {'contentType': contentType}));
    return (json['data'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => VideoServer.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// Resolves a playable stream. The resolved URL is signed and short-lived
  /// (minutes) — never cache the result, re-resolve per playback attempt.
  Future<PlaybackSource> resolveVideo(String contentId, VideoServer server,
      {String? provider, String contentType = 'episode'}) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/api/episodes/${Uri.encodeComponent(contentId)}/video',
      query: _providerQuery(provider, {'contentType': contentType}),
      body: {'server': server.toJson()},
    );
    final data = json['data'];
    if (data is! Map) {
      throw const ApiException('The server did not return a playable stream.');
    }
    return playbackSourceFromJson(data.cast<String, dynamic>());
  }

  Future<CastConfig> castConfig() async {
    final json = await _client.get<Map<String, dynamic>>('/api/cast-config');
    return CastConfig.fromJson(json);
  }

  Future<List<String>> providers() async {
    final json = await _client.get<Map<String, dynamic>>('/api/providers');
    return (json['providers'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
  }
}
