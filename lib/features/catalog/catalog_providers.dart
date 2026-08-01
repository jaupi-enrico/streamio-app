import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../state/api_providers.dart';
import '../../state/core_providers.dart';

/// The genre list for the active provider (`GET /api/genres`). Providers that
/// don't expose genres answer with an empty list, and the filter row simply
/// doesn't render.
final genresProvider = FutureProvider.autoDispose<List<Genre>>((ref) async {
  final api = ref.watch(contentApiProvider);
  return api.genres(provider: ref.watch(activeProviderNameProvider));
});

/// Catalog body: the same `GET /api/home` payload the home screen uses, laid
/// out as grids instead of rails (that's exactly what `catalog.js` does).
final catalogCategoriesProvider =
    FutureProvider.autoDispose<List<Category>>((ref) async {
  final api = ref.watch(contentApiProvider);
  return api.home(provider: ref.watch(activeProviderNameProvider));
});

/// `catalog.js`'s `isFeaturedCategory()` — the row that becomes the top
/// carousel rather than a grid. Matched by name because the backend labels it
/// in Italian for some providers and English for others.
bool isFeaturedCategory(String name) {
  final lower = name.toLowerCase();
  return lower.contains('evidenza') ||
      lower.contains('featured') ||
      lower.contains('highlight') ||
      lower.contains('spotlight');
}
