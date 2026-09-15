import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:streamio/core/models/models.dart';
import 'package:streamio/features/providers/providers_screen.dart';
import 'package:streamio/shared/widgets/provider_picker.dart';
import 'package:streamio/state/core_providers.dart';

ProviderInfo _info(String slug, String label, String family, String language) =>
    ProviderInfo(
      name: slug,
      displayName: label,
      description: 'Live TV channels.',
      family: family,
      language: language,
      languages: const [
        ProviderLanguage(code: 'it', label: 'Italia', slug: 'livegrid'),
        ProviderLanguage(code: 'de', label: 'Deutschland', slug: 'livegrid-de'),
      ],
    );

final _catalog = ProviderCatalog(
  providers: [
    _info('livegrid', 'LiveGrid', 'livegrid', 'it'),
    _info('livegrid-de', 'LiveGrid (Deutschland)', 'livegrid', 'de'),
    const ProviderInfo(
      name: 'toonbox',
      displayName: 'ToonBox',
      description: 'Anime.',
      family: 'toonbox',
      language: 'it',
    ),
  ],
  defaultProvider: 'livegrid',
);

Future<ProviderContainer> _pump(WidgetTester tester, Widget child) async {
  SharedPreferences.setMockInitialValues({'active_provider': 'livegrid'});
  final container = ProviderContainer(overrides: [
    providerCatalogProvider.overrideWith((ref) async => _catalog),
  ]);
  addTearDown(container.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(home: Scaffold(body: child)),
  ));
  // One pump for the stored selection, one for the catalog future.
  await tester.pump();
  await tester.pump();

  return container;
}

void main() {
  testWidgets('the providers screen switches language within a source',
      (tester) async {
    final container = await _pump(tester, const ProvidersScreen());

    expect(container.read(activeProviderNameProvider), 'livegrid');
    // One row per source, not one per language.
    expect(find.text('LiveGrid'), findsOneWidget);
    expect(find.text('LiveGrid (Deutschland)'), findsNothing);

    await tester.tap(find.text('Deutschland'));
    await tester.pump();

    expect(container.read(activeProviderNameProvider), 'livegrid-de');
  });

  testWidgets('the selected source\'s languages are one tap from the bar',
      (tester) async {
    final container = await _pump(tester, const ProviderPicker());

    // The bar names the source once and lists only its languages — never the
    // whole catalogue, which is what made a chip per source overflow.
    expect(find.text('LiveGrid'), findsOneWidget);
    expect(find.text('ToonBox'), findsNothing);

    await tester.tap(find.text('Deutschland'));
    await tester.pumpAndSettle();

    expect(container.read(activeProviderNameProvider), 'livegrid-de');
  });

  testWidgets('the menu selects another source', (tester) async {
    final container = await _pump(tester, const ProviderPicker());

    await tester.tap(find.text('LiveGrid'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ToonBox'));
    await tester.pumpAndSettle();

    expect(container.read(activeProviderNameProvider), 'toonbox');
    // A single-language source has no language row to show.
    expect(find.text('Deutschland'), findsNothing);
  });
}
