// The sprite declaration check (`PLAN-phase-9-tracks.md` §4.8). The check is a
// guard the sprite-table test leans on for every real sprite, so it needs a
// test of its own: a guard that cannot fail proves nothing.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/tracks/skins/pixel_sprite.dart';

const Color _red = Color(0xFFFF0000);
const Color _blue = Color(0xFF0000FF);

/// Sixteen rows of sixteen pixels, `#` in the first.
List<String> _rows() => [
  '#${'.' * 15}',
  for (var i = 1; i < spriteSize; i++) '.' * spriteSize,
];

void main() {
  test('a good sprite has no problems', () {
    final sprite = PixelSprite(rows: _rows(), day: {'#': _red});
    expect(sprite.problems(), isEmpty);
  });

  test('a separate night palette is checked as well, and passes', () {
    final sprite = PixelSprite(
      rows: _rows(),
      day: {'#': _red},
      night: {'#': _blue},
    );
    expect(sprite.problems(), isEmpty);
  });

  test('a wrong row count is reported', () {
    final sprite = PixelSprite(rows: _rows().sublist(0, 15), day: {'#': _red});
    expect(sprite.problems(), contains('has 15 rows, not 16'));
  });

  test('a wrong row length is reported', () {
    final rows = _rows()..[3] = '.' * 15;
    final sprite = PixelSprite(rows: rows, day: {'#': _red});
    expect(sprite.problems(), contains('row 3 has 15 pixels, not 16'));
  });

  test('a character missing from the day palette is reported', () {
    final rows = _rows()..[2] = 'x${'.' * 15}';
    final sprite = PixelSprite(
      rows: rows,
      day: {'#': _red},
      night: {'#': _red, 'x': _blue},
    );
    final problems = sprite.problems();
    expect(problems, hasLength(1));
    expect(problems.single, contains('"x" is not in the day palette'));
  });

  test('a character missing from the night palette is reported', () {
    final rows = _rows()..[2] = 'x${'.' * 15}';
    final sprite = PixelSprite(
      rows: rows,
      day: {'#': _red, 'x': _blue},
      night: {'#': _red},
    );
    final problems = sprite.problems();
    expect(problems, hasLength(1));
    expect(problems.single, contains('"x" is not in the night palette'));
  });

  test('transparent in a palette is reported, day or night', () {
    final inDay = PixelSprite(
      rows: _rows(),
      day: {'#': _red, '.': _blue},
      night: {'#': _red},
    );
    expect(inDay.problems(), hasLength(1));
    expect(inDay.problems().single, contains('transparent'));

    final inNight = PixelSprite(
      rows: _rows(),
      day: {'#': _red},
      night: {'#': _red, '.': _blue},
    );
    expect(inNight.problems(), hasLength(1));
  });

  test('night defaults to the day palette', () {
    final sprite = PixelSprite(rows: _rows(), day: {'#': _red});
    expect(sprite.paletteFor(Brightness.dark), same(sprite.day));
  });
}
