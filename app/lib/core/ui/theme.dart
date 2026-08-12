// Day and night themes, built entirely from `tokens.dart`.
//
// The point of building the theme rather than styling each widget is that the
// rules that matter — the 56 dp tap-target floor above all — hold for a widget
// nobody reviewed. A plain `ElevatedButton` dropped into a screen in phase 4
// is already large enough, because the theme said so.

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Builders for the app's two themes.
abstract final class AppTheme {
  /// The day theme.
  static ThemeData day() => _build(Brightness.light, AppPalette.day);

  /// The night theme.
  static ThemeData night() => _build(Brightness.dark, AppPalette.night);

  /// A colour scheme built around one palette role, for a control that is
  /// meant to read as that role — the two home cards, so far.
  ///
  /// Derived rather than applied directly so that the foreground colour comes
  /// out of the same tonal palette as the background: a role colour dropped
  /// onto a button as-is keeps the theme's `onPrimary`, which is contrast the
  /// role never agreed to.
  ///
  /// Memoised because `fromSeed` builds a full tonal palette. The cache is
  /// bounded by the number of roles times the two brightnesses, both of which
  /// are compile-time constants.
  static ColorScheme roleScheme(Color role, Brightness brightness) =>
      _roleSchemes.putIfAbsent((
        role,
        brightness,
      ), () => ColorScheme.fromSeed(seedColor: role, brightness: brightness));

  static final Map<(Color, Brightness), ColorScheme> _roleSchemes =
      <(Color, Brightness), ColorScheme>{};

  static ThemeData _build(Brightness brightness, AppPalette palette) {
    final colors = ColorScheme.fromSeed(
      seedColor: palette.brand,
      brightness: brightness,
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.button),
    );
    // A floor, not a size: `minimumSize` leaves a button free to grow when its
    // label wraps at a large text scale, which a fixed size would not.
    const minimumTap = Size(AppTapTargets.min, AppTapTargets.min);
    const buttonPadding = EdgeInsets.symmetric(
      horizontal: AppSpacing.xl,
      vertical: AppSpacing.md,
    );

    final buttonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll<Size>(minimumTap),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(buttonPadding),
      shape: WidgetStatePropertyAll<OutlinedBorder>(buttonShape),
    );

    return ThemeData(
      colorScheme: colors,
      useMaterial3: true,
      textTheme: _textTheme(),

      // Standard density on every platform, not `adaptivePlatformDensity`.
      // Adaptive density subtracts up to 8 dp from a control's minimum on
      // desktop, which would quietly turn the 56 dp floor into 48 dp on three
      // of the six targets. The floor is a product constraint (PLAN.md §4.2),
      // not a platform convention.
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,

      elevatedButtonTheme: ElevatedButtonThemeData(style: buttonStyle),
      filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle),
      textButtonTheme: TextButtonThemeData(style: buttonStyle),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll<Size>(minimumTap),
          shape: const WidgetStatePropertyAll<OutlinedBorder>(CircleBorder()),
        ),
      ),

      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        margin: const EdgeInsets.all(AppSpacing.sm),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
      ),
    );
  }

  /// Every Material text slot mapped onto one of the four sizes in
  /// [AppTypeScale].
  ///
  /// Colour and font family are left unset on purpose: `ThemeData` merges this
  /// over the brightness-appropriate typography, so text still takes its
  /// colour from the colour scheme.
  static TextTheme _textTheme() {
    const display = TextStyle(
      fontSize: AppTypeScale.display,
      height: AppTypeScale.headingHeight,
      fontWeight: FontWeight.w700,
    );
    const title = TextStyle(
      fontSize: AppTypeScale.title,
      height: AppTypeScale.headingHeight,
      fontWeight: FontWeight.w600,
    );
    const body = TextStyle(
      fontSize: AppTypeScale.body,
      height: AppTypeScale.textHeight,
    );
    const caption = TextStyle(
      fontSize: AppTypeScale.caption,
      height: AppTypeScale.textHeight,
    );
    // Button and tab labels: body-sized, but weighted so a label reads as
    // something to press rather than something to read.
    const label = TextStyle(
      fontSize: AppTypeScale.body,
      height: AppTypeScale.textHeight,
      fontWeight: FontWeight.w600,
    );

    return const TextTheme(
      displayLarge: display,
      displayMedium: display,
      displaySmall: display,
      headlineLarge: title,
      headlineMedium: title,
      headlineSmall: title,
      titleLarge: title,
      titleMedium: body,
      titleSmall: body,
      bodyLarge: body,
      bodyMedium: body,
      bodySmall: caption,
      labelLarge: label,
      labelMedium: caption,
      labelSmall: caption,
    );
  }
}
