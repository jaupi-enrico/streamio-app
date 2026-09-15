import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/core/api/paged_response.dart';
import 'package:streamio/features/account/account_providers.dart';

/// The paging arithmetic, exercised without an HTTP client.
///
/// Everything here fails silently in the app — a wrong offset shows duplicate
/// rows, an old server pages forever — so it is tested against a fake that
/// records exactly which offsets were asked for.
class _FakeNotifier extends PagedListNotifier<String> {
  _FakeNotifier(this.pages, {this.legacy});

  /// One entry per request, in order; the last repeats if asked again.
  final List<PagedResponse<String>> pages;
  final List<String>? legacy;

  final offsets = <int>[];
  int legacyCalls = 0;
  int _call = 0;

  @override
  Future<PagedResponse<String>> fetchPage({
    required int limit,
    required int offset,
  }) async {
    offsets.add(offset);
    final page = pages[_call.clamp(0, pages.length - 1)];
    _call++;
    return page;
  }

  @override
  Future<List<String>>? fetchAllLegacy() {
    if (legacy == null) return null;
    legacyCalls++;
    return Future.value(legacy);
  }
}

PagedResponse<String> page({
  required int items,
  required int rows,
  bool paged = true,
  int? total,
  int from = 0,
}) =>
    PagedResponse<String>(
      items: [for (var i = 0; i < items; i++) 'row${from + i}'],
      pageRows: rows,
      paged: paged,
      total: total,
    );

const _size = PagedListNotifier.pageSize; // 24

void main() {
  late ProviderContainer container;

  ({
    _FakeNotifier notifier,
    NotifierProvider<PagedListNotifier<String>, PagedList<String>> provider
  }) build(_FakeNotifier fake) {
    final provider =
        NotifierProvider<PagedListNotifier<String>, PagedList<String>>(
            () => fake);
    container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(provider, (_, __) {}, fireImmediately: true);
    return (notifier: fake, provider: provider);
  }

  /// Lets the first page's future settle — `build()` starts it eagerly.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('the first page lands and is not exhausted while full', () async {
    final fake = _FakeNotifier([page(items: _size, rows: _size, total: 90)]);
    final built = build(fake);
    await settle();

    final state = container.read(built.provider);
    expect(state.loading, isFalse);
    expect(state.items, hasLength(_size));
    expect(state.total, 90);
    expect(state.exhausted, isFalse);
    expect(fake.offsets, [0]);
  });

  test('a short page ends the list', () async {
    final built = build(_FakeNotifier([page(items: 5, rows: 5)]));
    await settle();

    expect(container.read(built.provider).exhausted, isTrue);
  });

  test('the offset advances by the rows read, not the rows returned', () async {
    // The 18+ gate dropped 3 of the 24 the server read. Stepping by 21 would
    // re-request those 3 and show the survivors a second time.
    final fake = _FakeNotifier([
      page(items: 21, rows: _size, total: 90),
      page(items: 21, rows: _size, from: 100),
    ]);
    final built = build(fake);
    await settle();

    await container.read(built.provider.notifier).loadMore();

    expect(fake.offsets, [0, _size]);
    expect(container.read(built.provider).items, hasLength(42));
  });

  test('a full page that arrives half-empty is not the last page', () async {
    final built = build(_FakeNotifier([page(items: 2, rows: _size)]));
    await settle();

    expect(container.read(built.provider).exhausted, isFalse,
        reason: 'there are more rows behind the filtered ones');
  });

  test('a server without paging headers stops after one request', () async {
    // The pre-paging endpoints ignore limit/offset and return everything, so
    // asking again would hand back the same rows forever.
    final fake = _FakeNotifier([page(items: 87, rows: 87, paged: false)]);
    final built = build(fake);
    await settle();

    expect(container.read(built.provider).exhausted, isTrue);
    await container.read(built.provider.notifier).loadMore();
    expect(fake.offsets, [0], reason: 'no second request');
  });

  test('an unpaged server that truncated history is refetched the old way',
      () async {
    final fake = _FakeNotifier(
      [page(items: _size, rows: _size, paged: false)],
      legacy: [for (var i = 0; i < 100; i++) 'old$i'],
    );
    final built = build(fake);
    await settle();
    await settle();

    expect(fake.legacyCalls, 1);
    expect(container.read(built.provider).items, hasLength(100),
        reason: 'the app must not show fewer rows than the previous release');
  });

  test('loadMore is a no-op while exhausted or already loading', () async {
    final fake = _FakeNotifier([page(items: 5, rows: 5)]);
    final built = build(fake);
    await settle();

    await container.read(built.provider.notifier).loadMore();
    await container.read(built.provider.notifier).loadMore();
    expect(fake.offsets, [0]);
  });

  test('a failed later page keeps what is on screen', () async {
    final fake = _ThrowingOnSecond();
    final built = build(fake);
    await settle();

    await container.read(built.provider.notifier).loadMore();

    final state = container.read(built.provider);
    expect(state.items, hasLength(_size), reason: 'the first page survives');
    expect(state.loadingMore, isFalse, reason: 'so the next press can retry');
    expect(state.exhausted, isFalse);
  });

  test('a failed first page surfaces the error', () async {
    final built = build(_ThrowingFirst());
    await settle();

    final state = container.read(built.provider);
    expect(state.loading, isFalse);
    expect(state.error, isNotNull);
    expect(state.items, isEmpty);
  });

  test('removing a row drops it, decrements the total and rewinds the offset',
      () async {
    final fake = _FakeNotifier([
      page(items: _size, rows: _size, total: 90),
      page(items: _size, rows: _size, from: 100),
    ]);
    final built = build(fake);
    await settle();

    container.read(built.provider.notifier).removeWhere((e) => e == 'row0');

    var state = container.read(built.provider);
    expect(state.items, hasLength(_size - 1));
    expect(state.total, 89);

    // The server's list got shorter too, so the next page starts one earlier —
    // otherwise a row falls between the two pages and is never shown.
    await container.read(built.provider.notifier).loadMore();
    expect(fake.offsets, [0, _size - 1]);
  });

  test('refresh goes back to the first page', () async {
    final fake = _FakeNotifier([
      page(items: _size, rows: _size),
      page(items: _size, rows: _size, from: 100),
      page(items: 3, rows: 3, from: 200),
    ]);
    final built = build(fake);
    await settle();
    await container.read(built.provider.notifier).loadMore();

    await container.read(built.provider.notifier).refresh();

    expect(fake.offsets, [0, _size, 0]);
    expect(container.read(built.provider).items, hasLength(3));
  });
}

class _ThrowingOnSecond extends _FakeNotifier {
  _ThrowingOnSecond() : super([page(items: _size, rows: _size)]);

  int _calls = 0;

  @override
  Future<PagedResponse<String>> fetchPage({
    required int limit,
    required int offset,
  }) async {
    offsets.add(offset);
    if (_calls++ == 0) return page(items: _size, rows: _size);
    throw Exception('network');
  }
}

class _ThrowingFirst extends _FakeNotifier {
  _ThrowingFirst() : super(const []);

  @override
  Future<PagedResponse<String>> fetchPage({
    required int limit,
    required int offset,
  }) async =>
      throw Exception('offline');
}
