// Design tokens: the raw numbers and colours the rest of the app is built
// from. Nothing outside this file hard-codes a spacing, a radius, a font size
// or a colour, so a change to the visual language is a change to one file and
// a review can see it.
//
// Sizes are logical pixels (dp). They are deliberately not scaled here — text
// scales through `MediaQuery.textScaler`, which Flutter applies at paint time,
// so a token multiplied by a scale factor would apply it twice.

import 'dart:ui' show Brightness, Color;

/// The spacing scale. Every gap and padding in the app is one of these.
///
/// Seven steps rather than a continuous range: a fixed set is what makes two
/// screens built months apart look like the same app.
abstract final class AppSpacing {
  /// 4 dp — between a glyph and the text it belongs to.
  static const double xs = 4;

  /// 8 dp — between tightly related controls.
  static const double sm = 8;

  /// 12 dp — inside a control, around its content.
  static const double md = 12;

  /// 16 dp — the default gap between elements.
  static const double lg = 16;

  /// 24 dp — screen edge padding, and between groups.
  static const double xl = 24;

  /// 32 dp — between sections.
  static const double xxl = 32;

  /// 48 dp — around a screen's single main action.
  static const double xxxl = 48;
}

/// Corner radii. Three values, one per shape role.
abstract final class AppRadii {
  /// Cards and surfaces.
  static const double card = 12;

  /// Buttons, including [AppTapTargets.primary]-sized ones.
  static const double button = 24;

  /// Fully rounded ends — chips and pills. Any value past half the shorter
  /// side gives the same shape, so this is a "round it fully" marker rather
  /// than a measurement.
  static const double pill = 999;
}

/// Minimum tap target sizes (PLAN.md §4.2).
///
/// These are floors, not fixed sizes: a control may be larger, never smaller.
/// `AppTheme` derives Material's button and icon minimums from them, so a
/// button below the floor is impossible rather than discouraged.
abstract final class AppTapTargets {
  /// 56 dp — the floor for every interactive control.
  static const double min = 56;

  /// 72 dp — a screen's primary actions, sized for a child's aim rather than
  /// an adult's.
  static const double primary = 72;
}

/// Border widths.
abstract final class AppBorders {
  /// 3 dp — thick enough to read as a state change on its own, which is what
  /// lets a selected control avoid signalling selection by colour.
  static const double selected = 3;

  /// 1 dp — an outline that says "this is a control" without competing with
  /// [selected] for attention.
  static const double hairline = 1;

  /// 2 dp — the line between two boxes of a Sudoku grid, against
  /// [hairline] between two cells of one box.
  ///
  /// Its own token rather than [selected] at the same value: this line is
  /// structure, not state, and a change to how selection is drawn must not
  /// silently redraw the grid.
  static const double gridBox = 2;
}

/// Icon sizes.
abstract final class AppIconSizes {
  /// 24 dp — Material's default, and what most icons use.
  static const double standard = 24;

  /// 32 dp — inside a control sized [AppTapTargets.primary], where a 24 dp
  /// glyph looks lost.
  static const double large = 32;
}

/// The type scale: four sizes, from four roles.
///
/// A child's app does not need eight. Every Material text slot maps onto one
/// of these in `AppTheme`, so no size exists that was not chosen here.
abstract final class AppTypeScale {
  /// 40 dp — a screen's own name, one per screen.
  static const double display = 40;

  /// 28 dp — section and card titles.
  static const double title = 28;

  /// 18 dp — body text and button labels. Larger than Material's 14 dp
  /// default: the reader is learning to read.
  static const double body = 18;

  /// 14 dp — captions and secondary labels. Never the only carrier of
  /// information a player needs.
  static const double caption = 14;

  /// Line height multiplier for [display] and [title].
  ///
  /// Tight, because headings are one or two words and the extra leading only
  /// pushes content off a phone screen at 200% text scale.
  static const double headingHeight = 1.15;

  /// Line height multiplier for [body] and [caption]. Loose enough that a
  /// wrapped sentence is easy to track back to the next line.
  static const double textHeight = 1.35;
}

/// A seed colour per surface role, for one brightness.
///
/// Roles rather than literal colours: `sudoku` is "the colour Sudoku is", so
/// the day and night values can differ as much as they need to without the
/// call site knowing which one it got.
///
/// Colour never carries state on its own anywhere in the app (PLAN.md §5's
/// accessibility rule and `AGENTS.md`): every role below is paired with an
/// icon, a label or a border wherever it is used, so a colourblind player and
/// a player on a washed-out screen in sunlight lose nothing.
final class AppPalette {
  const AppPalette({
    required this.brand,
    required this.sudoku,
    required this.arcade,
    required this.draw,
    required this.notice,
    required this.avatarSwatches,
  });

  /// App chrome, primary buttons, and the seed for the whole colour scheme.
  final Color brand;

  /// The Sudoku half of the home screen.
  final Color sudoku;

  /// The arcade third of the home screen.
  final Color arcade;

  /// The draw third of the home screen, from phase 8.
  final Color draw;

  /// Messages the player is told once and dismisses — the recovered-save
  /// banner in particular. Warm rather than red: nothing here is an error the
  /// child caused.
  final Color notice;

  /// One seed per avatar, assigned by position: the avatar at index `i` of the
  /// saved enum takes the swatch at index `i` (`avatars.dart` owns that
  /// mapping, and asserts the two lengths agree).
  ///
  /// Hues spaced around the wheel rather than chosen to look like the animal —
  /// the icons are not likenesses either (`avatars.dart`), and what a child
  /// needs is to tell their own profile from the one beside it at arm's length.
  /// The name and the glyph carry the same distinction for a player who cannot
  /// use the colour.
  final List<Color> avatarSwatches;

  /// Day palette. Mid-tone seeds, so Material's tonal derivation has room to
  /// go both lighter and darker.
  static const AppPalette day = AppPalette(
    brand: Color(0xFF3F6FD8),
    sudoku: Color(0xFF2E7D6B),
    arcade: Color(0xFF8E3FBF),
    draw: Color(0xFFC2410C),
    notice: Color(0xFFB4690E),
    avatarSwatches: <Color>[
      Color(0xFFD24B2E),
      Color(0xFFC98A12),
      Color(0xFF7A9E1F),
      Color(0xFF2E8B57),
      Color(0xFF1F9C9C),
      Color(0xFF3A66C4),
      Color(0xFF7A4FC0),
      Color(0xFFC0417F),
    ],
  );

  /// Night palette. Lifted and slightly desaturated: the same hues at day
  /// luminance vibrate against a dark surface and read as neon.
  static const AppPalette night = AppPalette(
    brand: Color(0xFF7FA0E8),
    sudoku: Color(0xFF67C0AC),
    arcade: Color(0xFFC08FE0),
    draw: Color(0xFFE8955F),
    notice: Color(0xFFE0A85C),
    avatarSwatches: <Color>[
      Color(0xFFE8907B),
      Color(0xFFE0BB63),
      Color(0xFFB7CE72),
      Color(0xFF74C79B),
      Color(0xFF6ED0D0),
      Color(0xFF8FA9E8),
      Color(0xFFB79BE4),
      Color(0xFFE08FB4),
    ],
  );

  /// The palette that goes with [brightness].
  ///
  /// A widget takes its palette from the theme it is being built in rather
  /// than from the stored setting, so a screen is correct under `system` too.
  static AppPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? night : day;
}
