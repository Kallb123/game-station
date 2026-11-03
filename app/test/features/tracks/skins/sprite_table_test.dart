// The sprite tables are hand-typed strings, so a typo is a compile-clean bug:
// this reads every sprite of every built skin and fails on the first wrong row
// length or missing palette entry (`PLAN-phase-9-tracks.md` §6, PR 6).

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/features/tracks/skins/pixel_sprite.dart';
import 'package:zibo_games/features/tracks/skins/track_skins.dart';

void main() {
  for (final theme in TracksTheme.values) {
    for (final brightness in Brightness.values) {
      final skin = trackSkinFor(theme, brightness);
      final sprites = spritesOf(skin);

      test('${theme.name} ${brightness.name}: has sprites', () {
        expect(sprites, isNotEmpty);
      });

      for (var i = 0; i < sprites.length; i++) {
        final sprite = sprites[i];
        test('${theme.name} ${brightness.name}: sprite $i is $spriteSize x '
            '$spriteSize and uses only its palette', () {
          expect(sprite.rows, hasLength(spriteSize));
          for (final row in sprite.rows) {
            expect(row, hasLength(spriteSize));
          }
          expect(sprite.problems(), isEmpty);
        });
      }
    }
  }
}
