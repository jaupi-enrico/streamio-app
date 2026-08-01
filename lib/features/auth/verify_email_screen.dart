import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/async_states.dart';
import '../../state/api_providers.dart';
import '../../state/auth_providers.dart';
import 'auth_scaffold.dart';

/// Landing screen for the link in the verification email
/// (`streamio://auth/verify-email?token=…` or the web `/verify-email?token=`),
/// equivalent to `public/verify-email.html`: POST the token, show the result.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, this.token});

  final String? token;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _verify();
  }

  Future<void> _verify() async {
    final token = widget.token;
    if (token == null || token.isEmpty) {
      setState(() {
        _busy = false;
        _error = 'This link is missing its verification token.';
      });
      return;
    }

    try {
      await ref.read(authApiProvider).verifyEmail(token);
      // The signed-in user's `email_verified` flag just changed server-side.
      await ref.read(authProvider.notifier).refresh();
      if (mounted) setState(() => _busy = false);
    } catch (err) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = ErrorState.messageFor(err);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const AuthScaffold(
        title: 'Verifying your email',
        showBack: false,
        child: Center(child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(),
        )),
      );
    }

    return AuthScaffold(
      title: _error == null ? 'Email verified' : 'Verification failed',
      subtitle: _error ?? 'Thanks — your address is confirmed.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: () => context.go('/'),
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: const Text('Continue'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() {
                  _busy = true;
                  _error = null;
                });
                _verify();
              },
              child: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}
