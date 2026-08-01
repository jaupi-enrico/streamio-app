import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/async_states.dart';
import '../../../state/api_providers.dart';
import '../account_providers.dart';

/// Per-user preferences — a free-form key/value bag on the server
/// (`GET/PUT/DELETE /api/account/preferences/:key`), which is why this is a
/// generic editor with an "add" action rather than a fixed settings form.
/// It matches what `account.html` does with its "+ Add Custom" button.
class PreferencesTab extends ConsumerWidget {
  const PreferencesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(preferencesProvider);

    Future<void> refresh() async {
      ref.invalidate(preferencesProvider);
      await ref.read(preferencesProvider.future);
    }

    Future<void> edit({String? key, String? value}) async {
      final result = await showDialog<({String key, String value})>(
        context: context,
        builder: (context) => _PreferenceDialog(initialKey: key, initialValue: value),
      );
      if (result == null || !context.mounted) return;

      final ok = await runGuarded(
        context,
        () => ref
            .read(accountApiProvider)
            .setPreference(result.key, result.value),
        successMessage: 'Preference saved',
      );
      if (ok) await refresh();
    }

    Future<void> remove(String key) async {
      final ok = await runGuarded(
        context,
        () => ref.read(accountApiProvider).deletePreference(key),
        successMessage: 'Preference removed',
      );
      if (ok) await refresh();
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: refresh,
        child: prefsAsync.when(
          loading: () => const LoadingState(),
          error: (error, _) => ErrorState(error: error, onRetry: refresh),
          data: (prefs) {
            if (prefs.isEmpty) {
              return EmptyState(
                message: 'No preferences saved on this account.',
                icon: Icons.tune,
                action: FilledButton.tonal(
                  onPressed: () => edit(),
                  child: const Text('Add one'),
                ),
              );
            }

            final keys = prefs.keys.toList()..sort();
            return ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: keys.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final key = keys[i];
                final value = prefs[key];
                return ListTile(
                  title: Text(key),
                  subtitle: Text('$value',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => edit(key: key, value: '$value'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Remove',
                    onPressed: () => remove(key),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () => edit(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _PreferenceDialog extends StatefulWidget {
  const _PreferenceDialog({this.initialKey, this.initialValue});

  final String? initialKey;
  final String? initialValue;

  @override
  State<_PreferenceDialog> createState() => _PreferenceDialogState();
}

class _PreferenceDialogState extends State<_PreferenceDialog> {
  late final _key = TextEditingController(text: widget.initialKey ?? '');
  late final _value = TextEditingController(text: widget.initialValue ?? '');

  @override
  void dispose() {
    _key.dispose();
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialKey == null ? 'Add preference' : 'Edit preference'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _key,
            // The key is the row's identity server-side; changing it would
            // create a second row rather than rename this one.
            enabled: widget.initialKey == null,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Key',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _value,
            decoration: const InputDecoration(
              labelText: 'Value',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final key = _key.text.trim();
            if (key.isEmpty) return;
            Navigator.of(context).pop((key: key, value: _value.text));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
