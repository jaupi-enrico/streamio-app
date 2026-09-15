import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/auth_api.dart';
import '../../shared/tv.dart';
import '../../shared/widgets/async_states.dart';
import '../../state/api_providers.dart';
import '../../state/auth_providers.dart';
import 'auth_scaffold.dart';

/// Email/password sign-in plus the two OAuth providers the backend supports
/// (`auth/oauth.ts`: google, discord).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.redirectTo});

  /// Where to land after a successful sign-in — set by the router's auth
  /// guard so a deep link into /account survives the detour through here.
  final String? redirectTo;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
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

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref
          .read(authProvider.notifier)
          .login(_email.text.trim(), _password.text);
      if (mounted) _done();
    } catch (err) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = ErrorState.messageFor(err);
        });
      }
    }
  }

  /// Opens the provider's consent page in a browser tab and waits for the
  /// backend to bounce back to `streamio://auth?token=&refresh=`. The
  /// backend only redirects there for allowlisted targets — see
  /// `isAllowedRedirectUri` in `web/routes/auth.router.ts`.
  Future<void> _oauth(String provider) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final url = ref.read(authApiProvider).oauthUrl(provider);
      final result = await FlutterWebAuth2.authenticate(
        url: url,
        callbackUrlScheme: Uri.parse(AuthApi.oauthRedirectUri).scheme,
      );
      await ref.read(authProvider.notifier).completeOAuth(Uri.parse(result));
      if (mounted) _done();
    } on PlatformException catch (err) {
      // There is no browser on this device to open the consent page in — the
      // normal state of affairs on Android TV, and the reason this button used
      // to look simply dead. Hand over to the code-pairing flow rather than
      // reporting a failure the user can do nothing about.
      if (!mounted) return;
      setState(() => _busy = false);
      if (err.code == 'NO_BROWSER') {
        _goToDeviceLogin();
      } else {
        setState(() => _error = ErrorState.messageFor(err));
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

  void _goToDeviceLogin() {
    final redirect = widget.redirectTo;
    context.push(
      '/tv-login${redirect != null ? '?redirect=${Uri.encodeComponent(redirect)}' : ''}',
    );
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      showToast(context, 'Enter your email address first.', isError: true);
      return;
    }

    await runGuarded(
      context,
      () => ref.read(authApiProvider).requestPasswordReset(email),
      // The backend always answers 200 here to avoid leaking which addresses
      // exist, so the copy can't promise an email was actually sent.
      successMessage: 'If that address has an account, a reset link is on its way.',
    );
  }

  List<Widget> _tvSignInOptions(BuildContext context) {
    final theme = Theme.of(context);

    return [
      OutlinedButton.icon(
        onPressed: _busy ? null : _goToDeviceLogin,
        icon: const Icon(Icons.phone_iphone, size: 22),
        label: const Text('Sign in from your phone'),
        style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14)),
      ),
      const SizedBox(height: 8),
      Text(
        'Use Google, Discord or your password on a phone or computer, and '
        'approve a code shown here.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      // Nothing to go back to: the app is unusable until you sign in.
      showBack: false,
      title: 'Welcome back',
      subtitle: 'Sign in to sync your watchlist, history and watch parties.',
      error: _error,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.alternate_email),
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value == null || !value.contains('@')) ? 'Enter your email.' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              enabled: !_busy,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (value) =>
                  (value == null || value.isEmpty) ? 'Enter your password.' : null,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy ? null : _forgotPassword,
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: 4),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              child: _busy
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Sign in'),
            ),
            const SizedBox(height: 20),
            const _OrDivider(),
            const SizedBox(height: 20),
            // A television has no browser to open a consent page in, so the
            // OAuth buttons cannot work there at all — offering them would be
            // offering a button that throws. The pairing flow reaches the same
            // Google/Discord sign-in on a device that does have one.
            if (isTv(context))
              ..._tvSignInOptions(context)
            else ...[
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _oauth('google'),
                icon: const Icon(Icons.g_mobiledata, size: 28),
                label: const Text('Continue with Google'),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _oauth('discord'),
                icon: const Icon(Icons.chat_bubble_outline, size: 20),
                label: const Text('Continue with Discord'),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ],
            const SizedBox(height: 24),
            // Wrap, not Row: the prompt and the button together overflow a
            // narrow phone (and a large text scale) on one line.
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text("Don't have an account?"),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => context.push(
                          '/register${widget.redirectTo != null ? '?redirect=${Uri.encodeComponent(widget.redirectTo!)}' : ''}'),
                  child: const Text('Create one'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('or', style: TextStyle(color: Theme.of(context).hintColor)),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
