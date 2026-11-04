// The Santa skin's goal frames, labels and timings (`PLAN-phase-9-tracks.md`
// §4.8, §6 PR 9). The day/night palettes of every skin are in
// `water_skin_test.dart`.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/audio/motif.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/features/tracks/skins/santa_skin.dart';
import 'package:zibo_games/features/tracks/skins/track_skins.dart';
import 'package:zibo_games/features/tracks/skins/train_skin.dart';

void main() {
  group('the house', () {
    test('is dark at arrival 0 and smoking at 1', () {
      expect(
        identical(SantaSkin.goalSpriteFor(0), SantaSkin.houseDark),
        isTrue,
      );
      expect(
        identical(SantaSkin.goalSpriteFor(1), SantaSkin.houseSmoke),
        isTrue,
      );
    });

    test('lights its windows in between', () {
      expect(
        identical(SantaSkin.goalSpriteFor(0.5), SantaSkin.houseLit),
        isTrue,
      );
    });

    test('never goes backwards as arrival rises', () {
      final order = [
        SantaSkin.houseDark,
        SantaSkin.houseLit,
        SantaSkin.houseSmoke,
      ];
      var last = 0;
      for (var i = 0; i <= 100; i++) {
        final index = order.indexOf(SantaSkin.goalSpriteFor(i / 100));
        expect(index, greaterThanOrEqualTo(last));
        last = index;
      }
      expect(last, 2);
    });

    test('the three frames are different drawings', () {
      expect(SantaSkin.houseDark.rows, isNot(SantaSkin.houseLit.rows));
      expect(SantaSkin.houseLit.rows, isNot(SantaSkin.houseSmoke.rows));
      expect(SantaSkin.houseDark.rows, isNot(SantaSkin.houseSmoke.rows));
    });
  });

  test('trackSkinFor builds a SantaSkin in the brightness asked for', () {
    for (final brightness in Brightness.values) {
      final skin = trackSkinFor(TracksTheme.santa, brightness);
      expect(skin, isA<SantaSkin>());
      expect(skin.theme, TracksTheme.santa);
      expect(skin.brightness, brightness);
    }
  });

  test('labels, timings and motif', () {
    const santa = SantaSkin(Brightness.light);
    expect(santa.name, 'Santa');
    expect(santa.travellerLabel, 'Santa');
    expect(santa.goalLabel, 'the house');
    expect(santa.cellsPerSecond, 2.5);
    expect(santa.arrivalDuration, const Duration(milliseconds: 800));
    expect(santa.arrivalMotif, Motif.tracksSleighBells);
  });

  test('Santa is slower than the train', () {
    expect(
      const SantaSkin(Brightness.light).cellsPerSecond,
      lessThan(const TrainSkin(Brightness.light).cellsPerSecond),
    );
  });
}
