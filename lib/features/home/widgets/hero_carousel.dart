import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/models.dart';

/// Mirrors home.js's `buildHero()` / dots / `setInterval` auto-advance.
class HeroCarousel extends StatefulWidget {
  const HeroCarousel({super.key, required this.items, required this.onTap});

  final List<Show> items;
  final void Function(Show show) onTap;

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  late final PageController _controller = PageController();
  Timer? _timer;
  int _index = 0;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _startAutoAdvance();
  }

  void _startAutoAdvance() {
    _timer?.cancel();
    // Paused while focused so a D-pad user isn't fighting the auto-advance
    // while trying to page manually (see _pageBy).
    if (widget.items.length <= 1 || _focused) return;
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_index + 1) % widget.items.length;
      _controller.animateToPage(next,
          duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
    });
  }

  void _handleFocusChange(bool focused) {
    setState(() => _focused = focused);
    _startAutoAdvance();
  }

  void _pageBy(int delta) {
    if (!_controller.hasClients || widget.items.length <= 1) return;
    final next = (_index + delta) % widget.items.length;
    _controller.animateToPage(next < 0 ? next + widget.items.length : next,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  void didUpdateWidget(covariant HeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      _index = 0;
      _startAutoAdvance();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // Bound via Shortcuts/Actions, not a raw key listener, so these win over
  // Flutter's default arrow-key focus traversal once this widget has focus —
  // same reasoning as the watch screen's transport shortcuts.
  Map<ShortcutActivator, Intent> get _carouselShortcuts => {
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const _PageIntent(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const _PageIntent(1),
      };

  Map<Type, Action<Intent>> get _carouselActions => {
        _PageIntent: CallbackAction<_PageIntent>(
          onInvoke: (intent) => _pageBy(intent.delta),
        ),
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onTap(widget.items[_index]),
        ),
      };

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final primary = Theme.of(context).colorScheme.primary;

    return Shortcuts(
      shortcuts: _carouselShortcuts,
      child: Actions(
        actions: _carouselActions,
        child: Focus(
          onFocusChange: _handleFocusChange,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: _focused ? primary : Colors.transparent,
                width: 3,
              ),
            ),
            child: SizedBox(
              height: 420,
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _controller,
                    itemCount: widget.items.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) {
                      final show = widget.items[i];
                      return GestureDetector(
                        onTap: () => widget.onTap(show),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (show.poster != null)
                              CachedNetworkImage(
                                  imageUrl: show.poster!, fit: BoxFit.cover)
                            else
                              Container(color: const Color(0xFF1E2430)),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Theme.of(context)
                                        .scaffoldBackgroundColor
                                        .withValues(alpha: 0.95),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 20,
                              right: 20,
                              bottom: 28,
                              child: Text(
                                show.title,
                                style: Theme.of(context).textTheme.displaySmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    // One dot per item, and `items` is a whole provider
                    // category — 60+ titles on some sources, which is wider
                    // than the screen and overflowed the row. scaleDown only
                    // acts when the dots genuinely don't fit, so the common
                    // case (a handful of featured titles) is unchanged.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(widget.items.length, (i) {
                          final active = i == _index;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: active ? 18 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: active ? Colors.white : Colors.white38,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageIntent extends Intent {
  const _PageIntent(this.delta);

  final int delta;
}
