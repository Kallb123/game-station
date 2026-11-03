// The water skin's goal frames and the day/night palettes of every skin
// (`PLAN-phase-9-tracks.md` §4.8, §6 PR 6).

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/features/tracks/skins/track_skins.dart';
import 'package:zibo_games/features/tracks/skins/water_skin.dart';

void main() {
  group('the flower', () {
    test('is wilted at arrival 0 and lush at 1', () {
      expect(
        identical(WaterSkin.goalSpriteFor(0), WaterSkin.wiltedFlower),
        isTrue,
      );
      expect(
        identical(WaterSkin.goalSpriteFor(1), WaterSkin.lushFlower),
        isTrue,
      );
    });

    test('lifts in between', () {
      expect(
        identical(WaterSkin.goalSpriteFor(0.5), WaterSkin.liftingFlower),
        isTrue,
      );
    });

    test('never goes backwards as arrival rises', () {
      final order = [
        WaterSkin.wiltedFlower,
        WaterSkin.liftingFlower,
        WaterSkin.lushFlower,
      ];
      var last = 0;
      for (var i = 0; i <= 100; i++) {
        final index = order.indexOf(WaterSkin.goalSpriteFor(i / 100));
        expect(index, greaterThanOrEqualTo(last));
        last = index;
      }
      expect(last, 2);
    });

    test('the three frames are different drawings', () {
      expect(WaterSkin.wiltedFlower.rows, isNot(WaterSkin.liftingFlower.rows));
      expect(WaterSkin.liftingFlower.rows, isNot(WaterSkin.lushFlower.rows));
    });
  });

  group('palettes', () {
    for (final theme in TracksTheme.values) {
      test('${theme.name}: night colours differ from day', () {
        final day = trackSkinFor(theme, Brightness.light).colours;
        final night = trackSkinFor(theme, Brightness.dark).colours;
        expect(night.margin, isNot(day.margin));
        expect(night.ground, isNot(day.ground));
        expect(night.clue, isNot(day.clue));
        expect(night.track, isNot(day.track));
        // A dark margin must be darker than a light one, or night is not night.
        expect(
          night.margin.computeLuminance(),
          lessThan(day.margin.computeLuminance()),
        );
      });
    }
  });

  test('labels and timings', () {
    final water = WaterSkin(Brightness.light);
    expect(water.name, 'Water');
    expect(water.travellerLabel, 'the water');
    expect(water.goalLabel, 'the flower');
    expect(water.cellsPerSecond, 4);
    expect(water.arrivalDuration, const Duration(milliseconds: 900));
  });
}
