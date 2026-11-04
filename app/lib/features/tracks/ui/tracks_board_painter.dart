// Paints one Tracks board: the static half of the play screen
// (`PLAN-phase-9-tracks.md` §4.8, §4.12). Input, the toolbar, the ticker that
// supplies a [JourneyFrame] and the semantics tree belong to PR 7.
//
// **The painter, not the ticker, decides whether the goal may have arrived.**
// [effectiveFrame] turns every frame into [JourneyFrame.waiting] while the
// session is unsolved, so a stale ticker, a restored animation or a test that
// passes `JourneyFrame.arrived` to a board one connection short of solved still
// shows a waiting goal. That is the water skin's wilted flower staying wilted
// until the rules say otherwise (§6, PR 6).
//
// The skin only ever paints what it is told. Everything a rule decides (fixed,
// wrong, met, exceeded) is decided here from the session and handed down as a
// style or a colour.

import 'package:flutter/rendering.dart';

import '../model/tracks_session.dart';
import '../skins/journey.dart';
import '../skins/track_geometry.dart';
import '../skins/track_skin.dart';

/// Paints [session] with [skin], at animation position [frame].
class TracksBoardPainter extends CustomPainter {
  TracksBoardPainter({
    required this.session,
    required this.skin,
    this.frame = JourneyFrame.waiting,
    this.clueFontFamily,
  }) : super(repaint: session);

  final TracksSession session;
  final TrackSkin skin;
  final JourneyFrame frame;

  /// The font for clue numbers; null takes the platform default. PR 7 passes
  /// the app's, and a screenshot test passes one it has loaded, since the test
  /// engine's default font draws every glyph as a box.
  final String? clueFontFamily;

  /// What [frame] means for [session]: the frame itself on a solved board,
  /// [JourneyFrame.waiting] otherwise.
  static JourneyFrame effectiveFrame(
    TracksSession session,
    JourneyFrame frame,
  ) => session.isSolved ? frame : JourneyFrame.waiting;

  @override
  void paint(Canvas canvas, Size size) {
    final spec = session.spec;
    final side = spec.side;
    final layout = BoardLayout.fit(size, side);
    // `fit` floors to nothing on a tiny box, and skins divide by the cell.
    if (layout.cellSize <= 0) return;
    final colours = skin.colours;
    final shown = effectiveFrame(session, frame);
    final solved = session.isSolved;

    canvas.drawRect(layout.board, Paint()..color = colours.margin);

    for (var row = 0; row < side; row++) {
      for (var column = 0; column < side; column++) {
        skin.paintGround(canvas, layout.rectAt(row, column), row, column);
      }
    }

    _paintGridLines(canvas, layout, colours.gridLine);

    for (var row = 0; row < side; row++) {
      for (var column = 0; column < side; column++) {
        final cell = spec.indexAt(row, column);
        final rect = layout.rectAt(row, column);
        final mask = session.maskAt(cell);
        if (mask == 0) {
          if (session.isMarked(cell)) skin.paintMark(canvas, rect);
          continue;
        }
        final style = session.isFixed(cell)
            ? PieceStyle.fixed
            : session.flaggedSides(cell) != 0
            ? PieceStyle.wrong
            : PieceStyle.laid;
        // The port bits (west on the start cell, south on the goal cell) are
        // drawn as pieces like any other side: they run to the cell edge, where
        // the port's own art takes over.
        skin.paintPiece(canvas, rect, mask, style);
      }
    }

    _paintClues(canvas, layout);

    // A solved board's traveller is the journey's to draw, even at t = 0, so
    // the start port keeps only its stub whenever the journey runs.
    skin.paintStart(
      canvas,
      layout.rectAt(session.clues.startRow, -1),
      departed: solved,
    );
    skin.paintGoal(
      canvas,
      layout.rectAt(side, session.clues.goalColumn),
      shown.arrival,
    );

    if (solved) {
      final route = TrackGeometry.trace(session.clues, session.cells);
      if (route != null) skin.paintJourney(canvas, layout, route, shown.t);
    }
  }

  void _paintGridLines(Canvas canvas, BoardLayout layout, Color colour) {
    final paint = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = (layout.cellSize / 40).clamp(1.0, 2.0);
    final grid = layout.grid;
    for (var i = 0; i <= layout.side; i++) {
      final offset = i * layout.cellSize;
      canvas.drawLine(
        Offset(grid.left + offset, grid.top),
        Offset(grid.left + offset, grid.bottom),
        paint,
      );
      canvas.drawLine(
        Offset(grid.left, grid.top + offset),
        Offset(grid.right, grid.top + offset),
        paint,
      );
    }
  }

  void _paintClues(Canvas canvas, BoardLayout layout) {
    final clues = session.clues;
    final side = layout.side;
    for (var column = 0; column < side; column++) {
      _paintClue(
        canvas,
        layout.rectAt(-1, column),
        clues.columnCounts[column],
        session.placedInColumn(column),
      );
    }
    for (var row = 0; row < side; row++) {
      _paintClue(
        canvas,
        layout.rectAt(row, side),
        clues.rowCounts[row],
        session.placedInRow(row),
      );
    }
  }

  /// The number stays in every state; a met clue gains a tick beneath it and an
  /// exceeded one an underline, so colour never carries the state alone.
  void _paintClue(Canvas canvas, Rect cell, int clue, int placed) {
    final colours = skin.colours;
    final met = placed == clue;
    final exceeded = placed > clue;
    final colour = exceeded ? colours.wrong : colours.clue;

    final text = TextPainter(
      text: TextSpan(
        text: '$clue',
        style: TextStyle(
          color: colour,
          fontFamily: clueFontFamily,
          fontSize: cell.height * 0.5,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final top = cell.top + cell.height * 0.14;
    text
      ..paint(canvas, Offset(cell.center.dx - text.width / 2, top))
      ..dispose();

    final mark = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = (cell.width * 0.07).clamp(1.5, 4.0);
    final y = cell.top + cell.height * 0.84;
    if (met) {
      final c = Offset(cell.center.dx, y);
      final r = cell.width * 0.12;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - r, c.dy)
          ..lineTo(c.dx - r * 0.3, c.dy + r * 0.7)
          ..lineTo(c.dx + r, c.dy - r * 0.8),
        mark,
      );
    } else if (exceeded) {
      canvas.drawLine(
        Offset(cell.center.dx - cell.width * 0.14, y),
        Offset(cell.center.dx + cell.width * 0.14, y),
        mark,
      );
    }
  }

  @override
  bool shouldRepaint(TracksBoardPainter oldDelegate) =>
      oldDelegate.skin != skin ||
      oldDelegate.frame != frame ||
      oldDelegate.clueFontFamily != clueFontFamily ||
      oldDelegate.session != session;
}
