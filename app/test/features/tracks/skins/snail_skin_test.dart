// The snail skin's goal frames, labels and pace (`PLAN-phase-9-tracks.md` §4.8,
// §6 PR 9).

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/audio/motif.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/features/tracks/skins/snail_skin.dart';
import 'package:zibo_games/features/tracks/skins/track_skins.dart';

void main() {
  group('the pumpkin', () {
    test('is dull at arrival 0 and glowing at 1', () {
      expect(
        identical(SnailSkin.goalSpriteFor(0), SnailSkin.pumpkinDull),
        isTrue,
      );
      expect(
        identical(SnailSkin.goalSpriteFor(1), SnailSkin.pumpkinGlowing),
        isTrue,
      );
    });

    test('stirs in between', () {
      expect(
        identical(SnailSkin.goalSpriteFor(0.5), SnailSkin.pumpkinStirring),
        isTrue,
      );
    });

    test('never goes backwards as arrival rises', () {
      final order = [
        SnailSkin.pumpkinDull,
        SnailSkin.pumpkinStirring,
        SnailSkin.pumpkinGlowing,
      ];
      var last = 0;
      for (var i = 0; i <= 100; i++) {
        final index = order.indexOf(SnailSkin.goalSpriteFor(i / 100));
        expect(index, greaterThanOrEqualTo(last));
        last = index;
      }
      expect(last, 2);
    });

    test('the three frames are different drawings', () {
      expect(SnailSkin.pumpkinDull.rows, isNot(SnailSkin.pumpkinStirring.rows));
      expect(
        SnailSkin.pumpkinStirring.rows,
        isNot(SnailSkin.pumpkinGlowing.rows),
      );
    });
  });

  test('labels and timings', () {
    final snail = SnailSkin(Brightness.light);
    expect(snail.theme, TracksTheme.snail);
    expect(snail.name, 'Snail');
    expect(snail.travellerLabel, 'the snail');
    expect(snail.goalLabel, 'the pumpkin');
    expect(snail.cellsPerSecond, 2);
    expect(snail.arrivalDuration, const Duration(milliseconds: 700));
    expect(snail.arrivalMotif, Motif.tracksPop);
  });

  test('the registry builds a snail skin for the brightness asked', () {
    for (final brightness in Brightness.values) {
      final skin = trackSkinFor(TracksTheme.snail, brightness);
      expect(skin, isA<SnailSkin>());
      expect(skin.brightness, brightness);
    }
  });

  test('the snail is the slowest of the four skins', () {
    final snail = trackSkinFor(TracksTheme.snail, Brightness.light);
    for (final theme in TracksTheme.values) {
      if (theme == TracksTheme.snail) continue;
      expect(
        trackSkinFor(theme, Brightness.light).cellsPerSecond,
        greaterThan(snail.cellsPerSecond),
        reason: '${theme.name} should be faster than the snail',
      );
    }
  });
}
