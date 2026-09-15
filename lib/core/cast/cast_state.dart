/// The receiver's `STATE` message, and the pieces of it the cast panel renders.
///
/// Mirrors §2 of `docs/protocol.md` in the `cast-receiver` repo. **Every field
/// is optional with a default, deliberately.** A Chromecast caches receiver
/// HTML hard, so this app will at some point be talking to a receiver older
/// than the contract it was built against — a `STATE` missing half these keys
/// is a supported input, not a malformed one. `fromJson` must never throw.
library;

/// One selectable track. `id` is the receiver's own track id: for subtitles it
/// is what the sender declared on the LOAD (1-based, 0 is never valid), for
/// audio it is assigned by CAF from the HLS manifest.
class CastTrack {
  const CastTrack({required this.id, required this.name, required this.lang});

  final int id;
  final String name;
  final String lang;

  /// What to show in a picker. The receiver already falls back from name to
  /// language, but an older one may not have.
  String get label {
    if (name.isNotEmpty) return name;
    if (lang.isNotEmpty) return lang;
    return 'Track $id';
  }

  static CastTrack? fromJson(dynamic json) {
    if (json is! Map) return null;
    final id = _int(json['id'], -1);
    if (id <= 0) return null;
    return CastTrack(
      id: id,
      name: _string(json['name']),
      lang: _string(json['lang']),
    );
  }
}

/// One active Skip Intro/Recap/Credits/Preview segment, mirroring
/// `STATE.skipSegment` (`docs/protocol.md` §5 in the `cast-receiver` repo).
/// `null` on [CastState] means no segment is active right now — a normal,
/// common state, not a missing one.
class CastSkipSegment {
  const CastSkipSegment({
    required this.type,
    required this.label,
    required this.endMs,
    required this.runsToEnd,
  });

  /// `intro`, `recap`, `credits` or `preview`. Left as a string, like
  /// [CastState.phase], so an unrecognized value from a newer receiver isn't
  /// an error here.
  final String type;

  /// What the receiver's own button says — "Skip Intro", etc. Shown as-is
  /// rather than re-derived from [type], so the two can't drift.
  final String label;

  final int endMs;
  final bool runsToEnd;

  static CastSkipSegment? fromJson(dynamic json) {
    if (json is! Map) return null;
    final type = json['type'];
    final label = json['label'];
    if (type is! String || label is! String) return null;
    return CastSkipSegment(
      type: type,
      label: label,
      endMs: _int(json['endMs'], 0),
      runsToEnd: json['runsToEnd'] == true,
    );
  }
}

class CastState {
  const CastState({
    this.phase = 'IDLE',
    this.showTitle = '',
    this.contentType = '',
    this.episodeId = '',
    this.episodeIndex = -1,
    this.episodeLabel = '',
    this.episodeTitle = '',
    this.positionSeconds = 0,
    this.durationSeconds = 0,
    this.playing = false,
    this.autoplayNext = true,
    this.subtitleTracks = const [],
    this.activeTrackId = -1,
    this.audioTracks = const [],
    this.activeAudioTrackId = -1,
    this.skipSegment,
  });

  /// `IDLE`, `LOADING`, `RESOLVING`, `PLAYING`, `PAUSED`, `UPNEXT`,
  /// `RECOVERING` or `ERROR`. Left as a string on purpose: an unknown phase
  /// from a newer receiver must not be an error here.
  final String phase;

  final String showTitle;
  final String contentType;
  final String episodeId;
  final int episodeIndex;
  final String episodeLabel;
  final String episodeTitle;
  final int positionSeconds;
  final int durationSeconds;
  final bool playing;
  final bool autoplayNext;

  final List<CastTrack> subtitleTracks;

  /// The active text track, or -1 for none.
  final int activeTrackId;

  /// **Empty is a normal answer, not an error.** Audio renditions live inside
  /// the HLS manifest and are read back from CAF's `AudioTracksManager`, but
  /// playback on this receiver is the device's native pipeline — whether CAF's
  /// JS layer can enumerate them is a property of the device and the stream.
  /// The panel hides its language control rather than showing an empty picker.
  final List<CastTrack> audioTracks;

  final int activeAudioTrackId;

  /// The currently active Skip Intro/Recap/Credits/Preview segment, or
  /// `null` when none is active. See [CastSkipSegment].
  final CastSkipSegment? skipSegment;

  Duration get position => Duration(seconds: positionSeconds);
  Duration get duration => Duration(seconds: durationSeconds);

  bool get isEpisode => contentType == 'episode';

  /// True while the receiver is between streams — resolving a URL, recovering
  /// from an expired one, or loading. The panel greys out transport controls.
  bool get isBusy =>
      phase == 'LOADING' || phase == 'RESOLVING' || phase == 'RECOVERING';

  static CastState fromJson(Map<String, dynamic> json) {
    return CastState(
      phase: _string(json['phase'], 'IDLE'),
      showTitle: _string(json['showTitle']),
      contentType: _string(json['contentType']),
      episodeId: _string(json['episodeId']),
      episodeIndex: _int(json['episodeIndex'], -1),
      episodeLabel: _string(json['episodeLabel']),
      episodeTitle: _string(json['episodeTitle']),
      positionSeconds: _int(json['positionSeconds'], 0),
      durationSeconds: _int(json['durationSeconds'], 0),
      playing: json['playing'] == true,
      // Only an explicit false turns autoplay off — same rule the receiver
      // applies to SET_AUTOPLAY, so a missing field doesn't flip the switch.
      autoplayNext: json['autoplayNext'] != false,
      subtitleTracks: _tracks(json['subtitleTracks']),
      activeTrackId: _int(json['activeTrackId'], -1),
      audioTracks: _tracks(json['audioTracks']),
      activeAudioTrackId: _int(json['activeAudioTrackId'], -1),
      skipSegment: CastSkipSegment.fromJson(json['skipSegment']),
    );
  }

  static List<CastTrack> _tracks(dynamic json) {
    if (json is! List) return const [];
    return [
      for (final entry in json)
        if (CastTrack.fromJson(entry) case final track?) track,
    ];
  }
}

/// The receiver advanced to another episode by itself. Carries the identity
/// watch history has to follow — the receiver keeps playing after this app is
/// backgrounded, so its episode is the true one, not the one that was cast.
class CastEpisodeChanged {
  const CastEpisodeChanged({
    required this.episodeId,
    required this.episodeIndex,
    required this.episodeLabel,
    required this.title,
  });

  final String episodeId;
  final int episodeIndex;
  final String episodeLabel;
  final String title;

  static CastEpisodeChanged fromJson(Map<String, dynamic> json) {
    return CastEpisodeChanged(
      episodeId: _string(json['episodeId']),
      episodeIndex: _int(json['episodeIndex'], -1),
      episodeLabel: _string(json['episodeLabel']),
      title: _string(json['title']),
    );
  }
}

String _string(dynamic value, [String fallback = '']) {
  if (value is String) return value;
  return fallback;
}

int _int(dynamic value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}
