// The solve animation as arithmetic (`PLAN-phase-9-tracks.md` §4.8): what the
// board shows at any elapsed time, with no ticker and no pixels.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/core/storage/save_data.dart' show TracksTheme;
import 'package:zibo_games/features/tracks/skins/journey.dart';
import 'package:zibo_games/features/tracks/skins/track_geometry.dart';
import 'package:zibo_games/features/tracks/skins/track_skin.dart';

/// A skin that paints nothing and has round numbers for speed and arrival.
class _FakeSkin implements TrackSkin {
  _FakeSkin({this.arrivalDuration = const Duration(milliseconds: 500)});

  @override
  final Duration arrivalDuration;

  @override
  double get cellsPerSecond => 2;

  @override
  TracksTheme get theme => TracksTheme.train;

  @override
  Brightness get brightness => Brightness.light;

  @override
  String get name => 'Fake';

  @override
  String get travellerLabel => 'the fake';

  @override
  String get goalLabel => 'the goal';

  @override
  SkinColours get colours => const SkinColours(
    margin: Color(0xFF000000),
    ground: Color(0xFF000000),
    gridLine: Color(0xFF000000),
    track: Color(0xFF000000),
    fixedTrack: Color(0xFF000000),
    wrong: Color(0xFF000000),
    mark: Color(0xFF000000),
    clue: Color(0xFF000000),
  );

  @override
  void paintGround(Canvas canvas, Rect cell, int row, int column) {}

  @override
  void paintPiece(Canvas canvas, Rect cell, int mask, PieceStyle style) {}

  @override
  void paintMark(Canvas canvas, Rect cell) {}

  @override
  void paintStart(Canvas canvas, Rect port, {required bool departed}) {}

  @override
  void paintGoal(Canvas canvas, Rect port, double arrival) {}

  @override
  void paintJourney(
    Canvas canvas,
    BoardLayout layout,
    TrackGeometry route,
    double t,
  ) {}
}

/// A straight row east along row 0 and south down column 4 of a 5x5: a
/// route of 0.5 + 4 + pi/4 + 4 + 0.5 grid units, enough that no test depends
/// on a particular length.
TrackGeometry _route() {
  const w = TrackSide.west, e = TrackSide.east;
  const n = TrackSide.north, s = TrackSide.south;
  final cells = List<int>.filled(25, 0);
  for (var c = 0; c < 4; c++) {
    cells[c] = w | e;
  }
  cells[4] = w | s;
  for (var r = 1; r < 5; r++) {
    cells[r * 5 + 4] = n | s;
  }
  final clues = TracksClues(
    spec: TracksSpec.s5x5,
    startRow: 0,
    goalColumn: 4,
    rowCounts: List.filled(5, 0),
    columnCounts: List.filled(5, 0),
    fixed: List.filled(25, 0),
  );
  return TrackGeometry.trace(clues, cells)!;
}

void main() {
  final route = _route();
  final skin = _FakeSkin();
  final travel = travelDuration(skin, route);

  test('travel is the route length at the skin\'s speed', () {
    expect(
      travel.inMicroseconds / Duration.microsecondsPerSecond,
      closeTo(route.length / 2, 1e-6),
    );
  });

  test('the whole animation is travel plus arrival', () {
    expect(journeyDuration(skin, route), travel + skin.arrivalDuration);
  });

  group('journeyFrameAt', () {
    test('waits at zero and before', () {
      expect(journeyFrameAt(skin, route, Duration.zero), JourneyFrame.waiting);
      expect(
        journeyFrameAt(skin, route, const Duration(seconds: -1)),
        JourneyFrame.waiting,
      );
    });

    test('t rises linearly during travel with the goal still waiting', () {
      for (final fraction in [0.1, 0.25, 0.5, 0.9]) {
        final elapsed = Duration(
          microseconds: (travel.inMicroseconds * fraction).round(),
        );
        final frame = journeyFrameAt(skin, route, elapsed);
        expect(frame.t, closeTo(fraction, 1e-6));
        expect(frame.arrival, 0);
      }
    });

    test('t is 1 and arrival rises once the traveller has arrived', () {
      final at = journeyFrameAt(skin, route, travel);
      expect(at.t, 1);
      expect(at.arrival, 0);

      final half = journeyFrameAt(
        skin,
        route,
        travel + skin.arrivalDuration ~/ 2,
      );
      expect(half.t, 1);
      expect(half.arrival, closeTo(0.5, 1e-6));
    });

    test('is arrived at and past the end', () {
      final end = journeyDuration(skin, route);
      expect(journeyFrameAt(skin, route, end), JourneyFrame.arrived);
      expect(
        journeyFrameAt(skin, route, end + const Duration(hours: 1)),
        JourneyFrame.arrived,
      );
    });

    test('a zero arrival jumps straight to arrived', () {
      final instant = _FakeSkin(arrivalDuration: Duration.zero);
      final travelled = travelDuration(instant, route);
      expect(journeyDuration(instant, route), travelled);
      expect(journeyFrameAt(instant, route, travelled), JourneyFrame.arrived);
      expect(journeyFrameAt(instant, route, travelled ~/ 2).arrival, 0);
    });
  });

  test('frames compare by value', () {
    expect(const JourneyFrame(0.5, 0), const JourneyFrame(0.5, 0));
    expect(const JourneyFrame(0.5, 0), isNot(const JourneyFrame(0.5, 1)));
  });
}
