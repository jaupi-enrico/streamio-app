import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/server_config.dart';
import '../../shared/widgets/app_logo.dart';
import '../../shared/widgets/async_states.dart';
import '../../state/server_config_provider.dart';

/// First-run screen: where is the server?
///
/// There is no baked-in backend origin — a Streamio install is self-hosted
/// and normally reached through a DDNS name or the `redirect/` Cloudflare
/// Tunnel, either of which can change. Nothing else in the app can make a
/// request until this is answered, so the router sends every route here
/// while it's unset.
///
/// Reachable later from Account → Server, which is why it takes an
/// [isInitialSetup] flag: on a later visit it gets a back button and keeps
/// the current value in the field.
class ServerSetupScreen extends ConsumerStatefulWidget {
  const ServerSetupScreen({super.key, this.isInitialSetup = true});

  final bool isInitialSetup;

  @override
  ConsumerState<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends ConsumerState<ServerSetupScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  bool _checking = false;
  String? _error;
  String? _warning;
  List<String> _recent = const [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final recent = await ServerConfig.recent();
    final current = ref.read(currentServerUrlProvider);
    if (!mounted) return;
    setState(() {
      _recent = recent.where((url) => url != current).toList();
      if (_controller.text.isEmpty) {
        _controller.text = current ?? (recent.isNotEmpty ? recent.first : '');
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _connect({String? url}) async {
    final normalized = ServerConfig.normalize(url ?? _controller.text);
    if (normalized == null) {
      setState(() {
        _error = 'That doesn\'t look like a web address.';
        _warning = null;
      });
      return;
    }

    setState(() {
      _checking = true;
      _error = null;
      _warning = null;
    });

    final probe = await probeServerCandidates(normalized);
    if (!mounted) return;

    switch (probe.result) {
      case ServerProbeResult.ok:
        // Not necessarily what was typed: a pasted page URL gets trimmed back
        // to the base that actually answered.
        final resolved = probe.resolvedBase ?? normalized;
        await ref.read(serverBaseUrlProvider.notifier).set(resolved);
        if (!mounted) return;
        if (resolved != normalized) {
          _controller.text = resolved;
          showToast(context, 'Connected to $resolved');
        }
        // The router's redirect takes over from here on the initial setup;
        // a later visit just pops back to where it came from.
        if (widget.isInitialSetup) {
          context.go('/');
        } else if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }

      case ServerProbeResult.reachableNotReady:
        setState(() {
          _checking = false;
          _warning = probe.detail;
        });

      case ServerProbeResult.unreachable:
        setState(() {
          _checking = false;
          _error = probe.detail ?? 'Could not reach the server.';
        });
    }
  }

  /// Saves without a successful probe. The tunnel can take a minute to come
  /// up, and refusing to save an address that's merely not-ready-yet would
  /// leave the user stuck on this screen with nothing to do but retry.
  Future<void> _saveAnyway() async {
    final normalized = ServerConfig.normalize(_controller.text);
    if (normalized == null) return;
    await ref.read(serverBaseUrlProvider.notifier).set(normalized);
    if (!mounted) return;
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: widget.isInitialSetup
          ? null
          : AppBar(title: const Text('Server'), leading: const BackButton()),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.isInitialSetup) ...[
                    AppWordmark(
                      logoSize: 64,
                      textStyle: theme.textTheme.displaySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Point the app at your server to get started.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.hintColor),
                    ),
                    const SizedBox(height: 32),
                  ],
                  TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: widget.isInitialSetup,
                    enabled: !_checking,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    textInputAction: TextInputAction.go,
                    inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                    onSubmitted: (_) => _connect(),
                    decoration: InputDecoration(
                      labelText: 'Server address',
                      hintText: 'streamio.example.ddns.net',
                      prefixIcon: const Icon(Icons.dns_outlined),
                      border: const OutlineInputBorder(),
                      errorText: _error,
                      helperText: 'https:// is assumed if you leave the scheme out.',
                      helperMaxLines: 2,
                    ),
                  ),
                  if (_warning != null) ...[
                    const SizedBox(height: 12),
                    _NoticeBox(
                      icon: Icons.hourglass_bottom,
                      message: _warning!,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _checking ? null : () => _connect(),
                    icon: _checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link),
                    label: Text(_checking ? 'Checking…' : 'Connect'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  if (_warning != null) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _checking ? null : _saveAnyway,
                      child: const Text('Use this address anyway'),
                    ),
                  ],
                  if (_recent.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Text('Recently used',
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: theme.hintColor)),
                    const SizedBox(height: 4),
                    for (final url in _recent)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.history, size: 20),
                        title: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: _checking
                            ? null
                            : () {
                                _controller.text = url;
                                _connect(url: url);
                              },
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeBox extends StatelessWidget {
  const _NoticeBox({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
