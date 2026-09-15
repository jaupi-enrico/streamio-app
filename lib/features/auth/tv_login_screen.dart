import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api/auth_api.dart';
import '../../shared/widgets/async_states.dart';
import '../../state/api_providers.dart';
import '../../state/auth_providers.dart';
import 'auth_scaffold.dart';

/// Sign-in for a device that cannot open a browser.
///
/// An Android TV generally ships with no browser and nothing registered for
/// `https` ACTION_VIEW, so the OAuth path on the login screen has nothing to
/// launch — it throws before the consent page is ever reached, which is what
/// made "Continue with Google" look like a dead button. This screen is the
/// standard answer, and the one the same hardware already uses for YouTube and
/// Netflix: show a short code, let the user approve it from a device that
/// *does* have a browser (where Google sign-in works normally), and poll.
///
/// The backend half is `POST /api/auth/device/*` and the `/tv` page in
/// `../web`; `../web/auth/deviceLogin.ts` explains the two-code split.
class TvLoginScreen extends ConsumerStatefulWidget {
  const TvLoginScreen({super.key, this.redirectTo});

  final String? redirectTo;

  @override
  ConsumerState<TvLoginScreen> createState() => _TvLoginScreenState();
}

class _TvLoginScreenState extends ConsumerState<TvLoginScreen> {
  DeviceLoginSession? _session;
  Timer? _poll;
  String? _error;
  bool _expired = false;
  bool _starting = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _done() {
    final target = widget.redirectTo;
    if (target != null && target.isNotEmpty) {
      context.go(target);
    } else {
      context.go('/');
    }
  }

  Future<void> _start() async {
    _poll?.cancel();
    setState(() {
      _starting = true;
      _expired = false;
      _error = null;
      _session = null;
    });

    try {
      final session = await ref
          .read(authApiProvider)
          .startDeviceLogin(label: 'Streamio on this TV');
      if (!mounted) return;

      setState(() {
        _session = session;
        _starting = false;
      });

      _poll = Timer.periodic(session.interval, (_) => _tick());
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = ErrorState.messageFor(err);
      });
    }
  }

  /// One poll. A transport failure is deliberately swallowed: the code is good
  /// for ten minutes and the phone half is happening on someone else's
  /// network, so a single failed request says nothing worth tearing the screen
  /// down over — the next tick tries again.
  Future<void> _tick() async {
    final session = _session;
    if (session == null) return;

    DeviceLoginStatus status;
    try {
      status = await ref.read(authApiProvider).pollDeviceLogin(session);
    } catch (_) {
      return;
    }
    if (!mounted) return;

    switch (status) {
      case DeviceLoginStatus.pending:
        return;

      case DeviceLoginStatus.expired:
        _poll?.cancel();
        setState(() => _expired = true);

      case DeviceLoginStatus.approved:
        _poll?.cancel();
        try {
          await ref.read(authProvider.notifier).completeDeviceLogin();
          if (mounted) _done();
        } catch (err) {
          if (mounted) setState(() => _error = ErrorState.messageFor(err));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Sign in from your phone',
      subtitle:
          'This TV has no browser, so finish signing in — with Google, Discord '
          'or your password — on a device that does.',
      error: _error,
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_starting) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: LoadingState(),
      );
    }

    final session = _session;
    if (session == null || _expired) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_expired)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'That code expired before it was approved.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          FilledButton(
            autofocus: true,
            onPressed: _start,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: const Text('Get a new code'),
          ),
          const SizedBox(height: 12),
          _backButton(),
        ],
      );
    }

    return _CodePanel(
      session: session,
      onStartOver: _start,
      back: _backButton(),
    );
  }

  Widget _backButton() => TextButton(
        onPressed: () => context.canPop() ? context.pop() : context.go('/login'),
        child: const Text('Back to sign in'),
      );
}

class _CodePanel extends StatelessWidget {
  const _CodePanel({
    required this.session,
    required this.onStartOver,
    required this.back,
  });

  final DeviceLoginSession session;
  final VoidCallback onStartOver;
  final Widget back;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Step(
          number: '1',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('On your phone, go to', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              SelectableText(
                _displayUri(session.verificationUri),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _Step(
          number: '2',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Enter this code', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              // Read from across a room: as large as the layout allows, wide
              // letter spacing, and the dash kept so the two halves group.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  session.userCode,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 6,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // The QR is the shortcut, not the instructions: a TV with no browser is
        // often also a TV whose remote makes typing a URL miserable, but a
        // phone camera cannot be relied on either — so both paths are shown.
        Center(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: QrImageView(
              data: session.verificationUriComplete,
              version: QrVersions.auto,
              size: 168,
              backgroundColor: Colors.white,
              padding: EdgeInsets.zero,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'or scan this with your phone camera',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: theme.hintColor),
            ),
            const SizedBox(width: 10),
            Text('Waiting for you to approve…',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor)),
          ],
        ),
        const SizedBox(height: 16),
        // Focusable so a remote has somewhere to land — a screen with nothing
        // focused eats the first D-pad press.
        TextButton(autofocus: true, onPressed: onStartOver, child: const Text('Get a new code')),
        back,
      ],
    );
  }

  /// The scheme is noise on a screen someone is copying by hand.
  static String _displayUri(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null || !parsed.hasAuthority) return uri;
    return '${parsed.host}${parsed.hasPort ? ':${parsed.port}' : ''}${parsed.path}';
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.child});

  final String number;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary.withValues(alpha: 0.18),
          ),
          child: Text(number,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.primary)),
        ),
        const SizedBox(width: 12),
        Expanded(child: child),
      ],
    );
  }
}
