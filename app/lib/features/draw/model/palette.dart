// The colours and four pencil sizes a child chooses from — the concrete
// meaning behind [Stroke.colorIndex] and [Stroke.sizeIndex] (`stroke.dart`),
// and what [DrawingPainter]'s `colorOf`/`widthOf` callbacks resolve through
// (`drawing_painter.dart`).
//
// Colour cannot be designed out of a paint box — the swatches *are* the
// content (`PLAN-phase-8.md` §1) — so every swatch carries a spoken name
// here, and the picker signals which one is chosen with a border and a size
// change rather than with colour alone.

import 'package:flutter/painting.dart' show Color, HSLColor;

/// Every colour a stroke can have been saved with, and what each is called:
/// the eighteen the first release shipped, then a generated 16 x 16 grid.
///
/// [colors] and [names] are positional against each other and against
/// [Stroke.colorIndex] — index 3 is [Color]s[3], named `names[3]`, for the
/// life of every drawing that has ever used it. Reordering or removing an
/// entry here changes what an old drawing looks like when it is reopened
/// (`stroke.dart`'s note on why `colorIndex` is an index rather than a
/// stored value); adding one at the end is safe, which is why the grid is
/// appended rather than merged with the colours it replaces.
///
/// Three ranges, in index order:
///
/// * 0-11, the twelve paint-box colours, and 12-17, six skin tones. Fixed
///   forever, and always renderable.
/// * [gridStart] onward, [gridRows] x [gridColumns] colours: column 0 is a
///   grey ramp, columns 1-15 are fifteen hues, and each row is one lightness
///   from pale tint (row 0) to deep shade (the last row). Laid out row by row,
///   so [gridIndex] is the only arithmetic a caller needs.
///
/// What the picker *offers* is narrower than what exists: [pickerIndices].
/// The paint-box colours 0-11 stay renderable but are no longer offered, since
/// the grid holds a near-equivalent of each; the skin tones stay offered
/// because drawing a person is what a child needs them for and a hue grid at
/// any lightness cannot produce them.
abstract final class DrawPalette {
  /// The index of grid cell (0, 0) — the first index after the skin tones.
  static const int gridStart = 18;

  static const int gridColumns = 16;
  static const int gridRows = 16;

  /// How many colours the grid holds.
  static const int gridSize = gridColumns * gridRows;

  /// The first skin-tone index; the skin tones run up to [gridStart].
  static const int _skinStart = 12;

  /// The grid row whose lightness is exactly 0.5, where every hue is at its
  /// purest — the row a "just red" lives in.
  static const int _pureRow = 8;

  /// The index a new drawing starts with: the grid's pure red, the colour a
  /// child reaches for first, and the one the paint box always opened on.
  static const int defaultIndex = gridStart + _pureRow * gridColumns + 1;

  // The twelve paint-box colours and six skin tones the first release
  // shipped. Private: callers read the combined [colors], and an index into
  // this list is not an index into that one only by luck of both starting at
  // zero.
  static const List<Color> _legacyColors = <Color>[
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
    // child asks a paint box for that a hue wheel cannot answer.
    Color(0xFFFFDBAC), // Lightest skin
    Color(0xFFF1C27D), // Light skin
    Color(0xFFE0AC69), // Medium skin
    Color(0xFFC68642), // Medium deep skin
    Color(0xFF8D5524), // Deep skin
    Color(0xFF4A2C1A), // Deepest skin
  ];

  static const List<String> _legacyNames = <String>[
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
    // Every skin tone says "skin": the ramp reads as one set, and a name
    // spoken on its own ('Medium deep') would not say what it is.
    'Lightest skin',
    'Light skin',
    'Medium skin',
    'Medium deep skin',
    'Deep skin',
    'Deepest skin',
  ];

  /// The hue of columns 1-15, in degrees, and what each is called.
  ///
  /// Not evenly spaced: the eye separates hues unevenly, telling a yellow from
  /// an orange across a few degrees while a wide stretch of green reads as one
  /// colour. The gaps here are narrowest through the cyans and blues and widest
  /// from yellow to green, so that neighbours look like neighbours all the way
  /// round. Brown has no column of its own because it is dark orange, which
  /// rows 12-14 of the orange column already are.
  static const List<(String, double)> _hues = <(String, double)>[
    ('red', 0),
    ('orange', 30),
    ('yellow', 55),
    ('lime', 80),
    ('green', 125),
    ('mint', 152),
    ('teal', 174),
    ('cyan', 190),
    ('sky', 205),
    ('blue', 222),
    ('indigo', 245),
    ('violet', 268),
    ('purple', 288),
    ('magenta', 314),
    ('pink', 338),
  ];

  /// HSL lightness of grid row `row`: 0.93 down to 0.10, with the pure,
  /// fully saturated tone at row [_pureRow] (0.5) and the steps either side
  /// sized to reach the ends.
  ///
  /// The top stops short of white and the bottom short of black so that the
  /// extremes of a hue column stay recognisably that hue — pale pink rather
  /// than a second white, deep blue rather than a second black. The grey
  /// column, which does run to both, is where a child finds those.
  static double _lightnessOf(int row) => row <= _pureRow
      ? 0.93 - row * (0.93 - 0.5) / _pureRow
      : 0.5 - (row - _pureRow) * (0.5 - 0.10) / (gridRows - 1 - _pureRow);

  /// The word for each row's lightness, with a step number appended where a
  /// word covers more than one row ('Pale blue', 'Pale blue 2', ...) — sixteen
  /// rows are more than English has distinct words for, and a name has to be
  /// unique to be a useful label for a screen reader.
  static const List<(String, int)> _lightnessWords = <(String, int)>[
    ('Pale', 3), // rows 0-2
    ('Light', 4), // rows 3-6
    ('Bright', 1), // row 7
    ('Vivid', 1), // row 8
    ('Dark', 3), // rows 9-11
    ('Deep', 3), // rows 12-14
    ('Darkest', 1), // row 15
  ];

  /// The grey column's words, rows 0-15. 'Pure' leads the two ends because
  /// 'White' and 'Black' are already taken by the paint-box colours (names are
  /// unique across the whole palette) and the grid's ends are the same
  /// colours.
  static const List<(String, int)> _greyWords = <(String, int)>[
    ('Pure white', 1), // row 0
    ('Light grey', 5), // rows 1-5
    ('Grey', 4), // rows 6-9
    ('Dark grey', 5), // rows 10-14
    ('Pure black', 1), // row 15
  ];

  static final List<Color> _gridColors = _buildGridColors();
  static final List<String> _gridNames = _buildGridNames();

  static List<Color> _buildGridColors() {
    final result = List<Color>.filled(gridSize, const Color(0xFF000000));
    for (var row = 0; row < gridRows; row++) {
      // 255 / 15 is a whole 17, so sixteen greys step by exactly 17 and end on
      // pure white and pure black.
      final grey = 255 - 17 * row;
      result[row * gridColumns] = Color.fromARGB(255, grey, grey, grey);
      for (var column = 1; column < gridColumns; column++) {
        final hsl = HSLColor.fromAHSL(
          1,
          _hues[column - 1].$2,
          1,
          _lightnessOf(row),
        );
        // Rounded to 8 bits per channel, which is all a screen shows and all
        // a PNG export keeps, so a grid colour compares equal to itself after
        // a trip through either.
        result[row * gridColumns + column] = Color(hsl.toColor().toARGB32());
      }
    }
    return List.unmodifiable(result);
  }

  static List<String> _buildGridNames() {
    final result = List<String>.filled(gridSize, '');
    for (var row = 0; row < gridRows; row++) {
      result[row * gridColumns] = _stepName(_greyWords, row, '');
      for (var column = 1; column < gridColumns; column++) {
        result[row * gridColumns + column] = _stepName(
          _lightnessWords,
          row,
          ' ${_hues[column - 1].$1}',
        );
      }
    }
    return List.unmodifiable(result);
  }

  /// The name of row `row` in a ladder of (word, row count) runs: the word
  /// with `suffix`, numbered from 2 on its second and later rows.
  static String _stepName(List<(String, int)> ladder, int row, String suffix) {
    var first = 0;
    for (final (word, count) in ladder) {
      if (row < first + count) {
        final step = row - first + 1;
        return step == 1 ? '$word$suffix' : '$word$suffix $step';
      }
      first += count;
    }
    throw RangeError.range(row, 0, first - 1, 'row');
  }

  /// Every colour, positional against [names] and [Stroke.colorIndex].
  static final List<Color> colors = List.unmodifiable(<Color>[
    ..._legacyColors,
    ..._gridColors,
  ]);

  /// The spoken name of each of [colors], all different.
  static final List<String> names = List.unmodifiable(<String>[
    ..._legacyNames,
    ..._gridNames,
  ]);

  /// The palette index of grid cell (`row`, `column`), counted from the top
  /// left: column 0 the greys, columns 1-15 the hues.
  static int gridIndex(int row, int column) {
    RangeError.checkValueInInterval(row, 0, gridRows - 1, 'row');
    RangeError.checkValueInInterval(column, 0, gridColumns - 1, 'column');
    return gridStart + row * gridColumns + column;
  }

  /// Whether `index` is one of the grid's [gridSize] colours.
  static bool isGridIndex(int index) =>
      index >= gridStart && index < gridStart + gridSize;

  /// The grid row of grid index `index` — the inverse of [gridIndex].
  static int gridRowOf(int index) {
    assert(isGridIndex(index), 'index $index is not in the grid');
    return (index - gridStart) ~/ gridColumns;
  }

  /// The grid column of grid index `index` — the inverse of [gridIndex].
  static int gridColumnOf(int index) {
    assert(isGridIndex(index), 'index $index is not in the grid');
    return (index - gridStart) % gridColumns;
  }

  /// The indices the picker offers, in the order it shows them: the grid's
  /// [gridSize] colours row by row, then the six skin tones.
  ///
  /// A subset of [colors] on purpose. The paint-box colours 0-11 are not
  /// offered because the grid has a near-equivalent of each, and the skin
  /// tones are, because it does not. Strokes already drawn in a paint-box
  /// colour still render — nothing here is about what [colorAt] accepts.
  static final List<int> pickerIndices = List.unmodifiable(<int>[
    for (var i = gridStart; i < gridStart + gridSize; i++) i,
    for (var i = _skinStart; i < gridStart; i++) i,
  ]);

  /// Whether the picker offers `index`, so a caller can tell a colour it can
  /// highlight from one that exists only for old drawings.
  static bool isOffered(int index) =>
      isGridIndex(index) || (index >= _skinStart && index < gridStart);

  /// The paint colour for [Stroke.colorIndex] `index`. Never called for an
  /// eraser stroke ([Stroke.isEraser]).
  static Color colorAt(int index) => colors[index];

  /// The spoken name for `index`, for the swatch's own [Semantics] label and
  /// for anywhere else a colour needs to be said rather than shown.
  static String nameAt(int index) => names[index];

  /// The index of the offered swatch ([pickerIndices]) that looks most like
  /// [color] — what the colour dropper (`color_dropper.dart`) turns a pixel of
  /// a photo, or the sheet's own paper, into, because a stroke can only store
  /// an index (`stroke.dart`).
  ///
  /// Only offered indices are candidates, never the paint-box colours 0-11:
  /// the answer becomes the current colour, and a current colour the picker
  /// has no swatch for could not be shown as chosen.
  ///
  /// Distance is the "redmean" weighting of RGB: close to how the eye
  /// separates colours at the cost of three multiplications, where plain RGB
  /// distance calls a mid-grey nearer to Teal than to Black or White. Ties go
  /// to the lower index, so the answer never depends on anything but
  /// [colors]'s order. [color]'s alpha is ignored; a caller with a
  /// translucent colour blends it first.
  static int nearestIndex(Color color) {
    var best = -1;
    var bestDistance = double.infinity;
    for (final i in _nearestCandidates) {
      final candidate = colors[i];
      final redMean = (color.r + candidate.r) / 2;
      final dr = color.r - candidate.r;
      final dg = color.g - candidate.g;
      final db = color.b - candidate.b;
      final distance =
          (2 + redMean) * dr * dr + 4 * dg * dg + (3 - redMean) * db * db;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best;
  }

  /// The offered indices in ascending order — [pickerIndices] lists the skin
  /// tones last, which would hand a tie between a skin tone and a grid colour
  /// to the grid's higher index and break [nearestIndex]'s lower-wins rule.
  static final List<int> _nearestCandidates = List.unmodifiable(
    pickerIndices.toList()..sort(),
  );
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
