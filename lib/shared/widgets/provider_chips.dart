import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/core_providers.dart';

/// The horizontal source picker — `home.js`'s `.provider-bar` /
/// `renderProviderChips()`. Switching invalidates every content provider
/// downstream, so the page refetches against the new source.
class ProviderChips extends ConsumerWidget {
  const ProviderChips({super.key, this.padding = const EdgeInsets.symmetric(horizontal: 16)});

  final EdgeInsets padding;

  /// The backend's internal names are lowercase and unspaced; these are what
  /// the web UI labels them.
  static String label(String name) => switch (name) {
        'streamingcommunity' => 'StreamingCommunity',
        'streamingcommunity-en' => 'StreamingCommunity EN',
        'animeunity' => 'AnimeUnity',
        'animesaturn' => 'AnimeSaturn',
        'hentaisaturn' => 'HentaiSaturn',
        'vavoo' => 'Vavoo',
        'iptvorg' => 'IPTV-Org',
        _ => name,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providersAsync = ref.watch(providerListProvider);
    final active = ref.watch(activeProviderNameProvider);

    return providersAsync.maybeWhen(
      data: (providers) {
        if (providers.length <= 1) return const SizedBox.shrink();
        return SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: padding,
            itemCount: providers.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final name = providers[i];
              return ChoiceChip(
                label: Text(label(name)),
                selected: name == active,
                onSelected: (_) =>
                    ref.read(activeProviderNameProvider.notifier).setProvider(name),
              );
            },
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
