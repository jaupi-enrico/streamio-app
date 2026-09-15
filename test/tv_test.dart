import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/shared/tv.dart';

/// [isTv] answering `false` on an actual television is a silent failure: the
/// app keeps working, it just serves the touch chrome to someone holding a
/// remote. That is what the [MediaQuery.navigationModeOf]-only version did on
/// every device, so the platform answer is worth pinning down.
void main() {
  const channel = MethodChannel('streamio/platform');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TvPlatform.debugIsTv = false;
  });

  void answerIsTv(bool? value) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'isTv' ? value : null,
    );
  }

  Future<bool> readIsTv(WidgetTester tester,
      {NavigationMode? navigationMode}) async {
    late bool answer;
    final Widget reader = Builder(builder: (context) {
      answer = isTv(context);
      return const SizedBox.shrink();
    });
    final Widget probe = navigationMode == null
        ? reader
        : Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(navigationMode: navigationMode),
              child: reader,
            ),
          );
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: probe,
    ));
    return answer;
  }

  testWidgets('a platform that says it is a TV is treated as one',
      (tester) async {
    answerIsTv(true);
    await TvPlatform.load();
    expect(TvPlatform.isTvDevice, isTrue);
    expect(await readIsTv(tester), isTrue);
  });

  testWidgets('a platform that says it is not stays on the touch chrome',
      (tester) async {
    answerIsTv(false);
    await TvPlatform.load();
    expect(await readIsTv(tester), isFalse);
  });

  test('no channel at all (tests, a failed registration) falls back to false',
      () async {
    TvPlatform.debugIsTv = true;
    await TvPlatform.load();
    expect(TvPlatform.isTvDevice, isFalse);
  });

  test('a channel that answers null falls back to false', () async {
    answerIsTv(null);
    await TvPlatform.load();
    expect(TvPlatform.isTvDevice, isFalse);
  });

  testWidgets('a directional MediaQuery still forces the D-pad chrome',
      (tester) async {
    // Not how a real device is detected any more, but the override remains
    // the way a subtree (or a test) can ask for the TV treatment.
    expect(
      await readIsTv(tester, navigationMode: NavigationMode.directional),
      isTrue,
    );
    expect(
      await readIsTv(tester, navigationMode: NavigationMode.traditional),
      isFalse,
    );
  });
}
