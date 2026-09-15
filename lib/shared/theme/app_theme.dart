import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Dark streaming-app theme: Bebas Neue for display/headline text (poster
/// titles, hero headlines), DM Sans for body copy -- matches the original
/// web app's font pairing intent.
class AppTheme {
  AppTheme._();

  static const _background = Color(0xFF0B0E14);
  static const _surface = Color(0xFF161B26);
  static const _accent = Color(0xFFE8A33D);

  static ThemeData get dark {
    final base = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _background,
      colorScheme: const ColorScheme.dark(
        surface: _surface,
        primary: _accent,
        secondary: _accent,
      ),
      useMaterial3: true,
    );

    // Both families are bundled in `assets/google_fonts/` and `main()` disables
    // google_fonts' HTTP fetching, so this resolves from the app bundle and
    // never from fonts.gstatic.com. These two calls are what decide *which*
    // files have to be there: one per style of `base.textTheme`, at that
    // style's own weight (w400 and w500 for M3), rounded to the nearest weight
    // the family actually ships — which for single-weight Bebas Neue is always
    // Regular. Adding a family or a weight here means adding the file too; see
    // `test/fonts_test.dart`.
    final bodyFont = GoogleFonts.dmSansTextTheme(base.textTheme);
    final displayFont = GoogleFonts.bebasNeueTextTheme(base.textTheme);

    return base.copyWith(
      textTheme: bodyFont.copyWith(
        displayLarge: displayFont.displayLarge?.copyWith(letterSpacing: 1.2),
        displayMedium: displayFont.displayMedium?.copyWith(letterSpacing: 1.2),
        displaySmall: displayFont.displaySmall?.copyWith(letterSpacing: 1.2),
        headlineLarge: displayFont.headlineLarge?.copyWith(letterSpacing: 1.0),
        headlineMedium: displayFont.headlineMedium?.copyWith(letterSpacing: 1.0),
        headlineSmall: displayFont.headlineSmall?.copyWith(letterSpacing: 1.0),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _background,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: _surface,
      ),

      // ── Progress bars need a track that isn't the fill ───────
      //
      // M3 draws a linear indicator's track in `colorScheme.secondaryContainer`
      // and its fill in `primary` — and `ColorScheme.secondaryContainer` falls
      // back to `secondary` when it isn't given, which here is the same accent
      // as `primary`. Every bar in the app (badge progress, history and
      // continue-watching position, downloads) therefore rendered accent-on-
      // accent and read as 100% full whatever its value. The track is set
      // explicitly rather than by giving the scheme a `secondaryContainer`,
      // which would also repaint every selected chip. Only the linear track is
      // set: M3 leaves an *indeterminate* circular indicator trackless, and a
      // colour here would put a ring behind every loading spinner.
      progressIndicatorTheme: ProgressIndicatorThemeData(
        linearTrackColor: Colors.white.withValues(alpha: 0.18),
      ),

      // ── A seek bar needs a track you can see ─────────────────
      //
      // M3 draws a slider's inactive track in `surfaceContainerHighest`, whose
      // default here (`ColorScheme.dark` doesn't derive it from `surface`) is
      // a dark grey a shade off this theme's own surface. On the player's
      // black background it just about reads; on the cast panel's sheet —
      // which *is* that surface — the track past the thumb disappears, so the
      // bar looks like it stops where playback has got to and there is no way
      // to see, or aim at, the rest of the stream. Same shape of bug, and same
      // fix, as the progress-indicator track above.
      sliderTheme: SliderThemeData(
        inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
      ),

      // ── Focus, loudly ────────────────────────────────────────
      //
      // A D-pad user can only act on the widget that currently has focus, so
      // "where is focus?" has to be answerable at a glance from three metres
      // away. Material's defaults are tuned for a mouse hover on a phone in
      // your hand: an ~8% white overlay, which on this dark theme is close to
      // invisible on a television. Every ambient tap target below therefore
      // gets the accent colour behind it while focused.
      //
      // This is theme-wide rather than TV-only on purpose: it's the same fix
      // keyboard users on desktop want, and gating it on [isTv] would leave
      // the untestable path as the only one that matters.
      // ListTile, InkWell and friends read this one directly.
      focusColor: _accent.withValues(alpha: 0.32),
      chipTheme: ChipThemeData(
        selectedColor: _accent.withValues(alpha: 0.28),
      ),
      textButtonTheme: TextButtonThemeData(style: _focusableButtonStyle()),
      filledButtonTheme: FilledButtonThemeData(style: _focusableButtonStyle()),
      outlinedButtonTheme:
          OutlinedButtonThemeData(style: _focusableButtonStyle()),
      iconButtonTheme: IconButtonThemeData(style: _focusableButtonStyle()),
    );
  }

  /// Buttons don't read [ThemeData.focusColor] — they resolve their own
  /// `overlayColor` per [WidgetState] — so the focused state has to be
  /// restated for each button family.
  static ButtonStyle _focusableButtonStyle() => ButtonStyle(
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return _accent.withValues(alpha: 0.32);
          }
          if (states.contains(WidgetState.pressed)) {
            return _accent.withValues(alpha: 0.20);
          }
          return null;
        }),
      );
}
