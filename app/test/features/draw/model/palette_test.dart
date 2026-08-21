// The palette's positional contract (`palette.dart`). A drawing stores a
// colour as an index into this table (`PLAN-phase-8.md` §4.1), so what an
// index means has to outlive every later change to it — which is what makes
// appending the skin tones safe and moving anything above them not.

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/draw/model/palette.dart';

void main() {
  test('every colour has a spoken name', () {
    expect(DrawPalette.names, hasLength(DrawPalette.colors.length));
    expect(DrawPalette.names, isNot(contains('')));
  });

  test('the paint-box colours keep the indices drawings were saved with', () {
    // Names rather than colour values: retuning a swatch is allowed and
    // reopens old drawings in the new colour, which is the reason a stroke
    // stores an index at all. Moving one to a different index is not — it
    // repaints an old drawing in a colour nobody chose.
    expect(DrawPalette.names.take(12), [
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
    ]);
  });

  test('the skin tones are appended after them, and say so when spoken', () {
    final skinTones = DrawPalette.names.skip(12).toList();

    expect(skinTones, hasLength(6));
    expect(skinTones, everyElement(endsWith(' skin')));
    // Their order is the tool row's third rail line, left to right, so it is
    // the order a child reads them in.
    expect(skinTones.first, 'Lightest skin');
    expect(skinTones.last, 'Deepest skin');
  });

  test('the skin tones darken by one step at a time', () {
    // The names promise a ramp — "Lightest" through "Deepest" — and a ramp
    // whose middle two swatches are the wrong way round says the wrong thing
    // while looking fine on the row.
    final luminances = [
      for (var i = 12; i < DrawPalette.colors.length; i++)
        DrawPalette.colorAt(i).computeLuminance(),
    ];

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

  test('no two swatches share a colour or a name', () {
    expect(DrawPalette.colors.toSet(), hasLength(DrawPalette.colors.length));
    expect(DrawPalette.names.toSet(), hasLength(DrawPalette.names.length));
  });
}
