import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/async_states.dart';
import '../../../state/api_providers.dart';
import '../../../state/auth_providers.dart';
import '../../../state/server_config_provider.dart';

/// Display name / avatar, sign-out, and account deletion.
class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({super.key});

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> {
  final _displayName = TextEditingController();
  final _avatarUrl = TextEditingController();
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _displayName.dispose();
    _avatarUrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await runGuarded(
      context,
      () => ref.read(accountApiProvider).updateProfile(
            displayName: _displayName.text.trim(),
            avatarUrl: _avatarUrl.text.trim(),
          ),
      successMessage: 'Profile saved',
    );
    if (ok) await ref.read(authProvider.notifier).refresh();
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _signOut() async {
    await ref.read(authProvider.notifier).logout();
    if (mounted) context.go('/');
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'Your watchlist, favorites, ratings, history and social connections '
          'are deleted from this server. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await runGuarded(
      context,
      () => ref.read(accountApiProvider).deleteAccount(),
      successMessage: 'Account deleted',
    );
    if (ok) {
      await ref.read(authProvider.notifier).logout();
      if (mounted) context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final serverUrl = ref.watch(currentServerUrlProvider);

    // Seed the fields once from the loaded user, then leave them to the user.
    if (!_initialized && user != null) {
      _displayName.text = user.displayName ?? '';
      _avatarUrl.text = user.avatarUrl ?? '';
      _initialized = true;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _displayName,
          decoration: const InputDecoration(
            labelText: 'Display name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _avatarUrl,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Avatar URL',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save profile'),
        ),
        const Divider(height: 40),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.dns_outlined),
          title: const Text('Server'),
          subtitle: Text(serverUrl ?? 'Not configured'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/server'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: _signOut,
        ),
        const Divider(height: 40),
        Text('Danger zone',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _deleteAccount,
          icon: const Icon(Icons.delete_forever_outlined),
          label: const Text('Delete account'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}
