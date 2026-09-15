import 'package:flutter/material.dart';

import '../account_providers.dart';

/// Asks for the next page when the list gets within [threshold] of its end.
///
/// A `NotificationListener` rather than the `ScrollController` the catalog and
/// search screens use, because the account tabs sit in the body of
/// `account_screen.dart`'s [NestedScrollView]. That widget installs its own
/// [PrimaryScrollController] to couple the body's scrollables to the
/// collapsing `SliverAppBar`; handing a tab's `ListView` a controller of our
/// own opts it out of that coupling and the header stops collapsing. Scroll
/// notifications carry the same numbers and cost nothing to observe.
class PagedScrollLoader extends StatelessWidget {
  const PagedScrollLoader({
    super.key,
    required this.onLoadMore,
    required this.child,
    this.threshold = 400,
  });

  final VoidCallback onLoadMore;
  final Widget child;
  final double threshold;

  bool _nearEnd(ScrollMetrics metrics) =>
      metrics.axis == Axis.vertical && metrics.extentAfter < threshold;

  @override
  Widget build(BuildContext context) {
    // A page that doesn't fill the viewport produces no scroll notification at
    // all, so the scroll trigger alone would never fire again — the same stall
    // `fillViewport()` works around in `../web/public/scripts/account.js`.
    // ScrollMetricsNotification fires when the content grows or shrinks
    // without a scroll, which covers exactly that.
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 && _nearEnd(notification.metrics)) {
          onLoadMore();
        }
        return false;
      },
      child: _scrollListener(),
    );
  }

  Widget _scrollListener() {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // Only the list's own scrolling counts. Inside a NestedScrollView the
        // outer (header) position bubbles through here too, and its extent has
        // nothing to do with how much list is left.
        if (notification.depth != 0) return false;
        if (_nearEnd(notification.metrics)) onLoadMore();
        // Never swallow: RefreshIndicator and the NestedScrollView coordinator
        // are both listening further up.
        return false;
      },
      child: child,
    );
  }
}

/// The tail of a paged list: a spinner while a page is in flight, a **Load
/// more** button while there is more to ask for, nothing once exhausted.
///
/// The button isn't redundant with [PagedScrollLoader]. The account rows are
/// plain `ListTile`s with no [TvFocusable] `ensureVisible` behind them, so on
/// a television there is nothing to drive the scroll — a focusable button is
/// what makes paging reachable with a D-pad at all. It doubles as the retry
/// affordance after a page fails, which is the state a silent scroll trigger
/// leaves you stuck in.
///
/// Always rendered once the list has rows, even when there is nothing left to
/// load: pressing the button on the last page destroys the node that holds
/// focus, and a screen with no focused node swallows the next D-pad press. It
/// stays mounted so it can hand focus on rather than drop it.
class PagedListFooter extends StatefulWidget {
  const PagedListFooter({super.key, required this.list, required this.onLoadMore});

  final PagedList<Object?> list;
  final VoidCallback onLoadMore;

  @override
  State<PagedListFooter> createState() => _PagedListFooterState();
}

class _PagedListFooterState extends State<PagedListFooter> {
  final _buttonFocus = FocusNode(debugLabel: 'Load more');

  @override
  void didUpdateWidget(PagedListFooter oldWidget) {
    super.didUpdateWidget(oldWidget);

    final ended = !oldWidget.list.exhausted && widget.list.exhausted;
    if (ended && _buttonFocus.hasFocus) {
      // The button is about to stop being rendered. Hand focus back up into
      // the list rather than leaving the screen with no focused node.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).focusInDirection(TraversalDirection.up);
      });
    }
  }

  @override
  void dispose() {
    _buttonFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.list;
    if (list.exhausted && !list.loadingMore) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: list.loadingMore
            ? const SizedBox(
                width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : OutlinedButton.icon(
                focusNode: _buttonFocus,
                onPressed: widget.onLoadMore,
                icon: const Icon(Icons.expand_more),
                label: const Text('Load more'),
              ),
      ),
    );
  }
}

/// "Showing 24 of 87" above a paged list.
///
/// Hidden when the server didn't send `X-Total-Count` — an install predating
/// paging, where there is no total to show.
///
/// Once the list has ended the total is dropped in favour of the local count.
/// The server counts rows *before* the 18+ gate filters them, so for an
/// account with adult content disabled the total can exceed what will ever
/// arrive — and "24 of 87" sitting under a list with nothing left to load
/// reads as broken. Mid-list the discrepancy is invisible, so the total is
/// worth showing there and not at the end.
class PagedListCount extends StatelessWidget {
  const PagedListCount({super.key, required this.list, required this.noun});

  final PagedList<Object?> list;
  final String noun;

  @override
  Widget build(BuildContext context) {
    final total = list.total;
    final shown = list.items.length;
    final theme = Theme.of(context);

    final String label;
    if (list.exhausted || total == null) {
      if (total == null && shown == 0) return const SizedBox.shrink();
      label = '$shown $noun${shown == 1 ? '' : 's'}';
    } else {
      label = 'Showing $shown of $total';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(color: theme.hintColor),
      ),
    );
  }
}
