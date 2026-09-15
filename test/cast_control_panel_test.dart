import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/entities.dart';
import 'package:flutter_chrome_cast/enums/connection_state.dart';
import 'package:flutter_chrome_cast/enums/player_state.dart';
import 'package:flutter_chrome_cast/enums/repeat_mode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/core/api/api_client.dart';
import 'package:streamio/core/api/content_api.dart';
import 'package:streamio/core/cast/cast_service.dart';
import 'package:streamio/features/watch/cast_control_panel.dart';
import 'package:streamio/features/watch/now_casting_button.dart';
import 'package:streamio/state/cast_providers.dart';

/// The cast panel's transport controls, which are the half of it that has to
/// keep working against any receiver.
///
/// Both cases here were live bugs: "+10s" seeking to 0:10 from anywhere in the
/// film (the plugin drops `relative` on Android, so the offset was received as
/// an absolute position), and a progress bar whose thumb could not be moved
/// because `onChanged` threw the dragged value away and re-read the position
/// stream.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingCastService cast;

  Widget panel({
    CastState? state,
    required Duration position,
    GoggleCastMediaStatus? status,
  }) {
    return ProviderScope(
      overrides: [
        castServiceProvider.overrideWithValue(cast),
        castStateProvider.overrideWith((ref) => Stream.value(state)),
        castPositionProvider.overrideWith((ref) => Stream.value(position)),
        castMediaStatusProvider.overrideWith((ref) => Stream.value(status)),
        castSessionProvider.overrideWith((ref) => Stream.value(null)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: CastControlPanel(
            onCastHere: () async {},
            onChooseDevice: () {},
          ),
        ),
      ),
    );
  }

  const playing = CastState(
    phase: 'PLAYING',
    showTitle: 'A Film',
    contentType: 'movie',
    durationSeconds: 7200,
    playing: true,
  );

  setUp(() => cast = _RecordingCastService());

  testWidgets('forward 10 skips from where playback is, not to 0:10',
      (tester) async {
    await tester.pumpWidget(
      panel(state: playing, position: const Duration(minutes: 42)),
    );
    // Two frames: the session, the STATE and the position arrive on separate
    // streams, and one frame only catches the first of them.
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.forward_10));
    await tester.pump();

    expect(cast.seeks, [const Duration(minutes: 42, seconds: 10)]);
  });

  testWidgets('back 10 rewinds by ten seconds rather than to the start',
      (tester) async {
    await tester.pumpWidget(
      panel(state: playing, position: const Duration(minutes: 42)),
    );
    // Two frames: the session, the STATE and the position arrive on separate
    // streams, and one frame only catches the first of them.
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.replay_10));
    await tester.pump();

    expect(cast.seeks, [const Duration(minutes: 41, seconds: 50)]);
  });

  testWidgets('a second tap offsets from the first, not from the stale tick',
      (tester) async {
    await tester.pumpWidget(
      panel(state: playing, position: const Duration(minutes: 42)),
    );
    // Two frames: the session, the STATE and the position arrive on separate
    // streams, and one frame only catches the first of them.
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.forward_10));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.forward_10));
    await tester.pump();

    expect(cast.seeks.last, const Duration(minutes: 42, seconds: 20));
    // …and the bar shows the target while the transport still reports 42:00,
    // rather than snapping back to it.
    expect(find.text('42:20'), findsOneWidget);
  });

  testWidgets('dragging the bar moves the thumb and seeks where it was left',
      (tester) async {
    await tester.pumpWidget(
      panel(state: playing, position: const Duration(minutes: 42)),
    );
    // Two frames: the session, the STATE and the position arrive on separate
    // streams, and one frame only catches the first of them.
    await tester.pump();
    await tester.pump();

    final slider = find.byType(Slider).first;
    final width = tester.getSize(slider).width;
    // The drag grabs the track at its centre (an hour in) and carries it a
    // quarter of the way to the right — nowhere near the 42:00 the position
    // stream reports, which is the point: the old bar could only ever seek to
    // the value that stream held.
    await tester.drag(slider, Offset(width / 4, 0));
    await tester.pump();

    expect(cast.seeks, hasLength(1));
    expect(cast.seeks.single, greaterThan(const Duration(minutes: 75)));
    expect(cast.seeks.single, lessThan(const Duration(hours: 2)));
  });

  group('with no STATE from the receiver', () {
    // The receiver only answers on the standard Cast channel — an older build
    // cached on the device, a control channel that never attached. On Android
    // that leaves *nothing* carrying a duration: the plugin's bridge drops the
    // one passed at load (it never calls `setStreamDuration`) and returns a
    // media status with no `mediaInformation`. The panel then had a dead
    // progress bar reading `00:00` over a stream that was playing.
    final playingStatus = GoggleCastMediaStatus(
      mediaSessionID: 1,
      playerState: CastMediaPlayerState.playing,
      playbackRate: 1,
      volume: 1,
      isMuted: false,
      repeatMode: GoogleCastMediaRepeatMode.off,
    );

    testWidgets('names and scales the stream from what this app cast',
        (tester) async {
      cast.lastLoadOverride = const CastLoad(
        title: 'ignored',
        duration: Duration(hours: 1, minutes: 40),
        payload: CastPayload(
          apiBase: 'https://streamio.example',
          castProxyBase: '',
          provider: 'sc',
          contentType: 'episode',
          showTitle: '2.5 Dimensional Seduction',
          episodeLabel: 'S1E1',
        ),
      );

      await tester.pumpWidget(panel(
        state: null,
        status: playingStatus,
        position: const Duration(minutes: 3, seconds: 9),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('2.5 Dimensional Seduction'), findsOneWidget);
      expect(find.text('S1E1'), findsOneWidget);
      // The bar is live, and the right-hand clock counts down rather than
      // sitting at 00:00.
      final slider = tester.widget<Slider>(find.byType(Slider).first);
      expect(slider.onChanged, isNotNull);
      expect(find.text('-1:36:51'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.forward_10));
      await tester.pump();
      expect(cast.seeks, [const Duration(minutes: 3, seconds: 19)]);
    });

    testWidgets('says the duration is unknown rather than zero', (tester) async {
      await tester.pumpWidget(panel(
        state: null,
        status: playingStatus,
        position: const Duration(minutes: 3, seconds: 9),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('--:--'), findsOneWidget);
      expect(find.text('00:00'), findsNothing);
      final slider = tester.widget<Slider>(find.byType(Slider).first);
      expect(slider.onChanged, isNull);
    });
  });

  group('the now-casting button', () {
    Widget button({CastState? state, GoogleCastSession? session}) {
      return ProviderScope(
        overrides: [
          castServiceProvider.overrideWithValue(cast),
          castStateProvider.overrideWith((ref) => Stream.value(state)),
          castPositionProvider.overrideWith((ref) => Stream.value(Duration.zero)),
          castMediaStatusProvider.overrideWith((ref) => Stream.value(null)),
          castSessionProvider.overrideWith((ref) => Stream.value(session)),
        ],
        child: const MaterialApp(
          home: Scaffold(body: NowCastingButton()),
        ),
      );
    }

    testWidgets('stays out of the way when nothing is connected',
        (tester) async {
      await tester.pumpWidget(button(state: playing, session: null));
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.cast_connected), findsNothing);
    });

    testWidgets('stays out of the way when the receiver is idle',
        (tester) async {
      await tester.pumpWidget(button(
        state: const CastState(phase: 'IDLE'),
        session: _FakeSession(),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.cast_connected), findsNothing);
    });

    testWidgets('names what is playing once there is a cast to control',
        (tester) async {
      await tester.pumpWidget(button(state: playing, session: _FakeSession()));
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.cast_connected), findsOneWidget);
      expect(find.text('A Film'), findsOneWidget);
    });

    testWidgets('opens the controls, without a "play this here" it cannot honour',
        (tester) async {
      await tester.pumpWidget(button(state: playing, session: _FakeSession()));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byIcon(Icons.cast_connected));
      await tester.pumpAndSettle();

      expect(find.byType(CastControlPanel), findsOneWidget);
      expect(find.text('Play this on the TV'), findsNothing);
      // The transport is there and live: this is the point of the button.
      expect(find.byIcon(Icons.forward_10), findsOneWidget);
    });
  });

  testWidgets('the bar is not seekable before a duration is known',
      (tester) async {
    await tester.pumpWidget(
      panel(
        state: const CastState(phase: 'RESOLVING', contentType: 'movie'),
        position: Duration.zero,
      ),
    );
    // Two frames: the session, the STATE and the position arrive on separate
    // streams, and one frame only catches the first of them.
    await tester.pump();
    await tester.pump();

    final slider = tester.widget<Slider>(find.byType(Slider).first);
    expect(slider.onChanged, isNull);
  });
}

class _FakeSession extends GoogleCastSession {
  _FakeSession()
      : super(
          device: GoogleCastDevice(
            deviceID: 'tv',
            friendlyName: 'Living Room TV',
            modelName: 'Chromecast',
            statusText: null,
            deviceVersion: '1',
            isOnLocalNetwork: true,
            category: 'cast',
            uniqueID: 'tv',
          ),
          sessionID: 'session',
          connectionState: GoogleCastConnectState.connected,
          currentDeviceMuted: false,
          currentDeviceVolume: 0.5,
          deviceStatusText: '',
        );
}

/// A [CastService] that records the seeks it is asked for. Everything it
/// inherits that would touch the platform is overridden below; the
/// [ContentApi] is only there to satisfy the constructor and is never called.
class _RecordingCastService extends CastService {
  _RecordingCastService()
      : super(ContentApi(ApiClient(baseUrl: 'http://localhost')));

  final List<Duration> seeks = [];

  /// [CastService.lastLoad] is written by `load()`, which needs a session.
  CastLoad? lastLoadOverride;

  @override
  CastLoad? get lastLoad => lastLoadOverride;

  @override
  Future<void> seekTo(Duration position) async => seeks.add(position);

  @override
  GoggleCastMediaStatus? get mediaStatus => null;

  @override
  Duration get playerPosition => Duration.zero;

  @override
  Future<void> setVolume(double level) async {}
}
