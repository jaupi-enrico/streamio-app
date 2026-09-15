import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../state/core_providers.dart';

/// The source picker — `home.js`'s `.provider-bar`. Switching invalidates every
/// content provider downstream, so the screen refetches against the new source.
///
/// **One trigger plus a menu, not a chip per source.** A chip row was fine at
/// four sources and is not at eight: on a phone every source past the third sat
/// off-screen behind a horizontal scroll with nothing indicating it was there,
/// and on a TV reaching the last one cost a dozen D-pad presses. The button
/// names the current source; the menu is the only place that has to be as long
/// as the catalogue.
///
/// The language of the selected source stays in the bar as chips rather than
/// living in the menu: the picker is how most of the app switches source, and
/// a language buried one level deeper is one most people never find. Only the
/// selected family's languages are shown, so the row is at most a handful of
/// chips wide and never the whole catalogue.
class ProviderPicker extends ConsumerWidget {
  const ProviderPicker({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final familiesAsync = ref.watch(providerFamiliesProvider);
    final active = ref.watch(activeProviderNameProvider);

    return familiesAsync.maybeWhen(
      data: (families) {
        if (families.length <= 1) return const SizedBox.shrink();

        final selected = families.cast<ProviderFamily?>().firstWhere(
              (family) => family!.contains(active),
              orElse: () => null,
            );

        return SizedBox(
          height: 44,
          child: Row(
            children: [
              Padding(
                padding: EdgeInsets.only(left: padding.left),
                child: _SourceButton(families: families, active: active),
              ),
              if (selected != null && selected.hasLanguageChoice)
                Expanded(
                  child: _LanguageChips(
                    family: selected,
                    active: active,
                    padding: EdgeInsets.only(left: 8, right: padding.right),
                  ),
                ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// The trigger: what is selected, and the way to everything else.
class _SourceButton extends ConsumerStatefulWidget {
  const _SourceButton({required this.families, required this.active});

  final List<ProviderFamily> families;
  final String active;

  @override
  ConsumerState<_SourceButton> createState() => _SourceButtonState();
}

class _SourceButtonState extends ConsumerState<_SourceButton> {
  final _menu = MenuController();

  void _select(String slug) {
    ref.read(activeProviderNameProvider.notifier).setProvider(slug);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = widget.active;
    final selected = widget.families.cast<ProviderFamily?>().firstWhere(
          (family) => family!.contains(active),
          orElse: () => null,
        );

    return MenuAnchor(
      controller: _menu,
      menuChildren: [
        for (final family in widget.families)
          MenuItemButton(
            // The menu opens into its own overlay, which directional traversal
            // won't enter on its own: without a node claiming focus, a remote's
            // next press goes nowhere and the menu is unusable on a TV.
            autofocus: family.contains(active),
            leadingIcon: Icon(
              family.contains(active) ? Icons.check : null,
              size: 18,
            ),
            trailingIcon: family.hasLanguageChoice
                ? Text('${family.languages.length} languages',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.hintColor))
                : null,
            // Selecting a source activates the language already chosen within
            // it, so leaving a source and coming back doesn't reset it.
            onPressed: () => _select(family.targetLanguage(active).slug),
            child: Text(family.displayName),
          ),
      ],
      child: OutlinedButton.icon(
        onPressed: () => _menu.isOpen ? _menu.close() : _menu.open(),
        icon: const Icon(Icons.tune, size: 18),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Constrained: a long name must not push the language chips off a
            // phone-width row.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(
                selected?.displayName ?? 'Source',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}

/// The selected source's languages, one tap each.
class _LanguageChips extends ConsumerWidget {
  const _LanguageChips({
    required this.family,
    required this.active,
    required this.padding,
  });

  final ProviderFamily family;
  final String active;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: padding,
      itemCount: family.languages.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (context, i) {
        final language = family.languages[i];
        return Center(
          child: ChoiceChip(
            label: Text(language.label),
            selected: language.slug == active,
            onSelected: (_) => ref
                .read(activeProviderNameProvider.notifier)
                .setProvider(language.slug),
          ),
        );
      },
    );
  }
}
