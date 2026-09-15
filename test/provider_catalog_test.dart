import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/core/api/json_mappers.dart';
import 'package:streamio/core/models/models.dart';

/// A `catalog` entry as a current server sends it.
Map<String, dynamic> entry(
  String name, {
  String? family,
  String language = '',
  List<Map<String, dynamic>> languages = const [],
  bool adult = false,
  String displayName = '',
  String description = 'Some source.',
}) =>
    {
      'name': name,
      'displayName': displayName.isEmpty ? name : displayName,
      'description': description,
      'adult': adult,
      if (family != null) 'family': family,
      if (language.isNotEmpty) 'language': language,
      if (languages.isNotEmpty) 'languages': languages,
    };

void main() {
  const hubLanguages = [
    {'code': 'it', 'label': 'Italiano', 'slug': 'filmhub'},
    {'code': 'en', 'label': 'English', 'slug': 'filmhub-en'},
  ];

  ProviderCatalog catalogOf(List<Map<String, dynamic>> entries) =>
      ProviderCatalog(providers: entries.map(providerInfoFromJson).toList());

  group('provider families', () {
    test('groups the flat catalog by family, in catalog order', () {
      final catalog = catalogOf([
        entry('filmhub',
            family: 'filmhub',
            language: 'it',
            languages: hubLanguages,
            displayName: 'FilmHub'),
        entry('toonbox',
            family: 'toonbox', language: 'it', displayName: 'ToonBox'),
        entry('filmhub-en',
            family: 'filmhub',
            language: 'en',
            languages: hubLanguages,
            displayName: 'FilmHub EN'),
      ]);

      expect(catalog.providers.length, 3, reason: 'the flat list is untouched');
      expect(catalog.families.map((f) => f.id),
          ['filmhub', 'toonbox']);

      final sc = catalog.families.first;
      // Named after the default variant, not after whichever came last.
      expect(sc.displayName, 'FilmHub');
      expect(sc.hasLanguageChoice, isTrue);
      expect(sc.languages.map((l) => l.slug),
          ['filmhub', 'filmhub-en']);
      expect(sc.languages.map((l) => l.label), ['Italiano', 'English']);
      expect(catalog.families.last.hasLanguageChoice, isFalse);
    });

    test('only offers languages the server actually listed', () {
      // The English mirror is in every entry's `languages` array but was not
      // served as its own entry — an 18+ gate, a disabled variant. It must not
      // become selectable off the back of the array alone.
      final catalog = catalogOf([
        entry('filmhub',
            family: 'filmhub',
            language: 'it',
            languages: hubLanguages),
      ]);

      expect(catalog.families.single.languages.map((l) => l.slug),
          ['filmhub']);
      expect(catalog.familyOf('filmhub-en'), isNull);
    });

    test('a server predating families yields one family per entry', () {
      final catalog = catalogOf([
        {'name': 'filmhub'},
        {'name': 'toonbox'},
      ]);

      expect(catalog.families.length, 2);
      expect(catalog.families.every((f) => !f.hasLanguageChoice), isTrue);
      // Still the fallback title-casing, not a blank row.
      expect(catalog.families.first.displayName, 'Filmhub');
      expect(catalog.families.first.languages.single.slug, 'filmhub');
    });

    test('labels a language the server sent without one', () {
      final catalog = catalogOf([
        entry('livegrid', family: 'livegrid', language: 'it'),
        entry('livegrid-de', family: 'livegrid', language: 'de'),
        entry('livegrid-xx', family: 'livegrid', language: 'xx'),
      ]);

      expect(catalog.families.single.languages.map((l) => l.label),
          ['Italiano', 'Deutsch', 'XX']);
    });

    test('selecting a family keeps the language already active in it', () {
      final catalog = catalogOf([
        entry('filmhub',
            family: 'filmhub',
            language: 'it',
            languages: hubLanguages),
        entry('filmhub-en',
            family: 'filmhub',
            language: 'en',
            languages: hubLanguages),
      ]);
      final sc = catalog.families.single;

      expect(sc.targetLanguage('filmhub-en').slug,
          'filmhub-en');
      // Nothing of this family is active: the default variant wins.
      expect(sc.targetLanguage('toonbox').slug, 'filmhub');
      expect(sc.activeLanguage('toonbox'), isNull);
    });

    test('the label carries the language only when there is a choice', () {
      final multi = catalogOf([
        entry('filmhub',
            family: 'filmhub',
            language: 'it',
            languages: hubLanguages,
            displayName: 'FilmHub'),
        entry('filmhub-en',
            family: 'filmhub',
            language: 'en',
            languages: hubLanguages),
      ]).families.single;
      final single = catalogOf([
        entry('toonbox',
            family: 'toonbox', language: 'it', displayName: 'ToonBox'),
      ]).families.single;

      expect(multi.labelFor('filmhub-en'),
          'FilmHub · English');
      expect(multi.labelFor('toonbox'), 'FilmHub');
      expect(single.labelFor('toonbox'), 'ToonBox');
    });

    test('a family is 18+ if any of its languages is', () {
      final catalog = catalogOf([
        entry('lateshow', family: 'lateshow', language: 'it'),
        entry('lateshow-en',
            family: 'lateshow', language: 'en', adult: true),
      ]);

      expect(catalog.families.single.adult, isTrue);
    });

    test('the slug stays the wire identity', () {
      final catalog = catalogOf([
        entry('filmhub-en',
            family: 'filmhub',
            language: 'en',
            languages: hubLanguages),
      ]);

      // The family id is not a name to send anywhere; the variant's is.
      expect(catalog.byName('filmhub-en'), isNotNull);
      expect(catalog.byName('filmhub'), isNull);
      expect(catalog.familyOf('filmhub-en')?.id,
          'filmhub');
    });
  });
}
