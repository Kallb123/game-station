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
    // Pinned by value as well as name: the grid replaced the paint box in the
    // picker, but a drawing saved in Brown must still reopen brown.
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

  group('pickerIndices', () {
    test('are the grid then the skin tones, each once, all in range', () {
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

    test('leave out the paint-box colours but still render them', () {
      for (var i = 0; i < 12; i++) {
        expect(DrawPalette.pickerIndices, isNot(contains(i)));
        expect(DrawPalette.isOffered(i), isFalse);
        expect(DrawPalette.colorAt(i), isA<Color>());
      }
      for (var i = 12; i < 18; i++) {
        expect(DrawPalette.pickerIndices, contains(i));
        expect(DrawPalette.isOffered(i), isTrue);
      }
    });
  });

  test('the default is an offered, pure red', () {
    final color = DrawPalette.colorAt(DrawPalette.defaultIndex);

    expect(DrawPalette.pickerIndices, contains(DrawPalette.defaultIndex));
    expect(DrawPalette.nameAt(DrawPalette.defaultIndex), 'Vivid red');
    expect(color, const Color(0xFFFF0000));
  });

  group('nearestIndex', () {
    test('every offered swatch is its own nearest', () {
      for (final i in DrawPalette.pickerIndices) {
        expect(
          DrawPalette.nearestIndex(DrawPalette.colorAt(i)),
          i,
          reason: DrawPalette.nameAt(i),
        );
      }
    });

    test('only ever answers an offered index', () {
      final samples = <Color>[
        // The paint-box colours: each has a near-equivalent in the grid, and
        // must be answered with that rather than with itself.
        for (var i = 0; i < 12; i++) DrawPalette.colorAt(i),
        const Color(0xFF000000),
        const Color(0xFFFFFFFF),
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
        expect(DrawPalette.pickerIndices, contains(index));
      }
    });

    test('a paint-box colour lands on a grid colour of the same family', () {
      // Red, Sky and Yellow are not in the grid exactly, but must not jump
      // hue family: the dropper is how a child matches a colour they drew with.
      for (final (legacyIndex, hue) in [(0, 0.0), (5, 200.0), (2, 50.0)]) {
        final nearest = DrawPalette.colorAt(
          DrawPalette.nearestIndex(DrawPalette.colorAt(legacyIndex)),
        );
        final got = HSLColor.fromColor(nearest).hue;

        expect(
          (got - hue).abs() < 20 || (got - hue).abs() > 340,
          isTrue,
          reason: '${DrawPalette.nameAt(legacyIndex)} became hue $got',
        );
      }
    });

    test('black and white map to the grid\'s black and white', () {
      expect(
        DrawPalette.nearestIndex(const Color(0xFF000000)),
        DrawPalette.gridIndex(15, 0),
      );
      expect(
        DrawPalette.nearestIndex(const Color(0xFFFFFFFF)),
        DrawPalette.gridIndex(0, 0),
      );
    });

    test('near-black and near-white stay in the grey column, not a hue', () {
      // The near-white and near-black surfaces the day and night themes paint
      // the sheet with, and a plain mid-grey.
      for (final (color, rows) in [
        (const Color(0xFF141218), (13, 15)),
        (const Color(0xFF1A1A1A), (13, 15)),
        (const Color(0xFFF2F2F2), (0, 1)),
        (const Color(0xFFFEF7FF), (0, 1)),
        (const Color(0xFF808080), (6, 9)),
      ]) {
        final index = DrawPalette.nearestIndex(color);

        expect(DrawPalette.isGridIndex(index), isTrue, reason: '$color');
        expect(DrawPalette.gridColumnOf(index), 0, reason: '$color');
        expect(
          DrawPalette.gridRowOf(index),
          inInclusiveRange(rows.$1, rows.$2),
          reason: '$color',
        );
      }
    });

    test('a skin tone is its own nearest, not a nearby orange', () {
      for (var i = 12; i < 18; i++) {
        expect(DrawPalette.nearestIndex(DrawPalette.colorAt(i)), i);
      }
    });

    test('ignores alpha: the caller blends before asking', () {
      expect(
        DrawPalette.nearestIndex(const Color(0x00FF0000)),
        DrawPalette.defaultIndex,
      );
    });
  });
}
