import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The type is bundled (`assets/google_fonts/`) and `main()` turns runtime
/// fetching off, so these files are the only thing standing between the app and
/// Flutter's fallback face.
///
/// google_fonts matches assets by filename — `Family-Weight.ttf`, the
/// Google Fonts API's own naming — so a rename or a tidy-up of "unused" files
/// breaks font loading with no compile error and no test failure anywhere else.
/// Hence a check on the names themselves.
///
/// This deliberately isn't a load test: in `flutter test` the asset bundle and
/// `path_provider` don't behave like the real thing, and `GoogleFonts` reports
/// a missing file as a `debugPrint` rather than a failure — an assertion on the
/// loader passes there whether or not the fonts exist. What does catch a
/// *newly requested* weight is running the app: with fetching disabled,
/// google_fonts prints `unable to load font Family-Weight` at startup.
void main() {
  test('the weights AppTheme asks for are bundled', () {
    // DM Sans body copy at w400 and w500 (Material 3's title/label weight),
    // Bebas Neue for display/headline — it ships a single weight, so every
    // style resolves to Regular.
    const expected = <String>[
      'DMSans-Regular.ttf',
      'DMSans-Medium.ttf',
      'BebasNeue-Regular.ttf',
    ];

    final present = Directory('assets/google_fonts')
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .toSet();

    expect(present, containsAll(expected));
    // The OFL text is bundled too — main() feeds it to the LicenseRegistry, and
    // rootBundle.loadString throws at startup if it isn't there.
    expect(present, containsAll(['OFL-DMSans.txt', 'OFL-BebasNeue.txt']));
  });
}
