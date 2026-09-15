import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/models.dart';
import 'api_providers.dart';

const _activeProviderPrefsKey = 'active_provider';

/// The content sources the backend has registered (`GET /api/providers`),
/// with their labels and the server's own default.
final providerCatalogProvider = FutureProvider<ProviderCatalog>((ref) async {
  return ref.watch(contentApiProvider).providers();
});

/// Just the sources, for anything that needs the flat, per-language-variant
/// list. Metadata comes with each one — nothing in the app knows a provider
/// name ahead of time.
final providerListProvider = Provider<AsyncValue<List<ProviderInfo>>>((ref) {
  return ref.watch(providerCatalogProvider).whenData((c) => c.providers);
});

/// The sources grouped by family — one entry per site, carrying the languages
/// it is offered in. This is what the pickers render: two languages of the
/// same site are one choice plus a language selector, not two sources that
/// look unrelated.
final providerFamiliesProvider =
    Provider<AsyncValue<List<ProviderFamily>>>((ref) {
  return ref.watch(providerCatalogProvider).whenData((c) => c.families);
});

/// The user's chosen content provider. Local-only, never synced with the
/// server -- mirrors the web app's own behavior (its provider-selection
/// endpoints only validate, never persist server-side), so this is
/// shared_preferences here exactly like it is `localStorage` there.
///
/// The empty string is a real state, not a missing one: `_providerQuery` omits
/// an empty `provider`, and the server then answers from its own default. That
/// is what the app browses on before the catalog has loaded, and it is why
/// there is no compile-time default name here — the server's default arrives
/// with the catalog, and a name saved against a *different* server (the base
/// URL is user-configured and changeable) is dropped once we can see it isn't
/// on offer.
class ActiveProviderNotifier extends Notifier<String> {
  @override
  String build() {
    _restore();
    ref.listen<AsyncValue<ProviderCatalog>>(
      providerCatalogProvider,
      (_, next) => next.whenData(_reconcile),
      fireImmediately: true,
    );
    return '';
  }

  /// Set once [_restore] has run, so a catalog arriving first doesn't adopt the
  /// server default over a stored choice we simply hadn't read yet.
  bool _restored = false;
  ProviderCatalog? _pending;

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_activeProviderPrefsKey);
    if (!ref.mounted) return;
    if (saved != null && saved.isNotEmpty) state = saved;

    _restored = true;
    final pending = _pending;
    _pending = null;
    if (pending != null) _reconcile(pending);
  }

  void _reconcile(ProviderCatalog catalog) {
    if (!_restored) {
      _pending = catalog;
      return;
    }
    // An empty catalogue means the request failed or the user's 18+ gate hid
    // everything; either way, don't clear a working choice over it.
    if (catalog.providers.isEmpty) return;
    if (state.isNotEmpty && catalog.byName(state) != null) return;

    final fallback = catalog.defaultProvider;
    _persist(fallback != null && catalog.byName(fallback) != null
        ? fallback
        : catalog.providers.first.name);
  }

  Future<void> setProvider(String name) async {
    if (name.isEmpty || name == state) return;
    await _persist(name);
  }

  Future<void> _persist(String name) async {
    state = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeProviderPrefsKey, name);
  }
}

final activeProviderNameProvider =
    NotifierProvider<ActiveProviderNotifier, String>(ActiveProviderNotifier.new);

/// The active source's metadata, once the catalog is in — `null` while it
/// loads or if the server no longer offers it.
final activeProviderInfoProvider = Provider<ProviderInfo?>((ref) {
  final name = ref.watch(activeProviderNameProvider);
  if (name.isEmpty) return null;
  return ref.watch(providerCatalogProvider).value?.byName(name);
});

/// The family the active source belongs to — the grouped counterpart of
/// [activeProviderInfoProvider], for anything that wants to show the site and
/// the language separately.
final activeProviderFamilyProvider = Provider<ProviderFamily?>((ref) {
  final name = ref.watch(activeProviderNameProvider);
  if (name.isEmpty) return null;
  return ref.watch(providerCatalogProvider).value?.familyOf(name);
});

/// A short label for any provider slug — the site, plus the language *code*
/// when the site has more than one ("Site · EN"). Used to badge rows that
/// aren't from the source currently being browsed, which is every row of a
/// cross-provider list like Continue Watching.
///
/// Falls back to [ProviderInfo.fallback]'s title-casing for a slug the catalog
/// doesn't list — a history row saved before a source was added, or one behind
/// a gate that is currently closed — rather than showing nothing.
final providerLabelProvider = Provider.family<String, String>((ref, slug) {
  if (slug.isEmpty) return '';

  final catalog = ref.watch(providerCatalogProvider).value;
  final family = catalog?.familyOf(slug);
  if (family == null) return ProviderInfo.fallback(slug).displayName;

  final language = family.activeLanguage(slug);
  // The code, not the label: this goes on a card badge, where
  // "Site · United States" is truncated to uselessness.
  if (!family.hasLanguageChoice || language == null || language.code.isEmpty) {
    return family.displayName;
  }
  return '${family.displayName} · ${language.code.toUpperCase()}';
});
