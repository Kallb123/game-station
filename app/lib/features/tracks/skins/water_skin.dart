// The water skin: water runs from a tap through pipes to a wilted flower that
// comes up lush (`PLAN-phase-9-tracks.md` §4.8, §6 PR 6).
//
// No figure travels, so the journey is the water itself filling the pipes
// behind a moving front, and the goal is three sprites stepped through by
// `arrival`: wilted, lifting, lush.

import 'dart:math' as math;
import 'dart:ui';

import 'package:puzzle_engine/puzzle_engine.dart' show TrackSide;

import '../../../core/audio/motif.dart';
import '../../../core/storage/save_data.dart' show TracksTheme;
import 'piece_path.dart';
import 'pixel_sprite.dart';
import 'track_geometry.dart';
import 'track_skin.dart';

/// The water theme, built for one [brightness].
class WaterSkin implements TrackSkin {
  const WaterSkin(this.brightness);

  /// A tap whose spout points east, where the pipe starts.
  static const PixelSprite tap = PixelSprite(
    rows: [
      '....kkkkkkkk....',
      '....hhhhhhhh....',
      '......kffk......',
      '......kffk......',
      '....kkkffkkk....',
      '....kffffffk..kk',
      'kkkkkkkkkkkkkkFF',
      'kjjjjjjjjjjfffFk',
      'kfffffffffffffFk',
      'kkkkkkkkkkkkkkFF',
      '..............kk',
      '..............b.',
      '..............b.',
      '................',
      '................',
      '................',
    ],
    day: {
      'k': Color(0xFF4A3A10),
      'f': Color(0xFFC9A227),
      'j': Color(0xFFF3DE7A),
      'F': Color(0xFF9C7A12),
      'h': Color(0xFFD64545),
      'b': Color(0xFF4FA3E0),
    },
    night: {
      'k': Color(0xFF9A8750),
      'f': Color(0xFFC9A227),
      'j': Color(0xFFF3DE7A),
      'F': Color(0xFF9C7A12),
      'h': Color(0xFFE05555),
      'b': Color(0xFF6DC0F5),
    },
  );

  // The pot and soil are the same in all three flower sprites, so only the
  // plant above row 9 changes between them.
  static const List<String> _pot = [
    '....dddddddd....',
    '...kttttttttk...',
    '...kkkkkkkkkk...',
    '....kTTTTTUk....',
    '....kTTTTTUk....',
    '.....kTTTUk.....',
    '.....kkkkkk.....',
  ];

  static const Map<String, Color> _potDay = {
    'k': Color(0xFF5A2A18),
    'd': Color(0xFF4A3322),
    't': Color(0xFFD9814E),
    'T': Color(0xFFC1633C),
    'U': Color(0xFFA24E2C),
  };

  static const Map<String, Color> _potNight = {
    'k': Color(0xFFA0603E),
    'd': Color(0xFF5A4030),
    't': Color(0xFFD9814E),
    'T': Color(0xFFC1633C),
    'U': Color(0xFFA24E2C),
  };

  /// The flower before the water arrives: stem bent over, head hanging, dull
  /// brown and tan.
  static const PixelSprite wiltedFlower = PixelSprite(
    rows: [
      '................',
      '................',
      '................',
      '................',
      '.......ggggg....',
      '.......gg.gg....',
      '.......ggpppp...',
      '....lllggpyyp...',
      '...lll.gg.pp....',
      ..._pot,
    ],
    day: {
      ..._potDay,
      'p': Color(0xFFC9A58A),
      'y': Color(0xFF6B4A2E),
      'g': Color(0xFF7A6A2C),
      'l': Color(0xFFA8962E),
    },
    night: {
      ..._potNight,
      'p': Color(0xFFC9A58A),
      'y': Color(0xFF8A6440),
      'g': Color(0xFF9A8A3C),
      'l': Color(0xFFB8A63E),
    },
  );

  /// Part way: the stem straightening and the head a small half-open bloom.
  static const PixelSprite liftingFlower = PixelSprite(
    rows: [
      '................',
      '................',
      '......pppp......',
      '.....pppppp.....',
      '.....ppyypp.....',
      '.....pppppp.....',
      '......pppp......',
      '...ll..gg..ll...',
      '..lllllgglllll..',
      ..._pot,
    ],
    day: {
      ..._potDay,
      'p': Color(0xFFE88FB0),
      'y': Color(0xFFE8C24A),
      'g': Color(0xFF4F9A3A),
      'l': Color(0xFF7CB342),
    },
    night: {
      ..._potNight,
      'p': Color(0xFFE88FB0),
      'y': Color(0xFFE8C24A),
      'g': Color(0xFF5CAA48),
      'l': Color(0xFF8CC352),
    },
  );

  /// Arrived: upright, open, bright, with leaves lifted.
  static const PixelSprite lushFlower = PixelSprite(
    rows: [
      '......pppp......',
      '....pppppppp....',
      '...pppyyyyppp...',
      '...pppyyyyppp...',
      '....pppppppp....',
      '......pppp......',
      '.......gg.......',
      '...llllggllll...',
      '.....llggll.....',
      ..._pot,
    ],
    day: {
      ..._potDay,
      'p': Color(0xFFFF6FA5),
      'y': Color(0xFFFFD84D),
      'g': Color(0xFF2E8B3E),
      'l': Color(0xFF4CC15A),
    },
    night: {
      ..._potNight,
      'p': Color(0xFFFF6FA5),
      'y': Color(0xFFFFD84D),
      'g': Color(0xFF3FA552),
      'l': Color(0xFF5CD16A),
    },
  );

  /// Every sprite this skin draws, for the sprite-table test.
  static const List<PixelSprite> sprites = [
    tap,
    wiltedFlower,
    liftingFlower,
    lushFlower,
  ];

  /// The flower for [arrival], stepped in thirds so the change reads as the
  /// plant lifting rather than as a cross-fade.
  static PixelSprite goalSpriteFor(double arrival) {
    if (arrival < 1 / 3) return wiltedFlower;
    if (arrival < 2 / 3) return liftingFlower;
    return lushFlower;
  }

  static const SkinColours _day = SkinColours(
    margin: Color(0xFFEFE4D2),
    ground: Color(0xFFD9B99B),
    gridLine: Color(0xFFB8977A),
    track: Color(0xFF4F7CAC),
    fixedTrack: Color(0xFF24435F),
    wrong: Color(0xFFD32F2F),
    mark: Color(0xFF8B5E3C),
    clue: Color(0xFF3B2A1E),
  );

  static const SkinColours _night = SkinColours(
    margin: Color(0xFF121A24),
    ground: Color(0xFF4A3A34),
    gridLine: Color(0xFF332722),
    track: Color(0xFF6E9CC9),
    fixedTrack: Color(0xFFA9C9E8),
    wrong: Color(0xFFFF7070),
    mark: Color(0xFFD7C2A8),
    clue: Color(0xFFEADFD0),
  );

  static const Color _waterDay = Color(0xFF29B6F6);
  static const Color _waterNight = Color(0xFF7FD6FF);

  @override
  final Brightness brightness;

  bool get _dark => brightness == Brightness.dark;

  @override
  TracksTheme get theme => TracksTheme.water;

  @override
  String get name => 'Water';

  @override
  String get travellerLabel => 'the water';

  @override
  String get goalLabel => 'the flower';

  @override
  SkinColours get colours => _dark ? _night : _day;

  @override
  double get cellsPerSecond => 4;

  @override
  Duration get arrivalDuration => const Duration(milliseconds: 900);

  @override
  Motif? get arrivalMotif => Motif.tracksGurgle;

  @override
  void paintGround(Canvas canvas, Rect cell, int row, int column) {
    final shade = cellNoise(row, column, 1);
    final base = shade > 0.5
        ? Color.lerp(
            colours.ground,
            const Color(0xFFFFFFFF),
            (shade - 0.5) * 0.16,
          )
        : Color.lerp(
            colours.ground,
            const Color(0xFF000000),
            (0.5 - shade) * 0.16,
          );
    canvas.drawRect(cell, Paint()..color = base!);

    // Two courses of bricks per cell, the vertical joints staggered by row so
    // the wall does not read as a grid on top of the grid.
    final mortar = Paint()
      ..color = colours.gridLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, cell.width * 0.03);
    final h = cell.height;
    for (var course = 1; course < 3; course++) {
      final y = cell.top + h * course / 3;
      canvas.drawLine(Offset(cell.left, y), Offset(cell.right, y), mortar);
    }
    for (var course = 0; course < 3; course++) {
      final stagger = (row + course).isEven ? 0.5 : 0.25;
      final x = cell.left + cell.width * stagger;
      final top = cell.top + h * course / 3;
      canvas.drawLine(Offset(x, top), Offset(x, top + h / 3), mortar);
    }
  }

  @override
  void paintPiece(Canvas canvas, Rect cell, int mask, PieceStyle style) {
    final sides = sidesOf(mask);
    if (sides.isEmpty) return;
    final u = cell.width;
    final fixed = style == PieceStyle.fixed;
    final wrong = style == PieceStyle.wrong;
    final stub = sides.length == 1;

    final fill = wrong
        ? colours.wrong
        : (fixed ? colours.fixedTrack : colours.track);
    final outline = Color.lerp(fill, const Color(0xFF000000), 0.45)!;
    final shine = Color.lerp(fill, const Color(0xFFFFFFFF), 0.5)!;
    final outerWidth = u * (fixed ? 0.42 : 0.34);
    final bodyWidth = u * (fixed ? 0.32 : 0.26);

    canvas.save();
    canvas.clipRect(cell);
    var path = centreline(cell, mask, stubReach: 0.8);
    // A wrong pipe is in pieces, like one that has come apart at the joints.
    if (wrong) path = dashed(path, u * 0.2, u * 0.08);

    Paint stroke(Color colour, double width) => Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = stub ? StrokeCap.round : StrokeCap.butt
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, stroke(outline, outerWidth));
    canvas.drawPath(path, stroke(fill, bodyWidth));
    canvas.drawPath(
      path.shift(Offset(-u * 0.035, -u * 0.035)),
      stroke(shine, u * 0.05),
    );

    if (stub) {
      // A capped end: a pipe that goes nowhere yet.
      _flange(canvas, cell, sides[0], 0.8, outline, fill, fixed, wide: 1.1);
    } else if (!wrong) {
      for (final side in sides) {
        _flange(canvas, cell, side, 1, outline, fill, fixed);
      }
    }
    canvas.restore();
  }

  /// A joint band across the pipe where it crosses the edge of the cell, or at
  /// [reach] of the way to it. The neighbouring cell draws the other half.
  void _flange(
    Canvas canvas,
    Rect cell,
    int side,
    double reach,
    Color outline,
    Color fill,
    bool fixed, {
    double wide = 1,
  }) {
    final u = cell.width;
    final at = Offset.lerp(cell.center, sideMidpoint(cell, side), reach)!;
    final horizontal = side == TrackSide.north || side == TrackSide.south;
    final length = u * (fixed ? 0.5 : 0.42) * wide;
    final thick = u * 0.1 * wide;
    Rect band(double length, double thick) => Rect.fromCenter(
      center: at,
      width: horizontal ? length : thick,
      height: horizontal ? thick : length,
    );
    canvas.drawRect(band(length, thick), Paint()..color = outline);
    canvas.drawRect(
      band(length - u * 0.04, thick - u * 0.04),
      Paint()..color = Color.lerp(fill, const Color(0xFFFFFFFF), 0.25)!,
    );
  }

  @override
  void paintMark(Canvas canvas, Rect cell) {
    final box = cell.deflate(cell.width * 0.3);
    final paint = Paint()
      ..color = colours.mark
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, cell.width * 0.07)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(box.topLeft, box.bottomRight, paint);
    canvas.drawLine(box.topRight, box.bottomLeft, paint);
  }

  @override
  void paintStart(Canvas canvas, Rect port, {required bool departed}) {
    // The tap stays where it is whether or not the water has left: nothing
    // travels, so there is nothing for `departed` to take away.
    canvas.save();
    canvas.clipRect(port);
    tap.paint(canvas, port, brightness);
    canvas.restore();
  }

  @override
  void paintGoal(Canvas canvas, Rect port, double arrival) {
    canvas.save();
    canvas.clipRect(port);
    goalSpriteFor(arrival).paint(canvas, port, brightness);
    canvas.restore();
  }

  @override
  void paintJourney(
    Canvas canvas,
    BoardLayout layout,
    TrackGeometry route,
    double t,
  ) {
    if (t <= 0) return;
    final u = layout.cellSize;
    final water = _dark ? _waterNight : _waterDay;
    final path = route.toPath(layout, upTo: t);
    // The ports hold the tap and the flower, which are drawn whole; the water
    // is only ever seen in the pipes of the grid.
    canvas.save();
    canvas.clipRect(layout.grid);
    canvas.drawPath(
      path,
      Paint()
        ..color = water
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.16
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x66FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.05
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }
}
