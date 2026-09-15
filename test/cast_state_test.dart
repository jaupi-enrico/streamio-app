import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/core/cast/cast_state.dart';

/// A `STATE` message as the current receiver sends it — see §2 of
/// `docs/protocol.md` in the `cast-receiver` repo.
Map<String, dynamic> state({
  Object? audioTracks = const [
    {'id': 1, 'name': 'Italiano', 'lang': 'it'},
    {'id': 2, 'name': 'English', 'lang': 'en'},
  ],
}) =>
    {
      'type': 'STATE',
      'phase': 'PLAYING',
      'provider': 'filmhub',
      'showId': 'show-1',
      'showTitle': 'A Show',
      'contentType': 'episode',
      'episodeId': 'ep-3',
      'episodeIndex': 2,
      'episodeLabel': 'S01E03',
      'episodeTitle': 'Third',
      'positionSeconds': 615,
      'durationSeconds': 2700,
      'playing': true,
      'autoplayNext': true,
      'subtitleTracks': [
        {'id': 1, 'name': 'Italiano', 'lang': 'it'},
      ],
      'activeTrackId': 1,
      if (audioTracks != null) 'audioTracks': audioTracks,
      'activeAudioTrackId': 2,
    };

void main() {
  group('CastState.fromJson', () {
    test('reads a full STATE', () {
      final parsed = CastState.fromJson(state());

      expect(parsed.phase, 'PLAYING');
      expect(parsed.showTitle, 'A Show');
      expect(parsed.isEpisode, isTrue);
      expect(parsed.episodeIndex, 2);
      expect(parsed.position, const Duration(seconds: 615));
      expect(parsed.duration, const Duration(seconds: 2700));
      expect(parsed.playing, isTrue);
      expect(parsed.subtitleTracks.single.label, 'Italiano');
      expect(parsed.activeTrackId, 1);
      expect(parsed.audioTracks.map((t) => t.lang), ['it', 'en']);
      expect(parsed.activeAudioTrackId, 2);
    });

    // A Chromecast caches receiver HTML hard, so this app will at some point
    // be talking to a receiver built before `audioTracks` existed. That must
    // read as "this stream has one language", not as an error.
    test('an older receiver sends no audioTracks', () {
      final parsed = CastState.fromJson(state(audioTracks: null));

      expect(parsed.audioTracks, isEmpty);
      expect(parsed.showTitle, 'A Show');
      expect(parsed.subtitleTracks, hasLength(1));
    });

    test('an empty message parses to defaults rather than throwing', () {
      final parsed = CastState.fromJson(const {});

      expect(parsed.phase, 'IDLE');
      expect(parsed.playing, isFalse);
      expect(parsed.episodeIndex, -1);
      expect(parsed.activeTrackId, -1);
      expect(parsed.activeAudioTrackId, -1);
      expect(parsed.audioTracks, isEmpty);
      expect(parsed.subtitleTracks, isEmpty);
      // Only an explicit false turns autoplay off — the same rule the receiver
      // applies to SET_AUTOPLAY, so a missing field must not flip the switch.
      expect(parsed.autoplayNext, isTrue);
    });

    test('autoplayNext is off only when the receiver says so', () {
      expect(CastState.fromJson({'autoplayNext': false}).autoplayNext, isFalse);
    });

    test('junk in the track lists is dropped, not fatal', () {
      final parsed = CastState.fromJson({
        'subtitleTracks': 'not a list',
        'audioTracks': [
          {'id': 1, 'name': 'Italiano', 'lang': 'it'},
          // 0 is never a valid track id, and neither of these is a track.
          {'id': 0, 'name': 'Bogus', 'lang': 'xx'},
          'nonsense',
          null,
        ],
      });

      expect(parsed.subtitleTracks, isEmpty);
      expect(parsed.audioTracks.single.id, 1);
    });

    test('a track with neither name nor language still labels', () {
      final parsed = CastState.fromJson({
        'audioTracks': [
          {'id': 4},
        ],
      });

      expect(parsed.audioTracks.single.label, 'Track 4');
    });

    test('numeric fields survive being sent as floats or strings', () {
      // The receiver runs its numbers through num(), and JSON has one number
      // type — a whole-second position can arrive as 615.0.
      final parsed = CastState.fromJson({
        'positionSeconds': 615.0,
        'durationSeconds': '2700',
      });

      expect(parsed.position, const Duration(seconds: 615));
      expect(parsed.duration, const Duration(seconds: 2700));
    });

    test('an unknown phase from a newer receiver is not an error', () {
      final parsed = CastState.fromJson({'phase': 'SOMETHING_NEW'});

      expect(parsed.phase, 'SOMETHING_NEW');
      expect(parsed.isBusy, isFalse);
    });

    test('isBusy covers the states with no stream to control', () {
      for (final phase in ['LOADING', 'RESOLVING', 'RECOVERING']) {
        expect(CastState.fromJson({'phase': phase}).isBusy, isTrue,
            reason: phase);
      }
      for (final phase in ['PLAYING', 'PAUSED', 'UPNEXT', 'IDLE']) {
        expect(CastState.fromJson({'phase': phase}).isBusy, isFalse,
            reason: phase);
      }
    });
  });

  group('CastEpisodeChanged.fromJson', () {
    test('reads the identity watch history has to follow', () {
      final parsed = CastEpisodeChanged.fromJson(const {
        'type': 'EPISODE_CHANGED',
        'episodeId': 'ep-4',
        'episodeIndex': 3,
        'episodeLabel': 'S01E04',
        'title': 'Fourth',
      });

      expect(parsed.episodeId, 'ep-4');
      expect(parsed.episodeIndex, 3);
      expect(parsed.episodeLabel, 'S01E04');
      expect(parsed.title, 'Fourth');
    });

    test('an empty message parses to defaults', () {
      final parsed = CastEpisodeChanged.fromJson(const {});

      expect(parsed.episodeId, isEmpty);
      expect(parsed.episodeIndex, -1);
    });
  });
}
