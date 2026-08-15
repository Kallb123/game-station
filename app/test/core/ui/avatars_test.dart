// The avatar mapping: that no two avatars look alike.
//
// A child picks their profile by its picture, so two avatars a child cannot
// tell apart are the same failure as two profiles with the same name — and the
// picture, the colour and the name each have to carry the difference on their
// own, because a player who cannot use one of the three still has to be able to
// find themselves.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/ui/avatars.dart';

void main() {
  test('every avatar has a picture of its own', () {
    final icons = AvatarId.values.map(avatarIcon).toSet();

    expect(icons, hasLength(AvatarId.values.length));
  });

  for (final brightness in Brightness.values) {
    test('every avatar has a $brightness colour of its own', () {
      // This also covers the swatch list agreeing with the enum: a missing
      // swatch trips the assert in `avatarColor`, and a wrapped-round one shows
      // up here as a duplicate.
      final colors = AvatarId.values
          .map((avatar) => avatarColor(avatar, brightness))
          .toSet();

      expect(colors, hasLength(AvatarId.values.length));
    });
  }

  test('every avatar has a name of its own', () {
    final names = AvatarId.values.map(avatarLabel).toSet();

    expect(names, hasLength(AvatarId.values.length));
    expect(names, everyElement(isNotEmpty));
  });
}
