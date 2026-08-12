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
