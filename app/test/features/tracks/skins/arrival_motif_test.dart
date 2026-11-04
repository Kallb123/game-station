// Each theme's arrival motif (`PLAN-phase-9-tracks.md` §4.10): present in both
// brightnesses, and different per theme, so what sounds at the goal tells the
// child which traveller arrived.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/features/tracks/skins/track_skins.dart';

void main() {
  test('every theme has an arrival motif in both brightnesses', () {
    for (final theme in TracksTheme.values) {
      for (final brightness in Brightness.values) {
        final motif = trackSkinFor(theme, brightness).arrivalMotif;
        expect(motif, isNotNull, reason: '$theme $brightness');
        expect(motif!.asset, startsWith('tracks/'), reason: '$theme');
      }
    }
  });

  test('the four themes have four distinct motifs', () {
    final motifs = {
      for (final theme in TracksTheme.values)
        trackSkinFor(theme, Brightness.light).arrivalMotif,
    };
    expect(motifs, hasLength(TracksTheme.values.length));
  });
}
