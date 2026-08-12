// The picture a profile is chosen by.
//
// Material's icon set has no animals, and no art is bundled until phase 6
// (PLAN-phase-1.md §2), so each avatar maps to the most distinct glyph
// available rather than to a likeness. Distinctness is what the mapping is for:
// a child picks their profile by the picture, so eight glyphs that can be told
// apart at arm's length beat eight that are all a paw print. Phase 6 replaces
// them with drawings; the enum in the save file does not change when it does.

import 'package:flutter/material.dart';

import '../storage/save_data.dart';
import 'tokens.dart';

/// The glyph shown for [avatar].
IconData avatarIcon(AvatarId avatar) => switch (avatar) {
  AvatarId.fox => Icons.pets,
  AvatarId.bear => Icons.forest,
  AvatarId.cat => Icons.nightlight,
  AvatarId.dog => Icons.sports_baseball,
  AvatarId.frog => Icons.water_drop,
  AvatarId.owl => Icons.visibility,
  AvatarId.panda => Icons.spa,
  AvatarId.rabbit => Icons.cruelty_free,
};

/// The colour [avatar] is drawn in, from the palette for [brightness].
///
/// Positional against [AvatarId.values]. Adding an avatar to the enum without
/// adding a swatch fails the assert in debug and in tests; in release it wraps
/// round to an already-used colour, because two profiles sharing a colour is a
/// smaller problem than a range error on the screen a child picks their
/// profile from.
Color avatarColor(AvatarId avatar, Brightness brightness) {
  final swatches = AppPalette.of(brightness).avatarSwatches;
  assert(
    swatches.length == AvatarId.values.length,
    'every avatar needs a swatch: ${AvatarId.values.length} avatars, '
    '${swatches.length} swatches',
  );
  return swatches[avatar.index % swatches.length];
}

/// What [avatar] is called.
///
/// A picture needs a name for the same reason every icon-only control in the
/// app has a tooltip: without one, a screen reader announces the profile
/// picker as a row of unlabelled buttons. The animal is the name even though
/// the glyph is not a likeness of it — the drawings in phase 6 are, and the
/// name will not have to change with them.
String avatarLabel(AvatarId avatar) => switch (avatar) {
  AvatarId.fox => 'Fox',
  AvatarId.bear => 'Bear',
  AvatarId.cat => 'Cat',
  AvatarId.dog => 'Dog',
  AvatarId.frog => 'Frog',
  AvatarId.owl => 'Owl',
  AvatarId.panda => 'Panda',
  AvatarId.rabbit => 'Rabbit',
};
