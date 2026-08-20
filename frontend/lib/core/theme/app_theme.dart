import 'package:flutter/material.dart';

/// Spacing scale. Nothing in the app uses a value outside this set —
/// arbitrary padding is what makes a UI feel accidental.
class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class AppRadius {
  static const control = 10.0;
  static const card = 14.0;
  static const pill = 999.0;
}

/// Application status colours live here, not scattered across screens,
/// so a status always looks the same wherever it appears.
class StatusColors {
  static const applied = Color(0xFF64748B);
  static const shortlisted = Color(0xFF15803D);
  static const onHold = Color(0xFFB45309);
  static const interview = Color(0xFF1D4ED8);
  static const selected = Color(0xFF0F766E);
  static const rejected = Color(0xFFB91C1C);

  static Color of(String status) => switch (status) {
    'shortlisted' => shortlisted,
    'on_hold' => onHold,
    'interview' => interview,
    'selected' => selected,
    'rejected' => rejected,
    _ => applied,
  };

  static String label(String status) => switch (status) {
    'shortlisted' => 'Shortlisted',
    'on_hold' => 'On hold',
    'interview' => 'Interview',
    'selected' => 'Selected',
    'rejected' => 'Rejected',
    _ => 'Applied',
  };
}

class ScoreColors {
  static const strong = Color(0xFF15803D);
  static const review = Color(0xFFB45309);
  static const low = Color(0xFFB91C1C);

  static Color of(int score) {
    if (score >= 80) return strong;
    if (score >= 50) return review;
    return low;
  }
}

class AppTheme {
  // Candidates and recruiters get visibly different palettes. One glance
  // should tell you which side of the product you are looking at.
  static const _candidateSeed = Color(0xFF0D9488); // teal
  static const _hrSeed = Color(0xFF1E3A5F); // deep navy
  static const _neutralSeed = Color(0xFF334155);

  static ThemeData candidate() => _build(_candidateSeed);
  static ThemeData hr() => _build(_hrSeed);
  static ThemeData neutral() => _build(_neutralSeed);

  static ThemeData _build(Color seed) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),

      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
          letterSpacing: -0.2,
        ),
      ),

      // Flat cards with a hairline border read as cleaner than drop shadows
      // and keep dense lists from looking noisy.
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.xl,
            vertical: Space.md + 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        labelStyle: const TextStyle(fontSize: 12.5),
        padding: const EdgeInsets.symmetric(horizontal: Space.sm),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: Space.xl,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),

      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),

      // Four sizes carry the whole app. More than that and hierarchy blurs.
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        bodyMedium: TextStyle(fontSize: 14, height: 1.5),
        bodySmall: TextStyle(fontSize: 12.5, height: 1.4),
        labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}
