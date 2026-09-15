import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cast/cast_service.dart';
import '../../core/config/cast_receiver_config.dart';
import '../../shared/widgets/async_states.dart';
import '../../state/cast_providers.dart';

/// Where a custom Chromecast receiver application id is entered.
///
/// The id normally arrives from the server, but a receiver is registered
/// against a Google Cast console account rather than against a Streamio
/// install, so whoever runs the app is not necessarily whoever can change
/// `CAST_RECEIVER_APP_ID` on the server. This screen lets the id be set on the
/// device instead. See [CastReceiverConfig].
class CastSettingsScreen extends ConsumerStatefulWidget {
  const CastSettingsScreen({super.key});

  @override
  ConsumerState<CastSettingsScreen> createState() => _CastSettingsScreenState();
}

class _CastSettingsScreenState extends ConsumerState<CastSettingsScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  /// The stored override the field was last seeded from, so a rebuild doesn't
  /// stomp on what the user is currently typing.
  String? _seededFrom;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final appId = CastReceiverConfig.normalize(_controller.text);
    if (appId == null) return;

    setState(() => _saving = true);
    final ok = await runGuarded(
      context,
      () => ref.read(castReceiverOverrideProvider.notifier).set(appId),
      successMessage: 'Receiver id saved',
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _controller.text = appId;
    });
  }

  Future<void> _clear() async {
    setState(() => _saving = true);
    final ok = await runGuarded(
      context,
      () => ref.read(castReceiverOverrideProvider.notifier).clear(),
      successMessage: 'Using the server\'s receiver id again',
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overrideAsync = ref.watch(castReceiverOverrideProvider);
    final override = overrideAsync.value;

    // Seed the field once from storage, and again whenever the stored value
    // changes underneath us (cleared, or saved from elsewhere).
    if (overrideAsync.hasValue && _seededFrom != override) {
      _seededFrom = override;
      _controller.text = override ?? '';
    }

    final availableAsync = ref.watch(castAvailableProvider);
    final service = ref.watch(castServiceProvider);
    final info = ref.watch(castConfigInfoProvider);

    // The Cast SDK builds its shared instance once per process, so an id
    // changed after that only takes effect on the next launch.
    final live = service.liveAppId;
    final pending = override ?? info?.serverAppId;
    final needsRestart =
        live != null && pending != null && pending != live;

    return Scaffold(
      appBar: AppBar(title: const Text('Chromecast')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          if (!CastService.isSupported)
            const _Note(
              icon: Icons.info_outline,
              text: 'Casting is only available on Android and iOS. The '
                  'receiver id below is still saved for those platforms.',
            )
          else
            availableAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => _Note(
                icon: Icons.error_outline,
                isError: true,
                text: ErrorState.messageFor(error),
              ),
              data: (available) => available
                  ? const SizedBox.shrink()
                  : _Note(
                      icon: Icons.error_outline,
                      isError: true,
                      text: service.lastError ??
                          'The Cast SDK could not be started on this device.',
                    ),
            ),

          const SizedBox(height: 16),
          Text('Receiver app ID', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'The eight-character ID of the custom receiver registered in the '
            'Google Cast console. Leave this empty to use whatever the server '
            'reports.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),

          Form(
            key: _formKey,
            child: TextFormField(
              controller: _controller,
              enabled: !_saving,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9A-Fa-f]')),
                UpperCaseFormatter(),
              ],
              decoration: const InputDecoration(
                labelText: 'Custom receiver ID',
                hintText: 'e.g. BF64D6B2',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) return 'Enter an ID, or use "Use server\'s ID".';
                if (!CastReceiverConfig.isValid(text)) {
                  return 'A Cast app ID is 8 hexadecimal characters (0-9, A-F).';
                }
                return null;
              },
              onFieldSubmitted: (_) => _save(),
            ),
          ),

          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('Save'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving || override == null ? null : _clear,
                  child: const Text('Use server\'s ID'),
                ),
              ),
            ],
          ),

          if (needsRestart) ...[
            const SizedBox(height: 16),
            const _Note(
              icon: Icons.restart_alt,
              text: 'Saved. The Cast SDK only reads the receiver ID once per '
                  'launch, so close and reopen the app for this to take '
                  'effect.',
            ),
          ],

          const SizedBox(height: 28),
          Text('Current configuration', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _Row(label: 'In use now', value: live ?? 'not started'),
          _Row(
            label: 'Source',
            value: switch (info?.source) {
              CastAppIdSource.override => 'this device',
              CastAppIdSource.server => 'server (/api/cast-config)',
              CastAppIdSource.fallback => 'Streamio shared receiver (built in)',
              null => 'unknown',
            },
          ),
          _Row(label: 'Server reports', value: info?.serverAppId ?? 'nothing'),
          _Row(
            label: 'Cast proxy',
            value: (info?.proxyBase.isNotEmpty ?? false)
                ? info!.proxyBase
                : 'none — streams cast unproxied',
          ),

          if (info != null && info.proxyBase.isEmpty) ...[
            const SizedBox(height: 12),
            const _Note(
              icon: Icons.warning_amber_outlined,
              text: 'Without a proxy base the receiver gets the provider URL '
                  'directly, which most CDNs here reject. Check that APP_URL '
                  'is set on the server and that /api/cast-config answers.',
            ),
          ],
        ],
      ),
    );
  }
}

/// Cast app IDs are uppercase; typing lowercase hex should just work.
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.isError = false});

  final IconData icon;
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isError ? scheme.error : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isError ? scheme.errorContainer : scheme.surfaceContainerHighest)
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
