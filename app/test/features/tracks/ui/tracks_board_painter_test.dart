// The Tracks board painter (`PLAN-phase-9-tracks.md` §4.8, §6 PR 6): every skin
// paints a real board without throwing, and an unsolved board can never show
// an arrived goal or a journey, whatever frame it is handed.

import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/audio/motif.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/features/tracks/model/tracks_session.dart';
import 'package:zibo_games/features/tracks/skins/journey.dart';
import 'package:zibo_games/features/tracks/skins/track_geometry.dart';
import 'package:zibo_games/features/tracks/skins/track_skin.dart';
import 'package:zibo_games/features/tracks/skins/track_skins.dart';
import 'package:zibo_games/features/tracks/skins/water_skin.dart';
import 'package:zibo_games/features/tracks/ui/tracks_board_painter.dart';

import '../tracks_fixtures.dart';

/// Delegates to [inner] and records what the painter asked of the goal and the
/// journey.
class _RecordingSkin implements TrackSkin {
  _RecordingSkin(this.inner);

  final TrackSkin inner;
  final List<double> arrivals = [];
  final List<bool> departures = [];
  int journeys = 0;

  @override
  TracksTheme get theme => inner.theme;
  @override
  Brightness get brightness => inner.brightness;
  @override
  String get name => inner.name;
  @override
  String get travellerLabel => inner.travellerLabel;
  @override
  String get goalLabel => inner.goalLabel;
  @override
  SkinColours get colours => inner.colours;
  @override
  Motif? get arrivalMotif => null;

  @override
  double get cellsPerSecond => inner.cellsPerSecond;
  @override
  Duration get arrivalDuration => inner.arrivalDuration;

  @override
  void paintGround(Canvas canvas, Rect cell, int row, int column) =>
      inner.paintGround(canvas, cell, row, column);
  @override
  void paintPiece(Canvas canvas, Rect cell, int mask, PieceStyle style) =>
      inner.paintPiece(canvas, cell, mask, style);
  @override
  void paintMark(Canvas canvas, Rect cell) => inner.paintMark(canvas, cell);
  @override
  void paintStart(Canvas canvas, Rect port, {required bool departed}) {
    departures.add(departed);
    inner.paintStart(canvas, port, departed: departed);
  }

  @override
  void paintGoal(Canvas canvas, Rect port, double arrival) {
    arrivals.add(arrival);
    inner.paintGoal(canvas, port, arrival);
  }

  @override
  void paintJourney(
    Canvas canvas,
    BoardLayout layout,
    TrackGeometry route,
    double t,
  ) {
    journeys++;
    inner.paintJourney(canvas, layout, route, t);
  }
}

/// A 7x7 session with the solution laid, optionally without its last
/// connection (the one into the goal port).
TracksSession _session({required bool complete}) {
  final puzzle = puzzleFor('tracks:7x7:medium:0');
  final session = startSession(puzzle);
  final positions = solutionStroke(puzzle);
  stroke(
    session,
    complete ? positions : positions.sublist(0, positions.length - 1),
  );
  return session;
}

void _paintOnce(TracksBoardPainter painter) =>
    painter.paint(Canvas(PictureRecorder()), const Size(400, 400));

void main() {
  test('the fixture is one connection short, and then solved', () {
    expect(_session(complete: false).isSolved, isFalse);
    expect(_session(complete: true).isSolved, isTrue);
  });

  for (final theme in TracksTheme.values) {
    for (final brightness in Brightness.values) {
      testWidgets('${theme.name} ${brightness.name}: a played board paints', (
        tester,
      ) async {
        final puzzle = puzzleFor('tracks:7x7:medium:0');
        final session = startSession(puzzle);
        final path = solutionPath(puzzle);
        final spec = puzzle.id.spec;
        // Some laid track, a mark on a cell the solution leaves empty, and a
        // wrong piece laid beside the start.
        final positions = solutionStroke(puzzle);
        stroke(session, positions.sublist(0, 5));
        final empty = [
          for (var i = 0; i < spec.cells; i++)
            if (session.maskAt(i) == 0 && !path.contains(i)) i,
        ];
        session.toggleMark(empty.first);
        final wrongStart = (positions[2].$1, positions[2].$2);
        for (final (dr, dc) in [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final r = wrongStart.$1 + dr;
          final c = wrongStart.$2 + dc;
          if (r < 0 || c < 0 || r >= spec.side || c >= spec.side) continue;
          if (session.maskAt(spec.indexAt(r, c)) != 0) continue;
          stroke(session, [(r, c), (r + dr, c + dc)]);
          break;
        }

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox.square(
                dimension: 400,
                child: CustomPaint(
                  painter: TracksBoardPainter(
                    session: session,
                    skin: trackSkinFor(theme, brightness),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  test('an unsolved board shows a waiting goal and no journey', () {
    final skin = _RecordingSkin(WaterSkin(Brightness.light));
    _paintOnce(
      TracksBoardPainter(
        session: _session(complete: false),
        skin: skin,
        frame: JourneyFrame.arrived,
      ),
    );
    expect(skin.arrivals, [0]);
    expect(skin.journeys, 0);
    expect(skin.departures, [false]);
  });

  test('a solved board shows the frame it is given', () {
    final skin = _RecordingSkin(WaterSkin(Brightness.light));
    _paintOnce(
      TracksBoardPainter(
        session: _session(complete: true),
        skin: skin,
        frame: JourneyFrame.arrived,
      ),
    );
    expect(skin.arrivals, [1]);
    expect(skin.journeys, 1);
    expect(skin.departures, [true]);
  });

  test('effectiveFrame passes a frame only while solved', () {
    const frame = JourneyFrame(0.5, 0);
    expect(
      TracksBoardPainter.effectiveFrame(_session(complete: false), frame),
      JourneyFrame.waiting,
    );
    expect(
      TracksBoardPainter.effectiveFrame(_session(complete: true), frame),
      frame,
    );
  });

  test('water: wilted flower unsolved, lush flower solved and arrived', () {
    final unsolved = _RecordingSkin(WaterSkin(Brightness.light));
    _paintOnce(
      TracksBoardPainter(
        session: _session(complete: false),
        skin: unsolved,
        frame: JourneyFrame.arrived,
      ),
    );
    expect(
      identical(
        WaterSkin.goalSpriteFor(unsolved.arrivals.single),
        WaterSkin.wiltedFlower,
      ),
      isTrue,
    );

    final solved = _RecordingSkin(WaterSkin(Brightness.light));
    _paintOnce(
      TracksBoardPainter(
        session: _session(complete: true),
        skin: solved,
        frame: JourneyFrame.arrived,
      ),
    );
    expect(
      identical(
        WaterSkin.goalSpriteFor(solved.arrivals.single),
        WaterSkin.lushFlower,
      ),
      isTrue,
    );
  });

  test('shouldRepaint follows the skin and the frame', () {
    final session = _session(complete: false);
    final skin = WaterSkin(Brightness.light);
    final base = TracksBoardPainter(session: session, skin: skin);
    expect(
      base.shouldRepaint(TracksBoardPainter(session: session, skin: skin)),
      isFalse,
    );
    expect(
      base.shouldRepaint(
        TracksBoardPainter(session: session, skin: WaterSkin(Brightness.dark)),
      ),
      isTrue,
    );
    expect(
      base.shouldRepaint(
        TracksBoardPainter(
          session: session,
          skin: skin,
          frame: JourneyFrame.arrived,
        ),
      ),
      isTrue,
    );
  });
}
