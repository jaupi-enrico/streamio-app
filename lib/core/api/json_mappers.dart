/// Deserializers for the content endpoints.
///
/// The backend responds with `JSON.stringify`d instances of the classes in
/// `core/models/*.ts`, and the Dart classes in `core/models/` already mirror
/// those field-for-field — so this file is the one place that knows the wire
/// format, and the models stay serialization-agnostic (they have no
/// `fromJson` of their own, matching how they were written).
///
/// Two shapes need care:
///  * `Date` fields serialize to ISO-8601 strings (`released`, `watchedDate`).
///  * `/api/shows/:id` returns either a Movie or a TvShow with no explicit
///    discriminator, so [showFromJson] keys off the presence of `seasons`.
library;

import 'dart:convert';

import '../models/models.dart';

String? _str(dynamic value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

int? _int(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}

double? _double(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

DateTime? _date(dynamic value) {
  final text = _str(value);
  return text == null ? null : DateTime.tryParse(text);
}

/// ISO-8601 date the model constructors accept (they call `DateTime.parse`
/// on it, so an unparseable value has to become null here instead).
String? _dateStr(dynamic value) => _date(value)?.toIso8601String();

List<Map<String, dynamic>> _objects(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
}

Genre genreFromJson(Map<String, dynamic> json) => Genre(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      shows: _objects(json['shows']).map(showFromJson).whereType<Show>().toList(),
    );

People peopleFromJson(Map<String, dynamic> json) => People(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      image: _str(json['image']),
      biography: _str(json['biography']),
      placeOfBirth: _str(json['placeOfBirth']),
      birthdayStr: _dateStr(json['birthday']),
      deathdayStr: _dateStr(json['deathday']),
      filmography:
          _objects(json['filmography']).map(showFromJson).whereType<Show>().toList(),
    );

WatchHistory? _watchHistoryFromJson(dynamic value) {
  if (value is! Map) return null;
  final json = value.cast<String, dynamic>();
  return WatchHistory(
    lastEngagementTimeUtcMillis: _int(json['lastEngagementTimeUtcMillis']) ?? 0,
    lastPlaybackPositionMillis: _int(json['lastPlaybackPositionMillis']) ?? 0,
    durationMillis: _int(json['durationMillis']) ?? 0,
  );
}

Movie movieFromJson(Map<String, dynamic> json) => Movie(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      overview: _str(json['overview']),
      releasedStr: _dateStr(json['released']),
      runtime: _int(json['runtime']),
      trailer: _str(json['trailer']),
      quality: _str(json['quality']),
      rating: _double(json['rating']),
      poster: _str(json['poster']),
      banner: _str(json['banner']),
      imdbId: _str(json['imdbId']),
      providerName: _str(json['providerName']),
      genres: _objects(json['genres']).map(genreFromJson).toList(),
      directors: _objects(json['directors']).map(peopleFromJson).toList(),
      cast: _objects(json['cast']).map(peopleFromJson).toList(),
      recommendations: _objects(json['recommendations'])
          .map(showFromJson)
          .whereType<Show>()
          .toList(),
      isFavorite: json['isFavorite'] == true,
      favoritedAtMillis: _int(json['favoritedAtMillis']),
      isWatched: json['isWatched'] == true,
      watchedDate: _date(json['watchedDate']),
      watchHistory: _watchHistoryFromJson(json['watchHistory']),
    );

Episode episodeFromJson(Map<String, dynamic> json) => Episode(
      id: json['id']?.toString() ?? '',
      number: _int(json['number']) ?? 0,
      title: _str(json['title']),
      releasedStr: _dateStr(json['released']),
      poster: _str(json['poster']),
      overview: _str(json['overview']),
      isWatched: json['isWatched'] == true,
      watchedDate: _date(json['watchedDate']),
      watchHistory: _watchHistoryFromJson(json['watchHistory']),
    );

/// `tvShow` is deliberately not followed: the backend's Season carries a
/// back-reference to its parent show, and chasing it would recurse (the show
/// holds the seasons that hold the show). `TvShow.episodeToWatch` back-fills
/// both links itself, exactly like the TS getter.
Season seasonFromJson(Map<String, dynamic> json) => Season(
      id: json['id']?.toString() ?? '',
      number: _int(json['number']) ?? 0,
      title: _str(json['title']),
      poster: _str(json['poster']),
      episodes: _objects(json['episodes']).map(episodeFromJson).toList(),
    );

TvShow tvShowFromJson(Map<String, dynamic> json) => TvShow(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      overview: _str(json['overview']),
      releasedStr: _dateStr(json['released']),
      runtime: _int(json['runtime']),
      trailer: _str(json['trailer']),
      quality: _str(json['quality']),
      rating: _double(json['rating']),
      poster: _str(json['poster']),
      banner: _str(json['banner']),
      imdbId: _str(json['imdbId']),
      providerName: _str(json['providerName']),
      seasons: _objects(json['seasons']).map(seasonFromJson).toList(),
      genres: _objects(json['genres']).map(genreFromJson).toList(),
      directors: _objects(json['directors']).map(peopleFromJson).toList(),
      cast: _objects(json['cast']).map(peopleFromJson).toList(),
      recommendations: _objects(json['recommendations'])
          .map(showFromJson)
          .whereType<Show>()
          .toList(),
      isFavorite: json['isFavorite'] == true,
      favoritedAtMillis: _int(json['favoritedAtMillis']),
      isWatching: json['isWatching'] != false,
    );

/// Movie or TvShow, discriminated on `seasons` (only TvShow has it). The
/// backend also carries an `itemType` adapter field, but it's assigned by
/// `AppAdapter` and is absent on plenty of paths, so it can't be relied on.
Show? showFromJson(Map<String, dynamic> json) {
  if (json.isEmpty) return null;
  if (json.containsKey('seasons')) return tvShowFromJson(json);
  return movieFromJson(json);
}

/// Anything that can appear inside a `Category.list`: Movie/TvShow rails on
/// the home page, but also Genre and People rows.
Object? categoryItemFromJson(Map<String, dynamic> json) {
  if (json.containsKey('seasons')) return tvShowFromJson(json);
  if (json.containsKey('filmography') || json.containsKey('biography')) {
    return peopleFromJson(json);
  }
  // A Genre is the only remaining shape with a name but no title.
  if (!json.containsKey('title') && json.containsKey('name')) {
    return genreFromJson(json);
  }
  return movieFromJson(json);
}

Category categoryFromJson(Map<String, dynamic> json) => Category(
      json['name']?.toString() ?? '',
      list: _objects(json['list'])
          .map(categoryItemFromJson)
          .whereType<Object>()
          .toList(),
    );

Subtitle subtitleFromJson(Map<String, dynamic> json) => Subtitle(
      label: (json['label'] ?? json['lang'] ?? 'Subtitle').toString(),
      file: (json['file'] ?? json['url'] ?? json['src'] ?? '').toString(),
      // `default` is a reserved word in Dart but a plain key on the wire.
      isDefault: json['default'] == true || json['isDefault'] == true,
      initialDefault: json['initialDefault'] == true,
    );

/// The resolved-stream payload from `POST /api/episodes/:id/video`.
///
/// The backend's `Video` always sets `playlistUrl` to the raw signed HLS URL
/// and `source` to a `data:` URL wrapping the same manifest, so preferring
/// `playlistUrl` mirrors `buildPlayableUrl()` in `public/scripts/watch.js`.
/// A `data:`/inline manifest is unwrapped into [PlaybackSource.inlineManifest]
/// because media_kit can't open a `data:` URI — the caller materializes it.
PlaybackSource playbackSourceFromJson(Map<String, dynamic> json) {
  final headers = <String, String>{};
  final rawHeaders = json['headers'];
  if (rawHeaders is Map) {
    rawHeaders.forEach((key, value) {
      if (value != null) headers[key.toString()] = value.toString();
    });
  }

  final subtitles =
      _objects(json['subtitles']).map(subtitleFromJson).toList(growable: false);

  final playlistUrl = _str(json['playlistUrl']);
  final source = _str(json['source']) ?? _str(json['url']);
  final candidate = playlistUrl ?? source ?? '';

  String url = candidate;
  String? inlineManifest;

  if (candidate.startsWith('#EXTM3U')) {
    inlineManifest = candidate;
    url = '';
  } else if (candidate.startsWith('data:')) {
    final manifest = decodeManifestSource(candidate);
    if (manifest.startsWith('#EXTM3U')) {
      inlineManifest = manifest;
      url = '';
    } else {
      url = manifest;
    }
  }

  // A raw playlist URL wins, but if it was inline-only, keep the decoded
  // manifest and let the player materialize it to a temp file.
  return PlaybackSource(
    url: url,
    inlineManifest: inlineManifest,
    headers: headers,
    subtitles: subtitles,
    type: _str(json['type']) ?? 'hls',
  );
}

/// Port of `decodeManifestSource()` in `public/scripts/watch.js`: unwraps a
/// `data:` URL (base64 or percent-encoded) into its manifest text.
String decodeManifestSource(String source) {
  if (source.isEmpty) return '';
  if (!source.startsWith('data:')) return source.trim();

  final commaIndex = source.indexOf(',');
  if (commaIndex == -1) return '';

  final meta = source.substring(0, commaIndex);
  final payload = source.substring(commaIndex + 1);

  if (meta.contains(';base64')) {
    try {
      return String.fromCharCodes(_base64Decode(payload));
    } catch (_) {
      return '';
    }
  }
  return Uri.decodeComponent(payload);
}

List<int> _base64Decode(String input) {
  // Tolerate the unpadded/URL-safe variants an extractor might emit.
  var normalized = input.replaceAll('-', '+').replaceAll('_', '/');
  final remainder = normalized.length % 4;
  if (remainder != 0) normalized = normalized.padRight(normalized.length + (4 - remainder), '=');
  return base64.decode(normalized);
}
