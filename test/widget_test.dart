import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:streamio/app.dart';
import 'package:streamio/features/auth/login_screen.dart';
import 'package:streamio/features/setup/server_setup_screen.dart';

void main() {
  setUpAll(() {
    MediaKit.ensureInitialized();
    // The real plugin blocks indefinitely on a desktop test VM (no keyring
    // service to answer it), which hangs every test that reaches token
    // restore. The package ships this in-memory fake for exactly that.
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform({});
  });

  testWidgets('first launch lands on the server setup screen',
      (WidgetTester tester) async {
    // No stored server: nothing in the app can make a request, so the router
    // must send every route to /setup.
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ProviderScope(child: StreamioApp()));
    // Two pumps: one for the initial frame, one after the async read of
    // shared_preferences resolves and the redirect re-runs.
    await tester.pump();
    await tester.pump();

    expect(find.byType(ServerSetupScreen), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });

  testWidgets('the setup screen rejects an unusable address',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ProviderScope(child: StreamioApp()));
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '::::');
    await tester.tap(find.text('Connect'));
    await tester.pump();

    // Rejected locally, without a network round trip.
    expect(find.text('That doesn\'t look like a web address.'), findsOneWidget);
  });

  testWidgets('a configured server with no session lands on /login',
      (WidgetTester tester) async {
    // The server is known, so /setup is done — but nothing is usable without
    // an account, so the router must not let the shell render.
    SharedPreferences.setMockInitialValues({
      'server_base_url': 'https://streamio.test',
    });

    await tester.pumpWidget(const ProviderScope(child: StreamioApp()));
    // The stored server resolves, then the session restore does — the latter
    // finds no tokens in the fake keystore, which is exactly the "no
    // session" case.
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    // The guest escape hatch is gone: signing in is the only way forward.
    expect(find.text('Continue without an account'), findsNothing);
  });
}
