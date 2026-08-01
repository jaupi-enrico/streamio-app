import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_providers.dart';

const _activeProviderPrefsKey = 'active_provider';
const _fallbackProvider = 'streamingcommunity';

/// The content sources the backend has registered (`GET /api/providers`).
final providerListProvider = FutureProvider<List<String>>((ref) async {
  return ref.watch(contentApiProvider).providers();
});

/// The user's chosen content provider ("streamingcommunity", "animeunity",
/// ...). Local-only, never synced with the server -- mirrors the web app's
/// own behavior (its provider-selection endpoints only validate, never
/// persist server-side), so this is shared_preferences here exactly like it
/// is `localStorage` there.
class ActiveProviderNotifier extends StateNotifier<String> {
  ActiveProviderNotifier() : super(_fallbackProvider) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_activeProviderPrefsKey);
    if (saved != null && saved.isNotEmpty) state = saved;
  }

  Future<void> setProvider(String name) async {
    if (name.isEmpty || name == state) return;
    state = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeProviderPrefsKey, name);
  }
}

final activeProviderNameProvider =
    StateNotifierProvider<ActiveProviderNotifier, String>(
        (ref) => ActiveProviderNotifier());
