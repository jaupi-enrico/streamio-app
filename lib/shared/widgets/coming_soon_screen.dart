import 'package:flutter/material.dart';

/// Placeholder for screens not yet built in M1 (catalog, search, providers,
/// account, login/register) -- see plan milestones M2-M5.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const Center(child: Text('Coming soon')),
    );
  }
}
