/// A content source as the backend describes it — `ProviderInfo` in
/// `core/core.ts`, served by `GET /api/providers`.
///
/// The label and blurb come from the server rather than a switch here so that
/// a source added or renamed server-side shows up correctly without shipping a
/// new build. [ProviderInfo.fallback] covers the other direction: an install
/// older than the `catalog` field sends bare names, and those still have to
/// render as something.
///
/// One entry is one *language variant*, not one source: the catalog is flat by
/// design (see `ProviderInfo` in `../web/core/core.ts`) so that clients written
/// before provider families existed keep rendering every variant. Grouping is
/// this client's job — [ProviderFamily] and [groupProviderFamilies].
class ProviderInfo {
  const ProviderInfo({
    required this.name,
    required this.displayName,
    required this.description,
    this.adult = false,
    String? family,
    this.language = '',
    this.languages = const [],
  }) : _family = family;

  /// The internal name — what `?provider=` carries on every content request.
  /// This is the wire identity, per variant; [family] never goes on the wire.
  final String name;

  /// Human-readable label for the source picker.
  final String displayName;

  /// One-line introduction shown under the label on the providers screen.
  final String description;

  /// A whole-provider 18+ source. The server only lists these once the user's
  /// `adult_content` preference is on, so this is purely for badging.
  final bool adult;

  final String? _family;

  /// The id shared by every language variant of this source. Falls back to
  /// [name] on a server that predates families, which makes such a server's
  /// entries group into one single-language family each — i.e. the flat list.
  String get family => _family?.isNotEmpty == true ? _family! : name;

  /// This variant's language code (`"it"`, `"en"`, ...). Empty on an install
  /// that doesn't report one.
  final String language;

  /// Every language the *family* is available in, this variant included, as
  /// the server sees it. Used only for its labels — the languages actually
  /// offered in the UI are built from the catalog entries themselves, so the
  /// picker can never point at a variant this user isn't allowed to select.
  final List<ProviderLanguage> languages;

  /// The best that can be done for a server that only sent us a name:
  /// title-case each dash-separated part. Deliberately not a lookup table —
  /// one would go stale the moment the server's list changes, which is the
  /// thing this whole path exists to avoid.
  factory ProviderInfo.fallback(String name) {
    final label = name
        .split('-')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');

    return ProviderInfo(
      name: name,
      displayName: label.isEmpty ? name : label,
      description: 'Content source.',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProviderInfo && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// One selectable language of a source — `ProviderLanguageInfo` in
/// `core/core.ts`.
class ProviderLanguage {
  const ProviderLanguage({
    required this.code,
    required this.label,
    required this.slug,
  });

  /// Language code, e.g. `"it"`.
  final String code;

  /// Human label, e.g. `"Italiano"`.
  final String label;

  /// The provider slug to send as `?provider=` for this language.
  final String slug;

  @override
  bool operator ==(Object other) =>
      other is ProviderLanguage && other.slug == slug;

  @override
  int get hashCode => slug.hashCode;
}

/// Fallback label for a language code, for an install that sends `language`
/// but no `languages` labels. Kept deliberately small: unlike provider names,
/// language names don't change when the server's registry does, and an unknown
/// code renders as itself rather than as a wrong guess.
String languageLabelFor(String code) {
  const names = {
    'it': 'Italiano',
    'en': 'English',
    'de': 'Deutsch',
    'fr': 'Français',
    'es': 'Español',
    'es-mx': 'Español (México)',
    'es-ar': 'Español (Argentina)',
    'pl': 'Polski',
    'us': 'English (US)',
  };

  if (code.isEmpty) return '';
  return names[code.toLowerCase()] ?? code.toUpperCase();
}

/// One source with every language of it this user may select — the grouped
/// view of the flat catalog, and what the pickers render.
class ProviderFamily {
  ProviderFamily({
    required this.id,
    required this.displayName,
    required this.description,
    required this.adult,
    required List<ProviderLanguage> languages,
  }) : languages = List.unmodifiable(languages);

  /// Family id, shared by every variant. Not a provider slug to send anywhere:
  /// selecting a family means selecting one of its [languages]' slugs.
  final String id;
  final String displayName;
  final String description;
  final bool adult;

  /// At least one, in catalog order.
  final List<ProviderLanguage> languages;

  bool get hasLanguageChoice => languages.length > 1;

  bool contains(String slug) => languages.any((l) => l.slug == slug);

  /// The language currently selected within this family, or null when the
  /// active provider is some other source.
  ProviderLanguage? activeLanguage(String activeSlug) {
    for (final language in languages) {
      if (language.slug == activeSlug) return language;
    }
    return null;
  }

  /// What selecting the family itself should activate: whichever language is
  /// already active within it, else its default (the first). Keeps returning
  /// to a source from picking the language chosen last time rather than
  /// silently resetting it.
  ProviderLanguage targetLanguage(String activeSlug) =>
      activeLanguage(activeSlug) ?? languages.first;

  /// The family's label with the language appended when there is more than
  /// one, so the site's name alone is never ambiguous.
  String labelFor(String activeSlug) {
    final language = activeLanguage(activeSlug);
    if (language == null || !hasLanguageChoice) return displayName;
    return '$displayName · ${language.label}';
  }
}

/// Groups the flat catalog into one entry per source.
///
/// Languages come from the catalog entries themselves, never from an entry's
/// `languages` array, so a variant the server withheld (an 18+ gate, say) can
/// never end up in the picker; the array is consulted only for its labels.
/// Entries from a server that predates families carry `family == name`, which
/// yields one single-language family each — exactly the ungrouped list.
List<ProviderFamily> groupProviderFamilies(List<ProviderInfo> catalog) {
  final order = <String>[];
  final byId = <String, _FamilyBuilder>{};

  for (final entry in catalog) {
    if (entry.name.isEmpty) continue;

    final id = entry.family;
    final family = byId.putIfAbsent(id, () {
      order.add(id);
      return _FamilyBuilder(id: id, description: entry.description);
    });

    if (entry.adult) family.adult = true;

    // The family is named after its default variant — the one whose slug is
    // the family id. Until that one is seen, any variant's label beats none.
    if (family.displayName.isEmpty || entry.name == id) {
      family.displayName = entry.displayName;
      family.description = entry.description;
    }

    final meta = entry.languages.where((l) => l.slug == entry.name).firstOrNull;
    final code = entry.language.isNotEmpty ? entry.language : meta?.code ?? '';

    family.languages.add(ProviderLanguage(
      code: code,
      label: meta?.label.isNotEmpty == true ? meta!.label : languageLabelFor(code),
      slug: entry.name,
    ));
  }

  return [
    for (final id in order)
      ProviderFamily(
        id: id,
        displayName: byId[id]!.displayName.isEmpty ? id : byId[id]!.displayName,
        description: byId[id]!.description,
        adult: byId[id]!.adult,
        languages: byId[id]!.languages,
      ),
  ];
}

class _FamilyBuilder {
  _FamilyBuilder({required this.id, required this.description});

  final String id;
  String displayName = '';
  String description;
  bool adult = false;
  final List<ProviderLanguage> languages = [];
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// `GET /api/providers` in full: the sources this server offers the current
/// user, plus the name it falls back to when a request carries no `provider`.
class ProviderCatalog {
  ProviderCatalog({
    List<ProviderInfo> providers = const [],
    this.defaultProvider,
  })  : providers = List.unmodifiable(providers),
        families = List.unmodifiable(groupProviderFamilies(providers));

  /// The flat list, one entry per language variant — still the thing every
  /// content request is keyed on.
  final List<ProviderInfo> providers;

  /// The same list grouped by source, which is what the pickers render.
  final List<ProviderFamily> families;

  /// The server's own default (`Core.getDefaultProvider()`). Null on installs
  /// that don't report one — the app then simply sends no `provider` and lets
  /// the server pick.
  final String? defaultProvider;

  ProviderInfo? byName(String name) {
    for (final info in providers) {
      if (info.name == name) return info;
    }
    return null;
  }

  /// The family the given slug belongs to, or null if it isn't on offer.
  ProviderFamily? familyOf(String slug) {
    for (final family in families) {
      if (family.contains(slug)) return family;
    }
    return null;
  }
}
