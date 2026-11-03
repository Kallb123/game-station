// Palette-indexed pixel sprites, declared as Dart strings
// (`PLAN-phase-9-tracks.md` §4.8).
//
// `invaders/model/sprites.dart` stores one bit per pixel; a traveller needs a
// handful of colours, so a pixel here is one character and the sprite carries
// a palette from character to colour. `'.'` is transparent and never in a
// palette. No binary file, no licence line, exact at any cell size, and a
// change to a drawing is a diff a reviewer can read.
//
// Sprites are never rotated (§4.8): an upside-down Santa reads as broken. The
// one transform is a horizontal flip, for a traveller heading west.

import 'dart:ui';

import 'package:flutter/foundation.dart' show immutable;

/// The side of every sprite, in pixels. One value so a sprite and the square it
/// is drawn into always agree.
const int spriteSize = 16;

/// The transparent pixel.
const String transparentPixel = '.';

/// One drawing: [rows] top to bottom, one character per pixel, with a [day]
/// and a [night] palette over the same characters.
@immutable
class PixelSprite {
  const PixelSprite({
    required this.rows,
    required this.day,
    Map<String, Color>? night,
  }) : night = night ?? day;

  /// Top to bottom, [spriteSize] strings of [spriteSize] characters.
  final List<String> rows;

  /// Character to colour, by day.
  final Map<String, Color> day;

  /// Character to colour, by night. The day palette when none is given: most
  /// sprites read the same in both, and a sprite drawn on a dark margin
  /// changes only where it would otherwise vanish.
  final Map<String, Color> night;

  /// The palette for [brightness].
  Map<String, Color> paletteFor(Brightness brightness) =>
      brightness == Brightness.dark ? night : day;

  /// What is wrong with this sprite's declaration, or an empty list.
  ///
  /// Checked by a test over every sprite in every skin rather than at paint
  /// time: a typo in a table is a build failure, not a missing pixel on a
  /// child's screen.
  List<String> problems() {
    final found = <String>[];
    if (rows.length != spriteSize) {
      found.add('has ${rows.length} rows, not $spriteSize');
    }
    for (var y = 0; y < rows.length; y++) {
      final row = rows[y];
      if (row.length != spriteSize) {
        found.add('row $y has ${row.length} pixels, not $spriteSize');
      }
      for (var x = 0; x < row.length; x++) {
        final pixel = row[x];
        if (pixel == transparentPixel) continue;
        if (!day.containsKey(pixel)) {
          found.add('row $y column $x: "$pixel" is not in the day palette');
        }
        if (!night.containsKey(pixel)) {
          found.add('row $y column $x: "$pixel" is not in the night palette');
        }
      }
    }
    if (day.containsKey(transparentPixel) ||
        night.containsKey(transparentPixel)) {
      found.add(
        '"$transparentPixel" is transparent and cannot be in a palette',
      );
    }
    return found;
  }

  /// Draws the sprite filling [rect], flipped left to right when [flipX].
  ///
  /// Consecutive pixels of one colour in a row are one rectangle, so a 16 x 16
  /// sprite costs tens of `drawRect` calls rather than 256. Pixel edges are
  /// rounded to whole logical pixels so neighbouring runs never leave a seam.
  void paint(
    Canvas canvas,
    Rect rect,
    Brightness brightness, {
    bool flipX = false,
  }) {
    final palette = paletteFor(brightness);
    final paint = Paint()..isAntiAlias = false;
    double xAt(int column) =>
        (rect.left + rect.width * column / spriteSize).roundToDouble();
    double yAt(int row) =>
        (rect.top + rect.height * row / spriteSize).roundToDouble();

    for (var y = 0; y < rows.length; y++) {
      final row = rows[y];
      var x = 0;
      while (x < row.length) {
        final pixel = row[x];
        var end = x + 1;
        while (end < row.length && row[end] == pixel) {
          end++;
        }
        final colour = palette[pixel];
        if (pixel != transparentPixel && colour != null) {
          final from = flipX ? spriteSize - end : x;
          final to = flipX ? spriteSize - x : end;
          paint.color = colour;
          canvas.drawRect(
            Rect.fromLTRB(xAt(from), yAt(y), xAt(to), yAt(y + 1)),
            paint,
          );
        }
        x = end;
      }
    }
  }
}
