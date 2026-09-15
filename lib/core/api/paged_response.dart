/// One page of a listing, plus the two numbers the server sends alongside it.
///
/// The account listing endpoints (`/api/account/watchlist`, `/favorites`,
/// `/history` and their `/search` variants) stayed **bare JSON arrays** when
/// they gained paging — the numbers ride in response headers instead, so a
/// client written before paging existed is unaffected. See `sendPage()` in
/// `../web/routes/account.router.ts`.
class PagedResponse<T> {
  const PagedResponse({
    required this.items,
    required this.pageRows,
    required this.paged,
    this.total,
  });

  /// The rows that survived, already deserialized.
  final List<T> items;

  /// `X-Page-Rows` — how many rows the server's query actually *read*, before
  /// it dropped any behind the 18+ gate.
  ///
  /// **This is what an offset advances by, never [items].length.** The list can
  /// be shorter than the page the server read, and stepping by the shorter
  /// number re-requests the filtered rows and serves them again as duplicates.
  /// It is also the honest end-of-list test: a full page that arrives
  /// half-empty still has more behind it.
  ///
  /// Falls back to `items.length` when the header is absent — see [paged].
  final int pageRows;

  /// Whether the server actually paged this listing, i.e. whether it sent
  /// `X-Page-Rows` at all.
  ///
  /// `sendPage()` sets that header on every paged response, so its absence is
  /// a reliable "this install predates paging" detector — and the app ships to
  /// installs that upgrade at their own pace, so it has to be one. Such a
  /// server **ignores `limit`/`offset` and answers with the whole listing**:
  /// a 87-row watchlist comes back whole, `pageRows` falls back to 87, and
  /// `87 < 24` is false, so a pager that trusted the arithmetic would ask for
  /// offset 87, get the same 87 rows again, and loop. When this is false the
  /// array *is* the complete listing and there is nothing more to ask for.
  final bool paged;

  /// `X-Total-Count` — the listing's full size, or null if the server didn't
  /// say.
  ///
  /// Counted *before* 18+ filtering, so it can read slightly high for an
  /// account with adult content disabled. Fine to display as an approximate
  /// count; never derive "is there more" from it — that's [pageRows].
  final int? total;
}
