import 'dart:convert';

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

    Future<void> save(String key, Object value) async {
      final ok = await runGuarded(
        context,
        () => ref.read(accountApiProvider).setPreference(key, value),
        successMessage: 'Preference saved',
      );
      if (ok) await refresh();
    }

    Future<void> edit({String? key, Object? value}) async {
      final result = await showDialog<({String key, Object value})>(
        context: context,
        builder: (context) => _PreferenceDialog(initialKey: key, initialValue: value),
      );
      if (result == null || !context.mounted) return;
      await save(result.key, result.value);
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
                final removeButton = IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Remove',
                  onPressed: () => remove(key),
                );

                // A boolean is toggled in place — routing it through the text
                // dialog is what used to save it back as the string "true".
                if (value is bool) {
                  return SwitchListTile(
                    title: Text(key),
                    value: value,
                    onChanged: (next) => save(key, next),
                    secondary: removeButton,
                  );
                }

                return ListTile(
                  title: Text(key),
                  subtitle: Text(_display(value),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => edit(key: key, value: value),
                  trailing: removeButton,
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

/// How a value is edited. The bag is JSON, so the type has to be part of the
/// edit — a value typed into a bare text field would always save as a string
/// and quietly change `true` into `"true"`.
enum _PrefType { text, number, boolean, json }

String _display(Object? value) =>
    value is String ? value : jsonEncode(value);

_PrefType _typeOf(Object? value) {
  if (value is bool) return _PrefType.boolean;
  if (value is num) return _PrefType.number;
  if (value is String || value == null) return _PrefType.text;
  return _PrefType.json;
}

class _PreferenceDialog extends StatefulWidget {
  const _PreferenceDialog({this.initialKey, this.initialValue});

  final String? initialKey;
  final Object? initialValue;

  @override
  State<_PreferenceDialog> createState() => _PreferenceDialogState();
}

class _PreferenceDialogState extends State<_PreferenceDialog> {
  late final _key = TextEditingController(text: widget.initialKey ?? '');
  late final _value = TextEditingController(
    text: widget.initialValue == null ? '' : _display(widget.initialValue),
  );
  late _PrefType _type = _typeOf(widget.initialValue);
  late bool _flag = widget.initialValue is bool && widget.initialValue as bool;
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    _value.dispose();
    super.dispose();
  }

  /// The typed value, or null when the text doesn't parse as the chosen type.
  Object? _parsed() {
    final text = _value.text.trim();
    switch (_type) {
      case _PrefType.text:
        return _value.text;
      case _PrefType.boolean:
        return _flag;
      case _PrefType.number:
        return num.tryParse(text);
      case _PrefType.json:
        try {
          return jsonDecode(text) as Object?;
        } on FormatException {
          return null;
        }
    }
  }

  void _submit() {
    final key = _key.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'A key is required.');
      return;
    }
    final value = _parsed();
    if (value == null) {
      setState(() => _error = _type == _PrefType.number
          ? 'Not a number.'
          : 'Not valid JSON.');
      return;
    }
    Navigator.of(context).pop((key: key, value: value));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialKey == null ? 'Add preference' : 'Edit preference'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          DropdownButtonFormField<_PrefType>(
            initialValue: _type,
            decoration: const InputDecoration(
              labelText: 'Type',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: _PrefType.text, child: Text('Text')),
              DropdownMenuItem(value: _PrefType.number, child: Text('Number')),
              DropdownMenuItem(value: _PrefType.boolean, child: Text('On / off')),
              DropdownMenuItem(value: _PrefType.json, child: Text('JSON')),
            ],
            onChanged: (next) {
              if (next == null) return;
              setState(() {
                _type = next;
                _error = null;
              });
            },
          ),
          const SizedBox(height: 12),
          if (_type == _PrefType.boolean)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Value'),
              value: _flag,
              onChanged: (next) => setState(() => _flag = next),
            )
          else
            TextField(
              controller: _value,
              autocorrect: _type == _PrefType.text,
              keyboardType: _type == _PrefType.number
                  ? const TextInputType.numberWithOptions(decimal: true, signed: true)
                  : null,
              maxLines: _type == _PrefType.json ? 4 : 1,
              decoration: const InputDecoration(
                labelText: 'Value',
                border: OutlineInputBorder(),
              ),
              onSubmitted: _type == _PrefType.json ? null : (_) => _submit(),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
