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
    );
  }
}
