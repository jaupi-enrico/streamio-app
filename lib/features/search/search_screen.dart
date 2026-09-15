import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../shared/widgets/async_states.dart';
import '../../shared/widgets/poster_card.dart';
import '../../shared/widgets/provider_picker.dart';
import '../../state/api_providers.dart';
import '../../state/core_providers.dart';

/// `search.html` / `search.js`: a debounced query against `GET /api/search`
/// with page-by-page appending. The backend rejects an empty query (400), so
/// nothing is sent until there's something to send.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  static const _debounce = Duration(milliseconds: 400);

  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  Timer? _debounceTimer;
  String _query = '';
  int _page = 1;
  bool _loading = false;
  bool _loadingMore = false;
  bool _exhausted = false;
  Object? _error;
  List<Show> _results = const [];

  /// Guards against a stale response from a superseded query overwriting a
  /// newer one — only the most recent request's results are accepted.
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialQuery ?? '';
    _scrollController.addListener(_onScroll);
    if (_controller.text.trim().isNotEmpty) _run(_controller.text.trim());
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) _loadMore();
  }

  void _onChanged(String value) {
    _debounceTimer?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _query = '';
        _results = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    _debounceTimer = Timer(_debounce, () => _run(query));
  }

  Future<void> _run(String query) async {
    final id = ++_requestId;
    setState(() {
      _query = query;
      _page = 1;
      _loading = true;
      _exhausted = false;
      _error = null;
    });

    try {
      final results = await ref.read(contentApiProvider).search(
            query,
            provider: ref.read(activeProviderNameProvider),
            page: 1,
          );
      if (!mounted || id != _requestId) return;
      setState(() {
        _results = results.whereType<Show>().toList();
        _loading = false;
        _exhausted = results.isEmpty;
      });
    } catch (err) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _error = err;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _exhausted || _query.isEmpty) return;

    final id = _requestId;
    setState(() => _loadingMore = true);

    try {
      final next = _page + 1;
      final results = await ref.read(contentApiProvider).search(
            _query,
            provider: ref.read(activeProviderNameProvider),
            page: next,
          );
      if (!mounted || id != _requestId) return;

      final shows = results.whereType<Show>().toList();
      setState(() {
        _page = next;
        _loadingMore = false;
        _exhausted = shows.isEmpty;
        _results = [..._results, ...shows];
      });
    } catch (_) {
      if (!mounted || id != _requestId) return;
      // A failed "load more" leaves what's already on screen alone; the next
      // scroll to the bottom retries.
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A provider switch changes what "search" even means — rerun it.
    ref.listen(activeProviderNameProvider, (_, __) {
      if (_query.isNotEmpty) _run(_query);
    });

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _controller,
                autofocus: widget.initialQuery == null,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: (value) {
                  _debounceTimer?.cancel();
                  if (value.trim().isNotEmpty) _run(value.trim());
                },
                decoration: InputDecoration(
                  hintText: 'Search movies and series',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _controller.clear();
                            _onChanged('');
                          },
                        ),
                ),
              ),
            ),
            const ProviderPicker(),
            const SizedBox(height: 8),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_query.isEmpty) {
      return const EmptyState(
        message: 'Type to search the selected provider.',
        icon: Icons.search,
      );
    }
    if (_loading) return const LoadingState();
    if (_error != null) {
      return ErrorState(error: _error!, onRetry: () => _run(_query));
    }
    if (_results.isEmpty) {
      return EmptyState(message: 'Nothing found for "$_query".');
    }

    final activeProvider = ref.watch(activeProviderNameProvider);

    return FocusTraversalGroup(
      child: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 140,
          childAspectRatio: 0.55,
          crossAxisSpacing: 10,
          mainAxisSpacing: 14,
        ),
        itemCount: _results.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _results.length) {
            return const Center(child: CircularProgressIndicator());
          }
          final show = _results[i];
          return PosterCard(
            show: show,
            width: 140,
            // The active provider, not `show.providerName` — see the note on
            // `HomeScreen._openDetails`.
            onTap: () => context.push(
                '/details/$activeProvider/${Uri.encodeComponent(show.id)}'),
          );
        },
      ),
    );
  }
}
