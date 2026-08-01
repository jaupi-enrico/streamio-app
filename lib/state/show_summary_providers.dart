import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/content_api.dart';
import '../core/models/models.dart';
import 'api_providers.dart';

/// Identifies a title the way the account tables do: `(provider, show_id)`.
@immutable
class ShowRef {
  const ShowRef(this.provider, this.showId);

  final String provider;
  final String showId;

  @override
  bool operator ==(Object other) =>
      other is ShowRef && other.provider == provider && other.showId == showId;

  @override
  int get hashCode => Object.hash(provider, showId);

  @override
  String toString() => '$provider:$showId';
}

/// The `watchlist`, `favorites` and `watch_history` rows carry only
/// `(provider, show_id)` — no title, no poster (see `account.service.ts`).
/// The web account page hydrates them by fetching `/api/shows/:id` per row
/// (`hydrateShowCache` in `public/scripts/account.js`); this is the same,
/// keyed so several screens showing the same title fetch it once.
///
/// Resolves to null instead of throwing when the lookup fails: a broken
/// entry should degrade to "id only", not take a whole list down.
final showSummaryProvider =
    FutureProvider.autoDispose.family<Show?, ShowRef>((ref, key) async {
  final api = ref.watch(contentApiProvider);

  // Held across the fetch so a row scrolling out of view mid-request doesn't
  // dispose the provider and make the next build start over. A failed lookup
  // drops the link, so re-opening the tab retries it (same as the web page).
  final link = ref.keepAlive();
  final show = await _gate.run(() => _fetchShow(api, key));
  if (show == null) link.close();
  return show;
});

const _retries = 2;
const _retryDelay = Duration(milliseconds: 500);

/// Details come from the scrapers, so a list of 50 rows must not fan out into
/// 50 simultaneous provider hits — `account.js` caps itself at 4 the same way.
final _gate = _ConcurrencyGate(4);

Future<Show?> _fetchShow(ContentApi api, ShowRef key) async {
  for (var attempt = 0; attempt <= _retries; attempt++) {
    try {
      final show = await api.showDetails(key.showId, provider: key.provider);
      if (show != null) return show;
    } catch (_) {
      // Transient scraper failures are common; fall through to the retry.
    }
    if (attempt < _retries) await Future<void>.delayed(_retryDelay * (attempt + 1));
  }
  return null;
}

class _ConcurrencyGate {
  _ConcurrencyGate(this.limit);

  final int limit;
  final List<Completer<void>> _waiting = [];
  int _running = 0;

  Future<T> run<T>(Future<T> Function() task) async {
    if (_running >= limit) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    _running++;
    try {
      return await task();
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }
}

/// Title/poster for a library or history row, preferring anything the row
/// itself carried and falling back to the show id so a tile is never blank.
({String title, String? poster}) resolveShowDisplay(
  WidgetRef ref, {
  required String provider,
  required String showId,
  String? title,
  String? poster,
}) {
  if (title != null && poster != null) return (title: title, poster: poster);

  final show = ref.watch(showSummaryProvider(ShowRef(provider, showId))).valueOrNull;
  return (
    title: title ?? show?.title ?? showId,
    poster: poster ?? show?.poster,
  );
}
