import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/models/models.dart';
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
  /// Set by "Later"/"Update"/barrier tap, never cleared: the offer is made
  /// once per launch. Local rather than a provider because it is widget
  /// state, and because Riverpod rightly forbids mutating a provider from a
  /// widget life-cycle.
  bool _dismissed = false;

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

    final AppUpdateInfo? prompt =
        (!_dismissed && info != null && info.shouldPrompt) ? info : null;

    // Drawn into the tree rather than pushed with `showDialog`, deliberately.
    //
    // This widget sits in `MaterialApp.router`'s `builder`, which places it
    // *above* the `Router` — so there is no `Navigator` ancestor to show a
    // dialog from, and reaching sideways for the router's own navigator key
    // (`rootNavigatorKey`) does not work either: `showDialog` pushes a
    // *pageless* route, and Flutter drops pageless routes when the page they
    // are attached to is removed. GoRouter rebuilds its page list on every
    // `refreshListenable` tick, and the launch check typically lands while
    // the app is still on `/splash` — the redirect to `/` then takes the
    // dialog with it, a frame or two after it appeared.
    //
    // A `Stack` owned by this widget answers to nobody's route reconciliation.
    // `widget.child` stays at index 0 in every configuration so that showing
    // the prompt never re-creates the `Router` subtree underneath it.
    return Stack(
      fit: StackFit.expand,
      children: [
        // What a modal route does to the route below it: the app stays on
        // screen but stops being reachable, by pointer (the scrim below
        // absorbs those), by screen reader, or by D-pad — the TV build has no
        // pointer, so without this the remote would happily drive focus into
        // the UI behind the scrim. A `FocusScope` rather than `ExcludeFocus`
        // because a scope remembers its focused child and restores it when it
        // becomes focusable again, so dismissing the prompt puts the TV cursor
        // back where the user left it.
        FocusScope(
          canRequestFocus: prompt == null,
          child: ExcludeSemantics(
            excluding: prompt != null,
            child: widget.child,
          ),
        ),
        if (prompt != null)
          _UpdatePrompt(
            latest: prompt.latest,
            notes: prompt.notes,
            downloadUrl: prompt.downloadUrl!,
            onDismiss: () {
              if (mounted) setState(() => _dismissed = true);
            },
          ),
      ],
    );
  }
}

/// The optional-update dialog, as a plain widget rather than a route.
///
/// Reproduces what `showDialog` would have given us — scrim, tap-outside to
/// dismiss, fade/scale entrance — without depending on a `Navigator`. Back
/// button dismissal is the one thing not reproduced: the back press is owned
/// by the `Router` below this widget, which cannot see a modal that isn't one
/// of its routes. "Later" and the scrim both dismiss, so there is no way to
/// get stuck behind it.
class _UpdatePrompt extends StatefulWidget {
  const _UpdatePrompt({
    required this.latest,
    required this.notes,
    required this.downloadUrl,
    required this.onDismiss,
  });

  final String? latest;
  final String? notes;
  final String downloadUrl;
  final VoidCallback onDismiss;

  @override
  State<_UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends State<_UpdatePrompt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..forward();

  late final CurvedAnimation _entrance =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _entrance.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _update() async {
    final uri = Uri.tryParse(widget.downloadUrl);
    widget.onDismiss();
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FadeTransition(
      opacity: _entrance,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ModalBarrier(
            color: Colors.black54,
            dismissible: true,
            onDismiss: widget.onDismiss,
            semanticsLabel:
                MaterialLocalizations.of(context).modalBarrierDismissLabel,
          ),
          ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(_entrance),
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              child: AlertDialog(
                title: const Text('Update available'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.latest == null
                          ? 'A newer version of Streamio is available.'
                          : 'Streamio ${widget.latest} is available.'),
                      if (widget.notes != null) ...[
                        const SizedBox(height: 12),
                        Text(widget.notes!, style: theme.textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: widget.onDismiss,
                    child: const Text('Later'),
                  ),
                  FilledButton(
                    // Autofocused for the TV build, where there is no pointer
                    // to aim at a button with.
                    autofocus: true,
                    onPressed: _update,
                    child: const Text('Update'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
