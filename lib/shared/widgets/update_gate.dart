import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../routing/app_router.dart' show rootNavigatorKey;
import '../../state/update_providers.dart';

/// Wraps the whole app to handle the server's client-version policy.
///
/// Two distinct cases, deliberately handled differently:
///
///  * **Blocked** — the server is returning 426, so nothing works. Replaces
///    the UI entirely; there is nothing useful left underneath.
///  * **Update available** — a newer build exists but this one still works.
///    Offered once per launch as a dismissible dialog, never repeated, and
///    never shown at all without a download URL to send the user to.
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  /// Local rather than a provider: this is decided during build, and Riverpod
  /// rightly forbids mutating a provider from a widget life-cycle.
  bool _promptShown = false;

  @override
  Widget build(BuildContext context) {
    final blocked = ref.watch(clientOutdatedProvider);
    if (blocked != null) {
      return _BlockedScreen(
        message: blocked.message,
        latest: blocked.latest,
        notes: blocked.notes,
        downloadUrl: blocked.downloadUrl,
      );
    }

    // A launch check that comes back "required" while enforcement is on means
    // the same thing a 426 does — the server just hasn't been asked for
    // anything else yet.
    final info = ref.watch(updateCheckProvider).value;
    if (info != null && info.isBlocked) {
      return _BlockedScreen(
        message:
            'This version of the app (${info.currentVersion ?? 'unknown'}) is no longer supported.',
        latest: info.latest,
        notes: info.notes,
        downloadUrl: info.downloadUrl,
      );
    }

    if (info != null && info.shouldPrompt) {
      _maybePrompt(info.latest, info.notes, info.downloadUrl!);
    }

    return widget.child;
  }

  void _maybePrompt(String? latest, String? notes, String downloadUrl) {
    if (_promptShown) return;
    _promptShown = true;

    // Deferred: this runs during build, and showing a dialog synchronously
    // from build throws.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Not `context`: this widget wraps `child` in `MaterialApp.router`'s
      // `builder`, which places it *above* the Router's Navigator in the
      // tree, not inside it — `showDialog(context: context)` would find no
      // Navigator ancestor and silently fail to show anything. The router's
      // own navigator key gives a context that's actually inside it.
      final navContext = rootNavigatorKey.currentContext;
      if (navContext == null) return;
      showDialog<void>(
        context: navContext,
        builder: (context) => AlertDialog(
          title: const Text('Update available'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(latest == null
                  ? 'A newer version of Streamio is available.'
                  : 'Streamio $latest is available.'),
              if (notes != null) ...[
                const SizedBox(height: 12),
                Text(notes, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openDownload(downloadUrl);
              },
              child: const Text('Update'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _openDownload(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Full-screen dead end. No navigation out of it on purpose — every other
/// screen would only produce more 426s.
class _BlockedScreen extends StatelessWidget {
  const _BlockedScreen({
    required this.message,
    required this.latest,
    required this.notes,
    required this.downloadUrl,
  });

  final String message;
  final String? latest;
  final String? notes;
  final String? downloadUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.system_update, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 24),
                  Text('Update required',
                      style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Text(message,
                      style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
                  if (latest != null) ...[
                    const SizedBox(height: 8),
                    Text('Latest version: $latest',
                        style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                  ],
                  if (notes != null) ...[
                    const SizedBox(height: 12),
                    Text(notes!,
                        style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 28),
                  if (downloadUrl != null)
                    FilledButton.icon(
                      onPressed: () async {
                        final uri = Uri.tryParse(downloadUrl!);
                        if (uri != null) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                      icon: const Icon(Icons.download),
                      label: const Text('Download the new version'),
                    )
                  else
                    Text(
                      'Contact the server administrator for the new version.',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
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

/// Re-exported so callers that catch this don't need the api_client import.
typedef OutdatedClient = ClientOutdatedException;
