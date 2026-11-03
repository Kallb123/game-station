// Every paint method of every skin runs without throwing, over every piece in
// every style (`PLAN-phase-9-tracks.md` §6, PR 6). Painting onto a recorder
// checks the calls are valid; the pictures themselves are checked by eye.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/features/tracks/skins/track_geometry.dart';
import 'package:zibo_games/features/tracks/skins/track_skin.dart';
import 'package:zibo_games/features/tracks/skins/track_skins.dart';

import '../tracks_fixtures.dart';

/// The six pieces and the four single-bit stubs.
final List<int> _masks = [...TrackSide.pieces, ...TrackSide.all];

/// The route of a real puzzle's solution, or null while `TrackGeometry` is
/// unimplemented.
TrackGeometry? _route(TracksPuzzle puzzle) {
  try {
    return TrackGeometry.trace(puzzle.clues, puzzle.solution);
  } on UnimplementedError {
    return null;
  }
}

void main() {
  final puzzle = puzzleFor('tracks:7x7:medium:0');
  final route = _route(puzzle);

  for (final theme in TracksTheme.values) {
    for (final brightness in Brightness.values) {
      test('${theme.name} ${brightness.name}: every paint method runs', () {
        final skin = trackSkinFor(theme, brightness);
        expect(skin.theme, anyOf(theme, TracksTheme.train));
        expect(skin.brightness, brightness);
        final canvas = Canvas(PictureRecorder());
        const cell = Rect.fromLTWH(20, 20, 48, 48);

        skin.paintGround(canvas, cell, 0, 0);
        skin.paintGround(canvas, cell, 3, 5);
        skin.paintMark(canvas, cell);
        for (final mask in _masks) {
          for (final style in PieceStyle.values) {
            skin.paintPiece(canvas, cell, mask, style);
          }
        }
        for (final departed in [false, true]) {
          skin.paintStart(canvas, cell, departed: departed);
        }
        for (final arrival in [0.0, 0.25, 0.5, 0.75, 1.0]) {
          skin.paintGoal(canvas, cell, arrival);
        }
      });

      test('${theme.name} ${brightness.name}: the journey runs', () {
        if (route == null) {
          markTestSkipped('TrackGeometry is not implemented yet');
          return;
        }
        final skin = trackSkinFor(theme, brightness);
        final layout = BoardLayout.fit(
          const Size(400, 400),
          puzzle.clues.spec.side,
        );
        final canvas = Canvas(PictureRecorder());
        for (final t in [0.0, 0.1, 0.5, 0.99, 1.0]) {
          skin.paintJourney(canvas, layout, route, t);
        }
      });
    }
  }
}
