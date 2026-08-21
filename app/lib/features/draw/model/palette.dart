// The eighteen colours and four pencil sizes a child chooses from — the
// concrete meaning behind [Stroke.colorIndex] and [Stroke.sizeIndex]
// (`stroke.dart`), and what [DrawingPainter]'s `colorOf`/`widthOf` callbacks
// resolve through (`drawing_painter.dart`).
//
// Colour cannot be designed out of a paint box — the swatches *are* the
// content (`PLAN-phase-8.md` §1) — so every swatch carries a spoken name
// here, and the tool row (`tool_row.dart`) signals which one is chosen with a
// border and a size change rather than with colour alone.

import 'package:flutter/painting.dart' show Color;

/// The eighteen colours a child can draw with, and what each is called:
/// twelve paint-box colours, then six skin tones.
///
/// [colors] and [names] are positional against each other and against
/// [Stroke.colorIndex] — index 3 is [Color]s[3], named `names[3]`, for the
/// life of every drawing that has ever used it. Reordering or removing an
/// entry here changes what an old drawing looks like when it is reopened
/// (`stroke.dart`'s note on why `colorIndex` is an index rather than a
/// stored value); adding one at the end is safe, which is why the skin
/// tones are appended rather than sorted in among the colours they sit
/// between on a colour wheel.
abstract final class DrawPalette {
  static const List<Color> colors = <Color>[
    Color(0xFFE53935), // Red
    Color(0xFFFB8C00), // Orange
    Color(0xFFFDD835), // Yellow
    Color(0xFF43A047), // Green
    Color(0xFF00897B), // Teal
    Color(0xFF039BE5), // Sky
    Color(0xFF3949AB), // Blue
    Color(0xFF8E24AA), // Purple
    Color(0xFFD81B60), // Pink
    Color(0xFF6D4C41), // Brown
    Color(0xFF000000), // Black
    Color(0xFFFFFFFF), // White
    // Skin tones: a light-to-deep ramp, drawing a person being the thing a
    // child asks a paint box for that twelve rainbow colours cannot answer.
    // Six rather than five or eight because the rail is six swatches wide
    // (`tool_row.dart`), so the tones land there as a row of their own.
    Color(0xFFFFDBAC), // Lightest skin
    Color(0xFFF1C27D), // Light skin
    Color(0xFFE0AC69), // Medium skin
    Color(0xFFC68642), // Medium deep skin
    Color(0xFF8D5524), // Deep skin
    Color(0xFF4A2C1A), // Deepest skin
  ];

  static const List<String> names = <String>[
    'Red',
    'Orange',
    'Yellow',
    'Green',
    'Teal',
    'Sky',
    'Blue',
    'Purple',
    'Pink',
    'Brown',
    'Black',
    'White',
    // Every skin tone says "skin": the ramp reads as one set on the row, and
    // a name spoken on its own ('Medium deep') would not say what it is.
    'Lightest skin',
    'Light skin',
    'Medium skin',
    'Medium deep skin',
    'Deep skin',
    'Deepest skin',
  ];

  /// The paint colour for [Stroke.colorIndex] `index`. Never called for an
  /// eraser stroke ([Stroke.isEraser]).
  static Color colorAt(int index) => colors[index];

  /// The spoken name for `index`, for the swatch's own [Semantics] label and
  /// for anywhere else a colour needs to be said rather than shown.
  static String nameAt(int index) => names[index];
}

/// The four pencil sizes a child can draw with.
abstract final class DrawPencils {
  /// Stroke widths, in sheet units — what [DrawingPainter.widthOf] resolves
  /// [Stroke.sizeIndex] through, on the same 1600 x 1200 sheet every stroke's
  /// points are in (`stroke.dart`'s `sheetWidth`/`sheetHeight`).
  static const List<double> widths = <double>[8, 18, 32, 52];

  /// The dot diameter each size draws itself as in the tool row, in logical
  /// pixels.
  ///
  /// Deliberately not [widths]: a sheet-unit width means nothing on a control
  /// that never touches the sheet's coordinate space, and the two scale
  /// differently as a screen's size changes — `draw_sheet_screen.dart`'s
  /// `_fitToSheet` shrinks a sheet unit to a fraction of a logical pixel on a
  /// phone, which would draw the tool row's own dots as slivers. Chosen
  /// instead to read as four visibly different sizes inside one
  /// `AppTapTargets.min` (56 dp) button.
  static const List<double> previewDiameters = <double>[10, 18, 26, 34];

  static const List<String> names = <String>[
    'Thin',
    'Medium',
    'Thick',
    'Extra thick',
  ];

  /// The stroke width, in sheet units, for [Stroke.sizeIndex] `index`.
  static double widthAt(int index) => widths[index];

  /// The spoken name for `index`.
  static String nameAt(int index) => names[index];
}
