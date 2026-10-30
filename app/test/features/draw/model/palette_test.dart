// The palette's positional contract (`palette.dart`). A drawing stores a
// colour as an index into this table (`PLAN-phase-8.md` §4.1), so what an
// index means has to outlive every later change to it — which is what makes
// appending the grid safe and moving anything below it not.

import 'package:flutter/painting.dart' show Color, HSLColor;
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/draw/model/palette.dart';

/// The eighteen colours the first release shipped, pinned by value: an old
/// drawing that used one must reopen looking the same.
const List<(String, int)> _legacy = <(String, int)>[
  ('Red', 0xFFE53935),
  ('Orange', 0xFFFB8C00),
  ('Yellow', 0xFFFDD835),
  ('Green', 0xFF43A047),
  ('Teal', 0xFF00897B),
  ('Sky', 0xFF039BE5),
  ('Blue', 0xFF3949AB),
  ('Purple', 0xFF8E24AA),
  ('Pink', 0xFFD81B60),
  ('Brown', 0xFF6D4C41),
  ('Black', 0xFF000000),
  ('White', 0xFFFFFFFF),
  ('Lightest skin', 0xFFFFDBAC),
  ('Light skin', 0xFFF1C27D),
  ('Medium skin', 0xFFE0AC69),
  ('Medium deep skin', 0xFFC68642),
  ('Deep skin', 0xFF8D5524),
  ('Deepest skin', 0xFF4A2C1A),
];

void main() {
  test('every colour has a spoken name', () {
    expect(DrawPalette.colors, hasLength(274));
    expect(DrawPalette.names, hasLength(DrawPalette.colors.length));
    expect(DrawPalette.names, everyElement(isNotEmpty));
  });

  test('no two swatches share a name', () {
    expect(DrawPalette.names.toSet(), hasLength(DrawPalette.names.length));
  });

  test('indices 0-17 keep the colours and names drawings were saved with', () {
    // Pinned by value as well as name: a drawing saved in Brown must still
    // reopen brown, whatever is added after it.
    for (var i = 0; i < _legacy.length; i++) {
      expect(DrawPalette.nameAt(i), _legacy[i].$1, reason: 'name of $i');
      expect(
        DrawPalette.colorAt(i),
        Color(_legacy[i].$2),
        reason: 'colour of $i (${_legacy[i].$1})',
      );
    }
  });

  test('the skin tones darken by one step at a time', () {
    // The names promise a ramp — "Lightest" through "Deepest" — and a ramp
    // whose middle two swatches are the wrong way round says the wrong thing
    // while looking fine in the picker.
    final luminances = [
      for (var i = 12; i < DrawPalette.gridStart; i++)
        DrawPalette.colorAt(i).computeLuminance(),
    ];

    expect(luminances, hasLength(6));
    for (var i = 1; i < luminances.length; i++) {
      expect(
        luminances[i],
        lessThan(luminances[i - 1]),
        reason:
            '${DrawPalette.nameAt(12 + i)} is not darker than the one '
            'before it',
      );
    }
  });

  group('the grid', () {
    test('starts at 18 and is 16 x 16', () {
      expect(DrawPalette.gridStart, 18);
      expect(DrawPalette.gridColumns, 16);
      expect(DrawPalette.gridRows, 16);
      expect(
        DrawPalette.gridStart + DrawPalette.gridSize,
        DrawPalette.colors.length,
      );
    });

    test('holds 256 different colours', () {
      final grid = DrawPalette.colors.skip(DrawPalette.gridStart);

      expect(grid, hasLength(256));
      expect(grid.toSet(), hasLength(256));
    });

    test('gridIndex, gridRowOf and gridColumnOf agree', () {
      expect(DrawPalette.gridIndex(0, 0), 18);
      expect(DrawPalette.gridIndex(15, 15), 273);
      for (var row = 0; row < 16; row++) {
        for (var column = 0; column < 16; column++) {
          final index = DrawPalette.gridIndex(row, column);
          expect(DrawPalette.isGridIndex(index), isTrue);
          expect(DrawPalette.gridRowOf(index), row);
          expect(DrawPalette.gridColumnOf(index), column);
        }
      }
      expect(DrawPalette.isGridIndex(17), isFalse);
      expect(DrawPalette.isGridIndex(274), isFalse);
      expect(() => DrawPalette.gridIndex(16, 0), throwsRangeError);
      expect(() => DrawPalette.gridIndex(0, -1), throwsRangeError);
    });

    test('column 0 is grey, running from white to black', () {
      for (var row = 0; row < 16; row++) {
        final color = DrawPalette.colorAt(DrawPalette.gridIndex(row, 0));
        expect(color.r, color.g, reason: 'row $row');
        expect(color.g, color.b, reason: 'row $row');
        if (row > 0) {
          final above = DrawPalette.colorAt(DrawPalette.gridIndex(row - 1, 0));
          expect(color.r, lessThan(above.r), reason: 'row $row');
        }
      }
      expect(
        DrawPalette.colorAt(DrawPalette.gridIndex(0, 0)),
        const Color(0xFFFFFFFF),
      );
      expect(
        DrawPalette.colorAt(DrawPalette.gridIndex(15, 0)),
        const Color(0xFF000000),
      );
    });

    test('every hue column gets darker down the rows', () {
      for (var column = 1; column < 16; column++) {
        for (var row = 1; row < 16; row++) {
          final above = DrawPalette.colorAt(
            DrawPalette.gridIndex(row - 1, column),
          );
          final here = DrawPalette.colorAt(DrawPalette.gridIndex(row, column));
          expect(
            HSLColor.fromColor(here).lightness,
            lessThan(HSLColor.fromColor(above).lightness),
            reason:
                '${DrawPalette.nameAt(DrawPalette.gridIndex(row, column))}'
                ' is not darker than the row above',
          );
        }
      }
    });

    test('the extremes of a hue stay distinguishable from white and black', () {
      for (var column = 1; column < 16; column++) {
        final top = DrawPalette.colorAt(DrawPalette.gridIndex(0, column));
        final bottom = DrawPalette.colorAt(DrawPalette.gridIndex(15, column));

        expect(top, isNot(const Color(0xFFFFFFFF)));
        expect(
          top.computeLuminance(),
          lessThan(0.98),
          reason: 'column $column',
        );
        expect(bottom, isNot(const Color(0xFF000000)));
        expect(
          bottom.computeLuminance(),
          greaterThan(0.0005),
          reason: 'column $column',
        );
      }
    });

    test('names say the hue and the lightness', () {
      String nameAt(int row, int column) =>
          DrawPalette.nameAt(DrawPalette.gridIndex(row, column));

      expect(nameAt(0, 0), 'Pure white');
      expect(nameAt(15, 0), 'Pure black');
      expect(nameAt(0, 1), 'Pale red');
      expect(nameAt(1, 1), 'Pale red 2');
      expect(nameAt(8, 1), 'Vivid red');
      expect(nameAt(8, 9), 'Vivid sky');
      expect(nameAt(15, 10), 'Darkest blue');
    });
  });

  group('rowIndices and pickerIndices', () {
    test('rowIndices are the twelve paint-box colours, in order', () {
      expect(DrawPalette.rowCount, 12);
      expect(DrawPalette.rowIndices, [for (var i = 0; i < 12; i++) i]);
      expect(DrawPalette.nameAt(DrawPalette.rowIndices.first), 'Red');
      expect(DrawPalette.nameAt(DrawPalette.rowIndices.last), 'White');
    });

    test('pickerIndices are the grid then the skin tones, each once', () {
      final offered = DrawPalette.pickerIndices;

      expect(offered, hasLength(262));
      expect(offered.toSet(), hasLength(262));
      expect(offered.first, DrawPalette.gridStart);
      expect(offered.take(256), [for (var i = 18; i < 274; i++) i]);
      expect(offered.skip(256), [12, 13, 14, 15, 16, 17]);
      for (final index in offered) {
        expect(index, inInclusiveRange(0, DrawPalette.colors.length - 1));
      }
    });

    test('every colour is in the row or the popup, never both', () {
      final row = DrawPalette.rowIndices.toSet();
      final popup = DrawPalette.pickerIndices.toSet();

      expect(row.intersection(popup), isEmpty);
      expect(row.union(popup), hasLength(DrawPalette.colors.length));
      for (var i = 0; i < DrawPalette.colors.length; i++) {
        expect(DrawPalette.isRowIndex(i), row.contains(i), reason: '$i');
        expect(DrawPalette.isPickerIndex(i), popup.contains(i), reason: '$i');
        expect(DrawPalette.isOffered(i), isTrue, reason: '$i');
      }
    });

    test('the skin tones are in the popup, not the row', () {
      for (var i = 12; i < 18; i++) {
        expect(DrawPalette.rowIndices, isNot(contains(i)));
        expect(DrawPalette.pickerIndices, contains(i));
      }
    });

    test('nothing outside the palette is offered', () {
      for (final index in [-1, DrawPalette.colors.length, 1000]) {
        expect(DrawPalette.isRowIndex(index), isFalse, reason: '$index');
        expect(DrawPalette.isPickerIndex(index), isFalse, reason: '$index');
        expect(DrawPalette.isOffered(index), isFalse, reason: '$index');
      }
    });
  });

  test('the default is Red, the first swatch in the tool row', () {
    expect(DrawPalette.defaultIndex, 0);
    expect(DrawPalette.rowIndices, contains(DrawPalette.defaultIndex));
    expect(DrawPalette.nameAt(DrawPalette.defaultIndex), 'Red');
  });

  group('nearestIndex', () {
    test('every colour is its own nearest, except the grid\'s repeats', () {
      // The grid's pure white and pure black equal White (11) and Black (10),
      // and a tie goes to the lower index; every other colour is unique.
      final grey = {
        DrawPalette.gridIndex(0, 0): 11,
        DrawPalette.gridIndex(15, 0): 10,
      };
      for (var i = 0; i < DrawPalette.colors.length; i++) {
        expect(
          DrawPalette.nearestIndex(DrawPalette.colorAt(i)),
          grey[i] ?? i,
          reason: DrawPalette.nameAt(i),
        );
      }
    });

    test('answers a row swatch for an exact paint-box colour', () {
      for (final i in DrawPalette.rowIndices) {
        expect(DrawPalette.nearestIndex(DrawPalette.colorAt(i)), i);
      }
    });

    test('black and white tie with the grid and go to the row swatch', () {
      expect(
        DrawPalette.colorAt(DrawPalette.gridIndex(0, 0)),
        const Color(0xFFFFFFFF),
      );
      expect(
        DrawPalette.colorAt(DrawPalette.gridIndex(15, 0)),
        const Color(0xFF000000),
      );

      expect(DrawPalette.nearestIndex(const Color(0xFF000000)), 10);
      expect(DrawPalette.nearestIndex(const Color(0xFFFFFFFF)), 11);
    });

    test('only ever answers an offered index', () {
      final samples = <Color>[
        const Color(0xFF808080),
        const Color(0xFF7F7F7F),
        // A sweep over the cube, coarse enough to be quick and off the grid's
        // own values.
        for (var r = 0; r < 256; r += 37)
          for (var g = 0; g < 256; g += 41)
            for (var b = 0; b < 256; b += 43) Color.fromARGB(255, r, g, b),
      ];

      for (final color in samples) {
        final index = DrawPalette.nearestIndex(color);
        expect(
          DrawPalette.isOffered(index),
          isTrue,
          reason: '$color -> $index',
        );
      }
    });

    test('a colour just off a paint-box colour still lands on it', () {
      // The dropper's photo samples are never exact; the row swatch the child
      // already knows should win over a grid colour that is merely close.
      expect(DrawPalette.nearestIndex(const Color(0xFFE23A36)), 0);
      expect(DrawPalette.nearestIndex(const Color(0xFF3A47AC)), 6);
    });

    test('near-black and near-white stay in the greys, not a hue', () {
      // The near-white and near-black surfaces the day and night themes paint
      // the sheet with, and a plain mid-grey: the answer is Black, White or a
      // grey from the grid's column 0, never a tinted colour.
      for (final color in const [
        Color(0xFF141218),
        Color(0xFF1A1A1A),
        Color(0xFFF2F2F2),
        Color(0xFFFEF7FF),
        Color(0xFF808080),
      ]) {
        final index = DrawPalette.nearestIndex(color);

        expect(
          index == 10 ||
              index == 11 ||
              (DrawPalette.isGridIndex(index) &&
                  DrawPalette.gridColumnOf(index) == 0),
          isTrue,
          reason: '$color -> ${DrawPalette.nameAt(index)}',
        );
      }
    });

    test('a skin tone is its own nearest, not a nearby orange', () {
      for (var i = 12; i < 18; i++) {
        expect(DrawPalette.nearestIndex(DrawPalette.colorAt(i)), i);
      }
    });

    test('ignores alpha: the caller blends before asking', () {
      expect(DrawPalette.nearestIndex(const Color(0x00E53935)), 0);
    });
  });
}
