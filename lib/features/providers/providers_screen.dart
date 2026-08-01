import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/async_states.dart';
import '../../shared/widgets/provider_chips.dart';
import '../../state/core_providers.dart';
import '../../state/server_config_provider.dart';

/// `providers.html` / `providers.js`: pick which site content comes from.
///
/// The choice is client-side only — `provider.router.ts`'s `PUT /current` and
/// `POST /set-provider` validate a name and return, they never persist it —
/// so selecting one writes to shared_preferences and every content request
/// from then on carries `?provider=`.
class ProvidersScreen extends ConsumerWidget {
  const ProvidersScreen({super.key});

  /// A one-line description per source, matching how `providers.html`
  /// introduces each one.
  static String _describe(String name) => switch (name) {
        'streamingcommunity' => 'Italian movies and series, dubbed and subbed.',
        'streamingcommunity-en' => 'The English-language StreamingCommunity mirror.',
        'animeunity' => 'Anime with Italian dub and sub.',
        'animesaturn' => 'Anime, direct sources.',
        'hentaisaturn' => 'Adults-only anime.',
        'vavoo' => 'Live TV channels.',
        'iptvorg' => 'Open IPTV channel directory.',
        _ => 'Content source.',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providersAsync = ref.watch(providerListProvider);
    final active = ref.watch(activeProviderNameProvider);
    final serverUrl = ref.watch(currentServerUrlProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Providers')),
      body: providersAsync.when(
        loading: () => const LoadingState(),
        error: (error, _) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(providerListProvider),
        ),
        data: (providers) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            for (final name in providers)
              ListTile(
                onTap: () {
                  ref.read(activeProviderNameProvider.notifier).setProvider(name);
                  showToast(context, '${ProviderChips.label(name)} selected');
                },
                leading: Icon(
                  name == active
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: name == active
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).hintColor,
                ),
                title: Text(ProviderChips.label(name)),
                subtitle: Text(_describe(name)),
              ),
            const Divider(height: 32),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('Server'),
              subtitle: Text(serverUrl ?? 'Not configured'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/server'),
            ),
          ],
        ),
      ),
    );
  }
}
