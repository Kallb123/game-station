// Which skin draws which theme (`PLAN-phase-9-tracks.md` §4.8).

import 'dart:ui';

import '../../../core/storage/save_data.dart' show TracksTheme;
import 'pixel_sprite.dart';
import 'track_skin.dart';
import 'train_skin.dart';
import 'water_skin.dart';

/// The skin for [theme], built for [brightness].
///
/// `santa` and `snail` return the train skin until PR 9 builds them
/// (`PLAN-phase-9-tracks.md` §6): a profile that saved either theme still
/// gets a working board. The switch has no default, so adding a theme to the
/// enum is a compile error here rather than a silent train.
TrackSkin trackSkinFor(TracksTheme theme, Brightness brightness) =>
    switch (theme) {
      TracksTheme.train => TrainSkin(brightness),
      TracksTheme.santa => TrainSkin(brightness),
      TracksTheme.snail => TrainSkin(brightness),
      TracksTheme.water => WaterSkin(brightness),
    };

/// Every sprite [skin] draws, so the sprite-table test reaches all of them
/// without knowing each skin's names.
List<PixelSprite> spritesOf(TrackSkin skin) => switch (skin) {
  TrainSkin() => TrainSkin.sprites,
  WaterSkin() => WaterSkin.sprites,
  _ => throw ArgumentError.value(skin, 'skin', 'has no sprite list'),
};
