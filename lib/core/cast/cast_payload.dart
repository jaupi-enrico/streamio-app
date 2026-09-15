import '../models/models.dart';

/// The `customData` blob the Streamio CAF receiver reads on every LOAD.
///
/// This is a **cross-project contract**: the same shape is built by
/// `buildCastCustomData()` in `../web/public/scripts/watch.js`, and consumed by
/// the receiver, which lives in its own repo (`cast-receiver`) and is
/// deployed as a static page independently of both. It is what lets it draw a
/// real UI (artwork, title, S/E), advance to the next episode **by itself**
/// after this app is backgrounded or killed, and re-resolve a stream whose
/// signed URL has expired mid-playback.
///
/// Every field is optional on the receiver side, which is deliberate: it
/// degrades field by field rather than requiring the three projects to ship
/// together. Sending nothing at all is a supported (and, until now, the only)
/// mode — it falls back to the media metadata and simply loses autoplay-next
/// and stream recovery. So adding a field here never needs a coordinated
/// release; renaming or removing one does.
///
/// The canonical description of the contract is `docs/protocol.md` in the
/// receiver's repo — it is the one implementation both senders must satisfy.
class CastPayload {
  const CastPayload({
    required this.apiBase,
    required this.castProxyBase,
    required this.provider,
    required this.contentType,
    this.showId = '',
    this.tmdbId,
    this.imdbId = '',
    this.year,
    this.showTitle = '',
    this.description = '',
    this.poster = '',
    this.backdrop = '',
    this.seasonId = '',
    this.seasonNumber,
    this.episodeId = '',
    this.episodeNumber,
    this.episodeTitle = '',
    this.episodeLabel = '',
    this.durationSeconds,
    this.serverName = '',
    this.serverIndex = 0,
    this.subtitles = const [],
    this.episodes = const [],
    this.episodeIndex = -1,
    this.autoplayNext = true,
    this.upNextSeconds = 20,
  });

  /// Contract version. Bumped only on a breaking change to the shape.
  static const int version = 1;

  /// Absolute base the receiver calls `/api/...` on. It must answer **without
  /// a redirect** — CAF refuses to follow a cross-origin redirect for an HLS
  /// manifest, and a 302'd POST is not replayed as a POST, which would break
  /// both next-episode resolution and stream recovery.
  final String apiBase;

  /// e.g. `https://host/api/cast-proxy?url=` — already ends in `url=`.
  final String castProxyBase;

  final String provider;

  /// `episode` or `movie`.
  final String contentType;

  final String showId;

  /// Hints for the receiver's own Skip Intro/Recap/Credits/Preview lookup
  /// (`docs/protocol.md` §5 in the receiver's repo). All optional — the
  /// receiver derives [tmdbId] from [showId] itself when absent (the same
  /// `movie-<id>`/`tv-<id>` regex `_resolveIntroDbIds()` runs locally) and
  /// otherwise falls back to a title-only fuzzy match, same as
  /// `loadIntroSegments()` in `../../../../web/public/scripts/watch.js`.
  final int? tmdbId;
  final String imdbId;
  final int? year;

  final String showTitle;
  final String description;
  final String poster;
  final String backdrop;

  final String seasonId;
  final int? seasonNumber;
  final String episodeId;
  final int? episodeNumber;
  final String episodeTitle;

  /// e.g. `S2E5`.
  final String episodeLabel;

  final int? durationSeconds;

  /// Which server resolved this stream, so the receiver picks the same one for
  /// the next episode instead of falling back to the first in the list.
  final String serverName;
  final int serverIndex;

  /// Already proxy-wrapped — see [CastSubtitle.url].
  final List<CastSubtitle> subtitles;

  /// The show's episodes in play order. Ids only (~40 bytes each), so even a
  /// 300-episode show stays well inside the Cast message budget. Purely an
  /// optimisation: given an empty list the receiver fetches the episodes
  /// itself from `/api/shows/:id` + `/api/seasons/:id/episodes`.
  final List<CastEpisodeRef> episodes;

  /// Index of the episode being cast within [episodes]; -1 when unknown.
  final int episodeIndex;

  final bool autoplayNext;

  /// How long before the end the receiver shows its "Up next" card.
  final int upNextSeconds;

  Map<String, dynamic> toJson() => {
        'v': version,
        'apiBase': apiBase,
        'castProxyBase': castProxyBase,
        'provider': provider,
        'contentType': contentType,
        'showId': showId,
        'tmdbId': tmdbId,
        'imdbId': imdbId,
        'year': year,
        'showTitle': showTitle,
        'description': description,
        'poster': poster,
        'backdrop': backdrop,
        'seasonId': seasonId,
        'seasonNumber': seasonNumber,
        'episodeId': episodeId,
        'episodeNumber': episodeNumber,
        'episodeTitle': episodeTitle,
        'episodeLabel': episodeLabel,
        'durationSeconds': durationSeconds,
        'serverName': serverName,
        'serverIndex': serverIndex,
        'subtitles': [for (final s in subtitles) s.toJson()],
        'episodes': [for (final e in episodes) e.toJson()],
        'episodeIndex': episodeIndex,
        'autoplayNext': autoplayNext,
        'upNextSeconds': upNextSeconds,
      };
}

/// One entry of [CastPayload.episodes]. Keys are single letters because this
/// list is the only part of the payload that scales with the show's length.
class CastEpisodeRef {
  const CastEpisodeRef({
    required this.id,
    this.seasonId = '',
    this.seasonNumber,
    this.episodeNumber,
    this.title = '',
  });

  factory CastEpisodeRef.fromEpisode(Episode episode) => CastEpisodeRef(
        id: episode.id,
        seasonId: episode.season?.id ?? '',
        seasonNumber: episode.season?.number,
        episodeNumber: episode.number,
        title: episode.title ?? '',
      );

  final String id;
  final String seasonId;
  final int? seasonNumber;
  final int? episodeNumber;
  final String title;

  Map<String, dynamic> toJson() => {
        'id': id,
        'sid': seasonId,
        's': seasonNumber,
        'e': episodeNumber,
        't': title,
      };
}

/// A subtitle track as the receiver expects it.
class CastSubtitle {
  const CastSubtitle({
    required this.label,
    required this.lang,
    required this.url,
    this.isDefault = false,
  });

  final String label;
  final String lang;

  /// **Must already be proxied.** Upstream VTT is frequently plain `http`
  /// (mixed content against an https receiver) and carries no CORS header;
  /// either one makes CAF drop the track without a word.
  final String url;

  final bool isDefault;

  Map<String, dynamic> toJson() => {
        'label': label,
        'lang': lang,
        'url': url,
        'default': isDefault,
      };
}
