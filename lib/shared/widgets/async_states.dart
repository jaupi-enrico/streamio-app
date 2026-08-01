import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../user_facing_error.dart';

/// The three states every data-backed screen shows, in one place so loading
/// spinners, empty copy and retry buttons don't drift between screens.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.error,
    this.onRetry,
    this.scrollable = true,
  });

  final Object error;
  final VoidCallback? onRetry;

  /// Wraps in a scroll view so it can be the body of a RefreshIndicator
  /// (pull-to-refresh needs something scrollable even when it's an error).
  final bool scrollable;

  /// The server's own message when it sent one; a short generic line when it
  /// was a transport failure.
  static String messageFor(Object error) {
    if (error is SessionExpiredException) return 'Please sign in again.';
    if (error is UserFacingError) return error.message;
    if (error is StateError) return error.message;
    return 'Something went wrong.';
  }

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 40, color: Theme.of(context).hintColor),
            const SizedBox(height: 12),
            Text(messageFor(error), textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );

    if (!scrollable) return content;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: content,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    this.scrollable = true,
  });

  final String message;
  final IconData icon;
  final Widget? action;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Theme.of(context).hintColor),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );

    if (!scrollable) return content;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: content,
        ),
      ),
    );
  }
}

class LoadingState extends StatelessWidget {
  const LoadingState({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

/// The web frontend's `toast()`, as a SnackBar.
void showToast(BuildContext context, String message, {bool isError = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        duration: const Duration(seconds: 3),
      ),
    );
}

/// Runs [action], surfacing failures as a toast instead of an unhandled
/// exception. Returns true when it completed.
Future<bool> runGuarded(
  BuildContext context,
  Future<void> Function() action, {
  String? successMessage,
}) async {
  try {
    await action();
    if (context.mounted && successMessage != null) {
      showToast(context, successMessage);
    }
    return true;
  } catch (err) {
    if (context.mounted) {
      showToast(context, ErrorState.messageFor(err), isError: true);
    }
    return false;
  }
}
