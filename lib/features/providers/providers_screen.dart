import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../shared/widgets/async_states.dart';
import '../../state/core_providers.dart';
import '../../state/server_config_provider.dart';

/// `providers.html` / `providers.js`: pick which site content comes from.
///
/// The list, the labels and the blurbs all come from `GET /api/providers` —
/// a source added, renamed or retired server-side is reflected here without a
/// new build.
///
/// The server's `catalog` is flat, one entry per language variant; it is
/// grouped into families here (`groupProviderFamilies`) so a site offered in
/// several languages is one row with a language selector rather than several
/// rows that look like unrelated sources. Picking a language is picking a
/// provider slug — the language is not a separate setting.
///
/// The choice is client-side only — `provider.router.ts`'s `PUT /current` and
/// `POST /set-provider` validate a name and return, they never persist it —
/// so selecting one writes to shared_preferences and every content request
/// from then on carries `?provider=`.
class ProvidersScreen extends ConsumerWidget {
  const ProvidersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final familiesAsync = ref.watch(providerFamiliesProvider);
    final active = ref.watch(activeProviderNameProvider);
    final serverUrl = ref.watch(currentServerUrlProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Providers')),
      body: familiesAsync.when(
        loading: () => const LoadingState(),
        error: (error, _) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(providerCatalogProvider),
        ),
        data: (families) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            for (final family in families)
              _FamilyTile(family: family, active: active),
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

/// One source: the site, and — only when it has more than one — the languages
/// it can be watched in. Tapping the row selects the language already chosen
/// within this family, so coming back to a source doesn't reset it to the
/// default; tapping a language chip selects that variant outright.
class _FamilyTile extends ConsumerWidget {
  const _FamilyTile({required this.family, required this.active});

  final ProviderFamily family;
  final String active;

  void _select(BuildContext context, WidgetRef ref, ProviderLanguage language) {
    ref.read(activeProviderNameProvider.notifier).setProvider(language.slug);
    showToast(
      context,
      family.hasLanguageChoice
          ? '${family.displayName} · ${language.label} selected'
          : '${family.displayName} selected',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selected = family.activeLanguage(active);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          onTap: () => _select(context, ref, family.targetLanguage(active)),
          leading: Icon(
            selected != null
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color: selected != null ? theme.colorScheme.primary : theme.hintColor,
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(family.displayName)),
              if (family.adult) ...[
                const SizedBox(width: 8),
                const _AdultBadge(),
              ],
            ],
          ),
          subtitle: Text(family.description),
        ),
        if (family.hasLanguageChoice)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final language in family.languages)
                  ChoiceChip(
                    label: Text(language.label),
                    selected: language.slug == active,
                    onSelected: (_) => _select(context, ref, language),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Badges a whole-provider 18+ source. The server only lists these once the
/// user's `adult_content` preference is on, so seeing one means it's allowed —
/// this only says which one it is.
class _AdultBadge extends StatelessWidget {
  const _AdultBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '18+',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onErrorContainer,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
