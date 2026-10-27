
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette: banknote green on cool paper, with the amber of a notification dot.
class Palette {
  static const green = Color(0xFF0F5A3E);
  static const mint = Color(0xFFDDEFE4);
  static const paper = Color(0xFFF6F8F6);
  static const ink = Color(0xFF14231C);
  static const amber = Color(0xFFF2A81D);
  static const credit = Color(0xFF1E8F55);
  static const line = Color(0xFFDCE4DE);

  static const darkBg = Color(0xFF0E1612);
  static const darkSurface = Color(0xFF16211B);
  static const darkGreen = Color(0xFF6FD3A0);
  static const darkInk = Color(0xFFE6EFE9);
  static const darkLine = Color(0xFF2A3A31);
}

/// Display face for headlines and big numbers.
TextStyle display(TextStyle? base) {
  return GoogleFonts.getFont(
    'Bricolage Grotesque',
    textStyle: base,
  );
}

ThemeData buildTheme(Brightness b) {
  final bool dark = b == Brightness.dark;

  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: Palette.green,
    brightness: b,
  ).copyWith(
    primary: dark ? Palette.darkGreen : Palette.green,
    onPrimary: dark ? Palette.darkBg : Colors.white,
    primaryContainer:
        dark ? const Color(0xFF1C3328) : Palette.mint,
    onPrimaryContainer: dark ? Palette.darkInk : Palette.green,
    tertiary: Palette.amber,
    surface: dark ? Palette.darkBg : Palette.paper,
    onSurface: dark ? Palette.darkInk : Palette.ink,
    surfaceContainerLowest:
        dark ? Palette.darkSurface : Colors.white,
    surfaceContainerLow:
        dark ? Palette.darkSurface : Colors.white,
    surfaceContainer: dark
        ? const Color(0xFF1A2620)
        : const Color(0xFFEEF2EF),
    surfaceContainerHigh: dark
        ? const Color(0xFF1F2C25)
        : const Color(0xFFE8EDE9),
    outlineVariant: dark ? Palette.darkLine : Palette.line,
  );

  // Start with Flutter's own TextTheme.
  final TextTheme baseText = ThemeData(
    brightness: b,
  ).textTheme;

  // Apply Figtree without using GoogleFonts.figtreeTextTheme().
  final TextTheme text = baseText.apply(
    fontFamily: GoogleFonts.figtree().fontFamily,
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );

  // Style the main display headings.
  final TextTheme styledText = text.copyWith(
    headlineMedium: GoogleFonts.getFont(
      'Bricolage Grotesque',
      textStyle: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.1,
      ),
    ),
    headlineSmall: GoogleFonts.getFont(
      'Bricolage Grotesque',
      textStyle: text.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.15,
      ),
    ),
    titleLarge: GoogleFonts.getFont(
      'Bricolage Grotesque',
      textStyle: text.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: styledText,

    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.getFont(
        'Bricolage Grotesque',
        textStyle: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
    ),

    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: scheme.outlineVariant,
        ),
      ),
    ),

    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      side: BorderSide(
        color: scheme.outlineVariant,
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      indicatorColor: scheme.primaryContainer,
      surfaceTintColor: Colors.transparent,
    ),

    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
    ),

    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      space: 1,
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
  );
}
