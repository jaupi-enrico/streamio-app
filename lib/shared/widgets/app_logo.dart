import 'package:flutter/material.dart';

/// The website's mark (`web/public/icons/site-icon.png`), reused in the app.
///
/// The source art is solid black on transparent, which would be invisible on
/// this app's dark theme — so it's recolored through a `srcIn` filter, which
/// keeps the alpha and repaints every opaque pixel. That works precisely
/// because the artwork is monochrome; it would flatten a multi-color logo.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 48, this.color});

  final double size;

  /// Defaults to the theme's accent, matching the STREAMIO wordmark.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icon/site-icon.png',
      width: size,
      height: size,
      color: color ?? Theme.of(context).colorScheme.primary,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.medium,
      // A missing asset shouldn't take a screen down with it.
      errorBuilder: (context, error, stack) => Icon(
        Icons.play_circle_outline,
        size: size,
        color: color ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

/// The mark and the wordmark stacked — the app's masthead, used on the setup
/// and auth screens.
class AppWordmark extends StatelessWidget {
  const AppWordmark({super.key, this.logoSize = 56, this.textStyle});

  final double logoSize;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(size: logoSize),
        const SizedBox(height: 10),
        Text(
          'STREAMIO',
          textAlign: TextAlign.center,
          style: textStyle ??
              theme.textTheme.headlineMedium?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 4,
              ),
        ),
      ],
    );
  }
}
