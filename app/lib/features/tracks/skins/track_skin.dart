// The skin interface: everything that makes one Tracks puzzle look like a
// train, Santa, a snail or water, and nothing that could change the puzzle
// (`PLAN-phase-9-tracks.md` §3's load-bearing decision, §4.8).
//
// A skin is handed geometry and state and paints pixels. It never sees a
// `TracksSession`, a solution or a clue, so a skin cannot make a rule even by
// accident: the board painter decides what is laid, fixed, wrong or arrived,
// and the skin only decides what each of those looks like.
//
// **A skin is built for one brightness.** The sketch in §4.8 passed a
// `Brightness` to `colours` alone, which left every paint method to guess which
// palette its sprites should use. Binding the brightness at construction gives
// every method the same answer, and the painter builds a new skin when the
// theme or the brightness changes — both rare, and both a rebuild anyway.

import 'dart:ui';

import 'package:flutter/foundation.dart' show immutable;

import '../../../core/storage/save_data.dart' show TracksTheme;
import 'track_geometry.dart';

/// How a piece of track is drawn (`PLAN-phase-9-tracks.md` §4.8, §4.12).
enum PieceStyle {
  /// Laid by the child, or by a hint. Liftable.
  laid,

  /// Part of the puzzle from the start. Never liftable, so it must read as
  /// different from [laid] by more than colour: every skin draws it heavier.
  fixed,

  /// Laid, and flagged as not in the solution under the profile's mistake
  /// feedback. Drawn in [SkinColours.wrong] and also differently shaped, for
  /// the same colour-is-never-alone reason.
  wrong,
}

/// The flat colours a skin uses outside its sprites, for one brightness.
///
/// The board painter reads [margin], [gridLine] and [clue] itself; the rest are
/// the skin's own, listed here so a test can check day and night differ and a
/// reader can see a skin's palette in one place.
@immutable
class SkinColours {
  const SkinColours({
    required this.margin,
    required this.ground,
    required this.gridLine,
    required this.track,
    required this.fixedTrack,
    required this.wrong,
    required this.mark,
    required this.clue,
  });

  /// Behind the one-cell margin that holds the clues and the ports.
  final Color margin;

  /// The base colour of a grid cell, before any texture.
  final Color ground;

  /// The lines between cells.
  final Color gridLine;

  /// A laid piece.
  final Color track;

  /// A fixed piece.
  final Color fixedTrack;

  /// A wrong piece, and a clue the board has exceeded.
  final Color wrong;

  /// The "no track here" mark.
  final Color mark;

  /// A clue number, and its tick once met.
  final Color clue;
}

/// Where the board sits on the canvas, in the units a skin paints in.
///
/// The board is the grid plus a one-cell margin on every side
/// (`PLAN-phase-9-tracks.md` §4.12), so a grid of `side` cells is
/// `side + 2` cells across. [origin] is the top-left corner of grid cell
/// (0, 0), so the margin starts at `origin - (cellSize, cellSize)`.
///
/// Positions use the session's `(row, column)` addressing, ports included:
/// the start port is `(startRow, -1)` and the goal port `(side, goalColumn)`.
@immutable
class BoardLayout {
  const BoardLayout({
    required this.origin,
    required this.cellSize,
    required this.side,
  });

  /// The largest square board that fits [size], centred in it.
  factory BoardLayout.fit(Size size, int side) {
    final across = side + 2;
    final cellSize = (size.shortestSide / across).floorToDouble();
    final boardExtent = cellSize * across;
    final left = (size.width - boardExtent) / 2;
    final top = (size.height - boardExtent) / 2;
    return BoardLayout(
      origin: Offset(left + cellSize, top + cellSize),
      cellSize: cellSize,
      side: side,
    );
  }

  /// Top-left of grid cell (0, 0).
  final Offset origin;

  /// The side of one cell, in logical pixels.
  final double cellSize;

  /// Cells per side of the grid, margin excluded.
  final int side;

  /// The whole board, margin included.
  Rect get board => Rect.fromLTWH(
    origin.dx - cellSize,
    origin.dy - cellSize,
    cellSize * (side + 2),
    cellSize * (side + 2),
  );

  /// The grid alone.
  Rect get grid =>
      Rect.fromLTWH(origin.dx, origin.dy, cellSize * side, cellSize * side);

  /// The square at ([row], [column]); either may be -1 or [side] for the
  /// margin.
  Rect rectAt(int row, int column) => Rect.fromLTWH(
    origin.dx + column * cellSize,
    origin.dy + row * cellSize,
    cellSize,
    cellSize,
  );

  /// A point in grid units — x across columns, y down rows, cell (0, 0)
  /// spanning (0, 0) to (1, 1) — as a canvas point.
  Offset toCanvas(Offset gridPoint) => origin + gridPoint * cellSize;

  /// The square containing [canvasPoint], or null outside the board.
  (int row, int column)? positionAt(Offset canvasPoint) {
    final local = (canvasPoint - origin) / cellSize;
    final row = local.dy.floor();
    final column = local.dx.floor();
    if (row < -1 || row > side || column < -1 || column > side) return null;
    return (row, column);
  }

  @override
  bool operator ==(Object other) =>
      other is BoardLayout &&
      other.origin == origin &&
      other.cellSize == cellSize &&
      other.side == side;

  @override
  int get hashCode => Object.hash(origin, cellSize, side);
}

/// One theme's look (`PLAN-phase-9-tracks.md` §4.8).
///
/// Every paint method draws into the rectangle or layout it is given and
/// nowhere else, saves and restores any canvas state it changes, and treats
/// its inputs as already decided: a skin is never asked whether a board is
/// solved, only told how far the journey has got.
abstract interface class TrackSkin {
  /// Which theme this is.
  TracksTheme get theme;

  /// The brightness this skin was built for.
  Brightness get brightness;

  /// The picker's label: "Train".
  String get name;

  /// For semantics: "the train".
  String get travellerLabel;

  /// For semantics: "the station".
  String get goalLabel;

  /// The flat colours, for [brightness].
  SkinColours get colours;

  /// How fast the traveller moves, in grid units per second. The one number
  /// that differs between skins' journeys: the geometry is shared, so the
  /// snail is slower only because this is smaller.
  double get cellsPerSecond;

  /// How long the goal takes to go from waiting to arrived once the journey
  /// ends.
  Duration get arrivalDuration;

  /// One grid cell's ground, before any track. [row] and [column] let a
  /// texture vary from cell to cell without randomness.
  void paintGround(Canvas canvas, Rect cell, int row, int column);

  /// The track in one cell. [mask] holds one or two of `TrackSide`'s bits: two
  /// for a piece, one for an end the child has not joined yet (a stub from
  /// the centre to that side). Zero is never passed.
  void paintPiece(Canvas canvas, Rect cell, int mask, PieceStyle style);

  /// The "no track here" mark on an empty cell.
  void paintMark(Canvas canvas, Rect cell);

  /// The start port, west of the grid. With [departed] false the traveller
  /// waits here; with it true the journey has the traveller and this draws
  /// whatever stays behind (a tap stays, a train does not).
  void paintStart(Canvas canvas, Rect port, {required bool departed});

  /// The goal port, south of the grid. [arrival] is 0 while waiting and 1 once
  /// arrived; between, the goal is changing (§4.8).
  void paintGoal(Canvas canvas, Rect port, double arrival);

  /// The journey along [route] at [t], 0 at the start port and 1 at the goal
  /// port. Called only on a solved board.
  void paintJourney(
    Canvas canvas,
    BoardLayout layout,
    TrackGeometry route,
    double t,
  );
}
