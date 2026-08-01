import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../shared/widgets/async_states.dart';
import '../../state/api_providers.dart';

final _hostingPointsProvider =
    FutureProvider.autoDispose<List<HostingPoint>>((ref) async {
  return ref.watch(settingsApiProvider).hostingPoints();
});

final _syncSettingsProvider = FutureProvider.autoDispose<SyncSettings>((ref) async {
  return ref.watch(settingsApiProvider).syncSettings();
});

final _powerSettingsProvider =
    FutureProvider.autoDispose<PowerSettings>((ref) async {
  return ref.watch(settingsApiProvider).powerSettings();
});

final _powerStatusProvider = FutureProvider.autoDispose<PowerStatus>((ref) async {
  return ref.watch(settingsApiProvider).powerStatus();
});

/// Server administration — the `panel-admin` half of `account.html`.
///
/// The whole `/api/settings` router is gated by `requireAuth + requireAdmin`
/// (the `ADMIN_EMAILS` allowlist), so a non-admin lands on a 403 here; the
/// entry point on the account screen is hidden for them.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Server admin')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(_hostingPointsProvider)
            ..invalidate(_syncSettingsProvider)
            ..invalidate(_powerSettingsProvider)
            ..invalidate(_powerStatusProvider);
          await ref.read(_hostingPointsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: const [
            _HostingPointsSection(),
            Divider(height: 32),
            _SyncSection(),
            Divider(height: 32),
            _PowerSection(),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (subtitle != null)
                  Text(subtitle!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(context).hintColor)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _HostingPointsSection extends ConsumerWidget {
  const _HostingPointsSection();

  Future<void> _edit(BuildContext context, WidgetRef ref, {HostingPoint? point}) async {
    final result = await showDialog<_HostingPointDraft>(
      context: context,
      builder: (context) => _HostingPointDialog(point: point),
    );
    if (result == null || !context.mounted) return;

    final api = ref.read(settingsApiProvider);
    final ok = await runGuarded(
      context,
      () => point == null
          ? api.addHostingPoint(
              name: result.name,
              url: result.url,
              sharedSecret: result.sharedSecret,
              enabled: result.enabled,
            )
          : api.updateHostingPoint(
              point.id,
              name: result.name,
              url: result.url,
              enabled: result.enabled,
              sharedSecret:
                  result.sharedSecret.isEmpty ? null : result.sharedSecret,
            ),
      successMessage: 'Hosting point saved',
    );
    if (ok) ref.invalidate(_hostingPointsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pointsAsync = ref.watch(_hostingPointsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          'Hosting points',
          subtitle: 'Peer Streamio servers this one syncs user libraries with.',
          trailing: IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add',
            onPressed: () => _edit(context, ref),
          ),
        ),
        pointsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ErrorState(
              error: error,
              scrollable: false,
              onRetry: () => ref.invalidate(_hostingPointsProvider),
            ),
          ),
          data: (points) {
            if (points.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No peer servers configured.'),
              );
            }
            return Column(
              children: [
                for (final point in points)
                  ListTile(
                    leading: Icon(
                      point.enabled ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                      color: point.enabled
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).hintColor,
                    ),
                    title: Text(point.name),
                    subtitle: Text(
                      [
                        point.url,
                        if (point.lastSyncStatus != null)
                          'Last sync: ${point.lastSyncStatus}',
                        if (point.lastSyncError != null) point.lastSyncError!,
                      ].join('\n'),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    isThreeLine: point.lastSyncError != null,
                    onTap: () => _edit(context, ref, point: point),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await runGuarded(
                          context,
                          () => ref
                              .read(settingsApiProvider)
                              .deleteHostingPoint(point.id),
                          successMessage: 'Hosting point removed',
                        );
                        if (ok) ref.invalidate(_hostingPointsProvider);
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SyncSection extends ConsumerWidget {
  const _SyncSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(_syncSettingsProvider);

    Future<void> save(SyncSettings settings) async {
      final ok = await runGuarded(
        context,
        () => ref.read(settingsApiProvider).updateSyncSettings(settings),
        successMessage: 'Sync settings saved',
      );
      if (ok) ref.invalidate(_syncSettingsProvider);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(
          'Library sync',
          subtitle:
              'Pull watchlists, ratings and history from enabled peers. Matching is by '
              'email, and nothing is ever deleted by a sync.',
        ),
        settingsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ErrorState(
              error: error,
              scrollable: false,
              onRetry: () => ref.invalidate(_syncSettingsProvider),
            ),
          ),
          data: (settings) => Column(
            children: [
              SwitchListTile(
                value: settings.enabled,
                onChanged: (enabled) => save(settings.copyWith(enabled: enabled)),
                title: const Text('Scheduled sync'),
              ),
              ListTile(
                title: const Text('Interval'),
                subtitle: Text('${settings.intervalMinutes} minutes'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final minutes = await _promptForNumber(
                    context,
                    title: 'Sync interval',
                    label: 'Minutes',
                    initial: settings.intervalMinutes,
                  );
                  if (minutes != null) {
                    await save(settings.copyWith(intervalMinutes: minutes));
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PowerSection extends ConsumerWidget {
  const _PowerSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(_powerSettingsProvider);
    final statusAsync = ref.watch(_powerStatusProvider);

    Future<void> save(PowerSettings settings) async {
      final ok = await runGuarded(
        context,
        () => ref.read(settingsApiProvider).updatePowerSettings(settings),
        successMessage: 'Power settings saved',
      );
      if (ok) ref.invalidate(_powerSettingsProvider);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(
          'Power',
          subtitle:
              'Idle-shutdown policy. The server runs in Docker and can\'t power off its '
              'own host — the host-side power-controller polls this and does it.',
        ),
        settingsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ErrorState(
              error: error,
              scrollable: false,
              onRetry: () => ref.invalidate(_powerSettingsProvider),
            ),
          ),
          data: (settings) => Column(
            children: [
              SwitchListTile(
                value: settings.enabled,
                onChanged: (enabled) => save(settings.copyWith(enabled: enabled)),
                title: const Text('Idle shutdown'),
              ),
              ListTile(
                title: const Text('Idle threshold'),
                subtitle: Text('${settings.idleMinutes} minutes'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final minutes = await _promptForNumber(
                    context,
                    title: 'Idle threshold',
                    label: 'Minutes',
                    initial: settings.idleMinutes,
                  );
                  if (minutes != null) {
                    await save(settings.copyWith(idleMinutes: minutes));
                  }
                },
              ),
              ListTile(
                title: const Text('Minimum uptime'),
                subtitle: Text('${settings.minUptimeMinutes} minutes'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final minutes = await _promptForNumber(
                    context,
                    title: 'Minimum uptime',
                    label: 'Minutes',
                    initial: settings.minUptimeMinutes,
                  );
                  if (minutes != null) {
                    await save(settings.copyWith(minUptimeMinutes: minutes));
                  }
                },
              ),
              ListTile(
                title: const Text('Current status'),
                subtitle: Text(statusAsync.maybeWhen(
                  data: (status) => status.shouldShutdown
                      ? 'Shutdown pending${status.reason != null ? ' — ${status.reason}' : ''}'
                      : 'Running',
                  orElse: () => '…',
                )),
                trailing: IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.invalidate(_powerStatusProvider),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Shut down the server host?'),
                              content: const Text(
                                  'The power-controller will power off the machine on its '
                                  'next poll. You will lose access until it is turned back '
                                  'on physically.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.of(context).pop(true),
                                  child: const Text('Shut down'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true || !context.mounted) return;
                          final ok = await runGuarded(
                            context,
                            () => ref
                                .read(settingsApiProvider)
                                .requestShutdown(reason: 'Requested from the app'),
                            successMessage: 'Shutdown requested',
                          );
                          if (ok) ref.invalidate(_powerStatusProvider);
                        },
                        icon: const Icon(Icons.power_settings_new),
                        label: const Text('Shut down'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final ok = await runGuarded(
                            context,
                            () => ref.read(settingsApiProvider).cancelShutdown(),
                            successMessage: 'Shutdown cancelled',
                          );
                          if (ok) ref.invalidate(_powerStatusProvider);
                        },
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Cancel'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<int?> _promptForNumber(
  BuildContext context, {
  required String title,
  required String label,
  required int initial,
}) async {
  final controller = TextEditingController(text: '$initial');
  final result = await showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        autofocus: true,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final value = int.tryParse(controller.text.trim());
            if (value != null && value > 0) Navigator.of(context).pop(value);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

class _HostingPointDraft {
  const _HostingPointDraft({
    required this.name,
    required this.url,
    required this.sharedSecret,
    required this.enabled,
  });

  final String name;
  final String url;
  final String sharedSecret;
  final bool enabled;
}

class _HostingPointDialog extends StatefulWidget {
  const _HostingPointDialog({this.point});

  final HostingPoint? point;

  @override
  State<_HostingPointDialog> createState() => _HostingPointDialogState();
}

class _HostingPointDialogState extends State<_HostingPointDialog> {
  late final _name = TextEditingController(text: widget.point?.name ?? '');
  late final _url = TextEditingController(text: widget.point?.url ?? '');
  final _secret = TextEditingController();
  late bool _enabled = widget.point?.enabled ?? true;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.point == null;

    return AlertDialog(
      title: Text(isNew ? 'Add hosting point' : 'Edit hosting point'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                  labelText: 'URL', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _secret,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Shared secret',
                // The server never returns the stored secret, so an edit that
                // leaves this blank keeps whatever is already saved.
                helperText: isNew ? null : 'Leave blank to keep the current secret',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
              title: const Text('Enabled'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            final url = _url.text.trim();
            if (name.isEmpty || url.isEmpty) return;
            if (isNew && _secret.text.trim().isEmpty) return;
            Navigator.of(context).pop(_HostingPointDraft(
              name: name,
              url: url,
              sharedSecret: _secret.text.trim(),
              enabled: _enabled,
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
