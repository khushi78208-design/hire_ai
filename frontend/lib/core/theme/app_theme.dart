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

/// The dark shell behind the drawer. Both roles share the layout; only the
/// tint separates them.
class Shell {
  static const hr = Color(0xFF1E1B4B); // indigo 950
  static const candidate = Color(0xFF134E4A); // teal 900

  static const onDark = Color(0xFFF5F5F7);
  static const onDarkMuted = Color(0xFF9CA3C7);

  static Color of(String? role) =>
      (role == 'hr' || role == 'admin') ? hr : candidate;
}

/// Application status colours live here, not scattered across screens,
/// so a status always looks the same wherever it appears.
class StatusColors {
  static const applied = Color(0xFF64748B);
  static const shortlisted = Color(0xFF059669);
  static const onHold = Color(0xFFD97706);
  static const interview = Color(0xFF4F46E5);
  static const selected = Color(0xFF0D9488);
  static const rejected = Color(0xFFDC2626);

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
  static const strong = Color(0xFF059669);
  static const review = Color(0xFFD97706);
  static const low = Color(0xFFDC2626);

  static Color of(int score) {
    if (score >= 80) return strong;
    if (score >= 50) return review;
    return low;
  }
}

class AppTheme {
  static const _hrSeed = Color(0xFF4F46E5); // indigo 600
  static const _candidateSeed = Color(0xFF0D9488); // teal 600
  static const _neutralSeed = Color(0xFF52525B);

  // Pure white makes cards disappear. A hair of warmth lets them sit on
  // the page instead of merging into it.
  static const _canvas = Color(0xFFFAFAFA);

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
      scaffoldBackgroundColor: _canvas,

      appBarTheme: AppBarTheme(
        backgroundColor: _canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
          letterSpacing: -0.3,
        ),
      ),

      // Flat cards with a hairline border read as cleaner than drop shadows
      // and keep dense lists from looking noisy.
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md + 2,
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
            vertical: Space.md + 4,
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        labelStyle: const TextStyle(fontSize: 12.5),
        padding: const EdgeInsets.symmetric(horizontal: Space.sm),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),

      // The drawer is the one dark surface in the app — it anchors the
      // layout and makes the role obvious at a glance.
      drawerTheme: const DrawerThemeData(
        backgroundColor: Shell.hr,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        width: 280,
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),

      // Four sizes carry the whole app. More than that and hierarchy blurs.
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        titleSmall: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
        bodyMedium: TextStyle(fontSize: 14, height: 1.5),
        bodySmall: TextStyle(fontSize: 12.5, height: 1.4),
        labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}
