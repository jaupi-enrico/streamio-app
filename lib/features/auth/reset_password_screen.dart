import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/async_states.dart';
import '../../state/api_providers.dart';
import 'auth_scaffold.dart';

/// Two modes, like `reset-password.html`: with a token from the emailed link,
/// it sets a new password; without one, it asks for the address to send the
/// link to.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.token});

  final String? token;

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _busy = false;
  bool _done = false;
  String? _error;

  bool get _hasToken => widget.token != null && widget.token!.isNotEmpty;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final api = ref.read(authApiProvider);
      if (_hasToken) {
        await api.confirmPasswordReset(widget.token!, _password.text);
      } else {
        await api.requestPasswordReset(_email.text.trim());
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _done = true;
        });
      }
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
    if (_done) {
      return AuthScaffold(
        title: _hasToken ? 'Password updated' : 'Check your email',
        subtitle: _hasToken
            ? 'You can sign in with your new password now.'
            : 'If that address has an account, a reset link is on its way.',
        child: FilledButton(
          onPressed: () => context.go('/login'),
          style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16)),
          child: const Text('Back to sign in'),
        ),
      );
    }

    return AuthScaffold(
      title: _hasToken ? 'Choose a new password' : 'Reset your password',
      subtitle: _hasToken
          ? null
          : 'We\'ll email you a link to set a new password.',
      error: _error,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_hasToken)
              TextFormField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.alternate_email),
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value == null || !value.contains('@'))
                    ? 'Enter your email.'
                    : null,
              )
            else ...[
              TextFormField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New password',
                  helperText: 'At least 8 characters.',
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.length < 8)
                    ? 'Use at least 8 characters.'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirm,
                enabled: !_busy,
                obscureText: true,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value != _password.text ? 'The passwords don\'t match.' : null,
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              child: _busy
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_hasToken ? 'Set new password' : 'Send reset link'),
            ),
          ],
        ),
      ),
    );
  }
}
