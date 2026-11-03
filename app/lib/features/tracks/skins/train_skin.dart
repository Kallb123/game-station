// The train skin: a locomotive runs along rails to a station whose lamp lights
// (`PLAN-phase-9-tracks.md` §4.8, §6 PR 6).
//
// Rails and sleepers are Canvas paths rather than sprites so a corner is a true
// quarter circle at any cell size and the pieces join without seams. The two
// figures, the locomotive and the station, are 16 x 16 sprites: they are the
// parts a child looks at, and pixel art keeps them legible at small sizes.

import 'dart:math' as math;
import 'dart:ui';

import 'package:puzzle_engine/puzzle_engine.dart' show TrackSide;

import '../../../core/storage/save_data.dart' show TracksTheme;
import 'piece_path.dart';
import 'pixel_sprite.dart';
import 'track_geometry.dart';
import 'track_skin.dart';

/// The train theme, built for one [brightness].
class TrainSkin implements TrackSkin {
  const TrainSkin(this.brightness);

  /// The locomotive, facing east. `paintJourney` flips it to go west.
  static const PixelSprite locomotive = PixelSprite(
    rows: [
      '................',
      '...........ss...',
      '..........ss....',
      '..kkkkkk.kkk....',
      '..kRRRRk.kgk....',
      '..kRwwRkkkgkkk..',
      '..kRwwRkrryrrrk.',
      '..kRRRRkrryrrrky',
      '..kRRRRkrryrrrk.',
      '..kRRRRkkkkkkkk.',
      '.kkggggggggggkk.',
      '..kkkk.kkkk.kkk.',
      '..khhk.khhk.khk.',
      '..kkkk.kkkk.kkk.',
      '................',
      '................',
    ],
    day: {
      'k': Color(0xFF1F2430),
      'R': Color(0xFF8E2B2B),
      'r': Color(0xFFD64545),
      'w': Color(0xFFBFE3F2),
      'g': Color(0xFF6B7280),
      'y': Color(0xFFF2C14E),
      'h': Color(0xFFC9CED6),
      's': Color(0xFFE5E7EB),
    },
    night: {
      'k': Color(0xFF4A5068),
      'R': Color(0xFF9E3434),
      'r': Color(0xFFE05555),
      'w': Color(0xFFBFE3F2),
      'g': Color(0xFF8A92A3),
      'y': Color(0xFFF2C14E),
      'h': Color(0xFFC9CED6),
      's': Color(0xFFAAB2C0),
    },
  );

  static const List<String> _stationRows = [
    '................',
    '...rrrrrr...kkk.',
    '..rrrrrrrr..LLL.',
    '.rrrrrrrrrr.LLL.',
    'kkkkkkkkkkkk.p..',
    '.ccnnnnnncc..p..',
    '.cwwccccwwc..p..',
    '.cwwccccwwc..p..',
    '.cccccccccc..p..',
    '.cccddddccc..p..',
    '.cccddddccc..p..',
    '.cccddddccc..p..',
    '.cccddddccc..p..',
    '.cccddddccc..p..',
    'gggggggggggggggg',
    '................',
  ];

  // The lit station differs only where the lamp's glow spills past the lamp,
  // so the change reads as light rather than as a different building.
  static const List<String> _litStationRows = [
    '................',
    '...rrrrrr...kkk.',
    '..rrrrrrrr.oLLLo',
    '.rrrrrrrrrroLLLo',
    'kkkkkkkkkkkkopo.',
    '.ccnnnnnncc..p..',
    '.cwwccccwwc..p..',
    '.cwwccccwwc..p..',
    '.cccccccccc..p..',
    '.cccddddccc..p..',
    '.cccddddccc..p..',
    '.cccddddccc..p..',
    '.cccddddccc..p..',
    '.cccddddccc..p..',
    'gggggggggggggggg',
    '................',
  ];

  static const Map<String, Color> _stationDay = {
    'k': Color(0xFF3A2A22),
    'r': Color(0xFFC0392B),
    'c': Color(0xFFF3E3C3),
    'w': Color(0xFF9CCBE8),
    'n': Color(0xFF2F5D8A),
    'd': Color(0xFF7A4A2A),
    'g': Color(0xFF9AA0A8),
    'p': Color(0xFF444B55),
  };

  static const Map<String, Color> _stationNight = {
    'k': Color(0xFF6A5448),
    'r': Color(0xFFC0392B),
    'c': Color(0xFFD9C8A4),
    'w': Color(0xFF7FAFCB),
    'n': Color(0xFF3C75AB),
    'd': Color(0xFF8A5A38),
    'g': Color(0xFF7D838C),
    'p': Color(0xFF8A93A3),
  };

  /// The station with its lamp off.
  static const PixelSprite stationUnlit = PixelSprite(
    rows: _stationRows,
    day: {..._stationDay, 'L': Color(0xFF8A8F98)},
    night: {..._stationNight, 'L': Color(0xFF8A8F98)},
  );

  /// The station with its lamp on.
  static const PixelSprite stationLit = PixelSprite(
    rows: _litStationRows,
    day: {..._stationDay, 'L': Color(0xFFFFE066), 'o': Color(0x99FFE680)},
    night: {..._stationNight, 'L': Color(0xFFFFE066), 'o': Color(0x99FFE680)},
  );

  /// Every sprite this skin draws, for the sprite-table test.
  static const List<PixelSprite> sprites = [
    locomotive,
    stationUnlit,
    stationLit,
  ];

  static const SkinColours _day = SkinColours(
    margin: Color(0xFFE6F0D4),
    ground: Color(0xFF7CB55A),
    gridLine: Color(0xFF5E9A44),
    track: Color(0xFF6B7280),
    fixedTrack: Color(0xFF262A33),
    wrong: Color(0xFFD32F2F),
    mark: Color(0xFFF5F0DC),
    clue: Color(0xFF2B3A20),
  );

  static const SkinColours _night = SkinColours(
    margin: Color(0xFF111A15),
    ground: Color(0xFF2E5530),
    gridLine: Color(0xFF223F26),
    track: Color(0xFFB7BECB),
    fixedTrack: Color(0xFFE4E8EF),
    wrong: Color(0xFFFF6B6B),
    mark: Color(0xFFD8D2B8),
    clue: Color(0xFFE6EEDC),
  );

  static const Color _sleeperDay = Color(0xFF8B5A2B);
  static const Color _sleeperNight = Color(0xFFA9774A);
  static const Color _fixedSleeperDay = Color(0xFF4A2F18);
  static const Color _fixedSleeperNight = Color(0xFFD2A874);

  @override
  final Brightness brightness;

  bool get _dark => brightness == Brightness.dark;

  @override
  TracksTheme get theme => TracksTheme.train;

  @override
  String get name => 'Train';

  @override
  String get travellerLabel => 'the train';

  @override
  String get goalLabel => 'the station';

  @override
  SkinColours get colours => _dark ? _night : _day;

  @override
  double get cellsPerSecond => 3;

  @override
  Duration get arrivalDuration => const Duration(milliseconds: 600);

  @override
  void paintGround(Canvas canvas, Rect cell, int row, int column) {
    final shade = cellNoise(row, column, 1);
    final base = shade > 0.5
        ? Color.lerp(
            colours.ground,
            const Color(0xFFFFFFFF),
            (shade - 0.5) * 0.2,
          )
        : Color.lerp(
            colours.ground,
            const Color(0xFF000000),
            (0.5 - shade) * 0.2,
          );
    canvas.drawRect(cell, Paint()..color = base!);

    final tuft = Paint()
      ..color = Color.lerp(colours.ground, const Color(0xFF000000), 0.3)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, cell.width * 0.025)
      ..strokeCap = StrokeCap.round;
    final u = cell.width;
    for (var i = 0; i < 2; i++) {
      final x =
          cell.left + (0.18 + 0.64 * cellNoise(row, column, 2 + i * 2)) * u;
      final y = cell.top + (0.3 + 0.6 * cellNoise(row, column, 3 + i * 2)) * u;
      canvas.drawLine(Offset(x, y), Offset(x - u * 0.035, y - u * 0.09), tuft);
      canvas.drawLine(Offset(x, y), Offset(x, y - u * 0.12), tuft);
      canvas.drawLine(Offset(x, y), Offset(x + u * 0.035, y - u * 0.09), tuft);
    }
  }

  @override
  void paintPiece(Canvas canvas, Rect cell, int mask, PieceStyle style) {
    final sides = sidesOf(mask);
    if (sides.isEmpty) return;
    canvas.save();
    canvas.clipRect(cell);
    if (sides.length == 1) {
      // A dangling end stops short of the edge at a buffer stop, so it reads as
      // "not joined yet" rather than as track running on into the next cell.
      final path = centreline(cell, mask, stubReach: 0.8);
      _drawTrack(canvas, cell, path, style, sleepers: 2);
      _drawBufferStop(canvas, cell, sides[0]);
    } else {
      _drawTrack(canvas, cell, centreline(cell, mask), style, sleepers: 3);
    }
    canvas.restore();
  }

  void _drawTrack(
    Canvas canvas,
    Rect cell,
    Path centre,
    PieceStyle style, {
    required int sleepers,
  }) {
    final u = cell.width;
    final fixed = style == PieceStyle.fixed;
    final wrong = style == PieceStyle.wrong;
    final railColour = wrong
        ? colours.wrong
        : (fixed ? colours.fixedTrack : colours.track);
    final sleeperColour = wrong
        ? colours.wrong
        : (fixed
              ? (_dark ? _fixedSleeperNight : _fixedSleeperDay)
              : (_dark ? _sleeperNight : _sleeperDay));
    final gauge = u * (fixed ? 0.17 : 0.14);

    final sleeper = Paint()
      ..color = sleeperColour
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * (fixed ? 0.13 : 0.07)
      ..strokeCap = wrong ? StrokeCap.round : StrokeCap.butt;
    // A wrong piece's sleepers lean over, like a track knocked out of true.
    const lean = 0.5;
    for (final s in samplesAlong(centre, sleepers)) {
      var t = s.tangent;
      if (wrong) {
        t = Offset(
          t.dx * math.cos(lean) - t.dy * math.sin(lean),
          t.dx * math.sin(lean) + t.dy * math.cos(lean),
        );
      }
      final across = Offset(-t.dy, t.dx) * (u * (fixed ? 0.27 : 0.24));
      canvas.drawLine(s.point - across, s.point + across, sleeper);
    }

    final rail = Paint()
      ..color = railColour
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * (fixed ? 0.08 : 0.05);
    for (final side in const [-1.0, 1.0]) {
      final line = offsetPath(centre, side * gauge);
      canvas.drawPath(wrong ? dashed(line, u * 0.14, u * 0.07) : line, rail);
    }
  }

  void _drawBufferStop(Canvas canvas, Rect cell, int side) {
    final u = cell.width;
    final end = Offset.lerp(cell.center, sideMidpoint(cell, side), 0.8)!;
    final along = end - cell.center;
    final unit = along / along.distance;
    final across = Offset(-unit.dy, unit.dx) * (u * 0.22);
    canvas.drawLine(
      end - across,
      end + across,
      Paint()
        ..color = colours.fixedTrack
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.09
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  void paintMark(Canvas canvas, Rect cell) {
    final inset = cell.width * 0.3;
    final box = cell.deflate(inset);
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
    canvas.save();
    canvas.clipRect(port);
    // Rail from the middle of the port to the grid, which stays behind when the
    // train goes.
    _drawTrack(
      canvas,
      port,
      centreline(port, TrackSide.east),
      PieceStyle.laid,
      sleepers: 2,
    );
    if (!departed) {
      locomotive.paint(canvas, port.deflate(port.width * 0.05), brightness);
    }
    canvas.restore();
  }

  @override
  void paintGoal(Canvas canvas, Rect port, double arrival) {
    canvas.save();
    canvas.clipRect(port);
    // The rail ends under the station's platform; the station is drawn a little
    // smaller and lower so the rail can be seen arriving.
    final top = Offset(port.center.dx, port.top);
    final stub = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(top.dx, port.top + port.height * 0.22);
    _drawTrack(canvas, port, stub, PieceStyle.laid, sleepers: 1);
    final size = port.width * 0.84;
    final rect = Rect.fromLTWH(
      port.left + (port.width - size) / 2,
      port.bottom - size,
      size,
      size,
    );
    (arrival < 0.5 ? stationUnlit : stationLit).paint(canvas, rect, brightness);
    canvas.restore();
  }

  @override
  void paintJourney(
    Canvas canvas,
    BoardLayout layout,
    TrackGeometry route,
    double t,
  ) {
    // The locomotive stops half a cell short of the goal port's centre and a
    // little more: arriving on top of the station would hide the lamp that is
    // about to light.
    final stop = math.max(0.0, (route.length - 0.9) / route.length);
    final at = t.clamp(0.0, 1.0) * stop;
    final centre = layout.toCanvas(route.pointAt(at));
    final size = layout.cellSize * 0.9;
    canvas.save();
    canvas.clipRect(layout.board);
    locomotive.paint(
      canvas,
      Rect.fromCenter(center: centre, width: size, height: size),
      brightness,
      flipX: route.directionAt(at).dx < 0,
    );
    canvas.restore();
  }
}
