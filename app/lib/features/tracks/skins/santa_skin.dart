// The Santa skin: Santa walks through the snow, leaving boot prints, to a house
// whose windows light and whose chimney smokes (`PLAN-phase-9-tracks.md` §4.8,
// §6 PR 9).
//
// The track is a trail of footprints along the same centre line the train's
// rails follow, so a corner curves the same way. The figures, Santa and the
// house, are 16 x 16 sprites: they are the parts a child looks at, and pixel art
// keeps them legible at small sizes. The goal is three sprites stepped through
// by `arrival`: windows dark, windows lit, and lit with smoke from the chimney.

import 'dart:math' as math;
import 'dart:ui';

import 'package:puzzle_engine/puzzle_engine.dart' show TrackSide;

import '../../../core/audio/motif.dart';
import '../../../core/storage/save_data.dart' show TracksTheme;
import 'piece_path.dart';
import 'pixel_sprite.dart';
import 'track_geometry.dart';
import 'track_skin.dart';

/// The Santa theme, built for one [brightness].
class SantaSkin implements TrackSkin {
  const SantaSkin(this.brightness);

  /// Santa, facing east. `paintJourney` flips him to go west.
  static const PixelSprite santa = PixelSprite(
    rows: [
      '.......RRR......',
      '......RRRRR.....',
      '.....RrrrRRRww..',
      '....wwwwwwwwww..',
      '....wwssssesw...',
      '....wwssssssw...',
      '....wwwwwnwww...',
      '.....wwwwwww....',
      '....RRwwwwwRR...',
      '...sRRrrrrrRRs..',
      '...sRRrrrrrRRs..',
      '....RRkkyykRR...',
      '....RRrrrrrRR...',
      '.....rrr.rrr....',
      '....kkkk.kkkk...',
      '....kkkk.kkkk...',
    ],
    day: {
      'R': Color(0xFFB71C1C),
      'r': Color(0xFFE53935),
      'w': Color(0xFFFFFFFF),
      's': Color(0xFFF4B792),
      'n': Color(0xFFE8A080),
      'e': Color(0xFF1A1A1A),
      'k': Color(0xFF1E1A1A),
      'y': Color(0xFFFFD54F),
    },
    night: {
      'R': Color(0xFFC62828),
      'r': Color(0xFFEF5350),
      'w': Color(0xFFF4F8FF),
      's': Color(0xFFF4B792),
      'n': Color(0xFFE8A080),
      'e': Color(0xFF1A1A1A),
      'k': Color(0xFF14101A),
      'y': Color(0xFFFFD54F),
    },
  );

  // The roof and the chimney are the same in all three house sprites, and so
  // are the walls apart from the windows, so each frame is the shared rows with
  // its own two rows of sky above and its own window pixels.
  static const List<String> _roof = [
    '..........wwwww.',
    '...........bbb..',
    '......wwww.bbb..',
    '.....RRRRRRbbb..',
    '....RRRRRRRbbb..',
    '...RRRRRRRRRRR..',
    '..RRRRRRRRRRRR..',
    '.wwwwwwwwwwwwww.',
  ];

  static const List<String> _wallsDark = [
    '..cccccccccccc..',
    '..cDDccccccDDc..',
    '..cDDcddddcDDc..',
    '..ccccddddcccc..',
    '..ccccddgdcccc..',
    'wwwwwwwwwwwwwwww',
  ];

  static const List<String> _wallsLit = [
    '..cccccccccccc..',
    '..cWWccccccWWc..',
    '..cWWcddddcWWc..',
    '..ccccddddcccc..',
    '..ccccddgdcccc..',
    'wwwwwwwwwwwwwwww',
  ];

  static const List<String> _clearSky = [
    '................',
    '................',
  ];

  static const List<String> _puffSky = ['...........mm...', '..........mmmm..'];

  static const Map<String, Color> _houseDay = {
    'b': Color(0xFF8D4B3A),
    'w': Color(0xFFFFFFFF),
    'R': Color(0xFFB23A3A),
    'c': Color(0xFFD9B38C),
    'd': Color(0xFF6B4226),
    'g': Color(0xFFFFD54F),
    'D': Color(0xFF2B3A55),
    'W': Color(0xFFFFE066),
    'm': Color(0xFFA9B0BC),
    'o': Color(0xFFD5DAE2),
  };

  static const Map<String, Color> _houseNight = {
    'b': Color(0xFFA85D49),
    'w': Color(0xFFE8F0FF),
    'R': Color(0xFFC24A4A),
    'c': Color(0xFFB08C68),
    'd': Color(0xFF8A5A36),
    'g': Color(0xFFFFD54F),
    'D': Color(0xFF141C2E),
    'W': Color(0xFFFFE066),
    'm': Color(0xFFC0C8D6),
    'o': Color(0xFFE6EAF0),
  };

  /// The house with its windows dark and no smoke.
  static const PixelSprite houseDark = PixelSprite(
    rows: [..._clearSky, ..._roof, ..._wallsDark],
    day: _houseDay,
    night: _houseNight,
  );

  /// The house with its windows lit.
  static const PixelSprite houseLit = PixelSprite(
    rows: [..._clearSky, ..._roof, ..._wallsLit],
    day: _houseDay,
    night: _houseNight,
  );

  /// The house lit, with a puff of smoke from the chimney.
  static const PixelSprite houseSmoke = PixelSprite(
    rows: [..._puffSky, ..._roof, ..._wallsLit],
    day: _houseDay,
    night: _houseNight,
  );

  /// Every sprite this skin draws, for the sprite-table test.
  static const List<PixelSprite> sprites = [
    santa,
    houseDark,
    houseLit,
    houseSmoke,
  ];

  /// The house for [arrival], stepped in thirds so the change reads as the
  /// lights coming on and then the fire catching, not as a cross-fade.
  static PixelSprite goalSpriteFor(double arrival) {
    if (arrival < 1 / 3) return houseDark;
    if (arrival < 2 / 3) return houseLit;
    return houseSmoke;
  }

  static const SkinColours _day = SkinColours(
    margin: Color(0xFFD5E3F0),
    ground: Color(0xFFF2F7FC),
    gridLine: Color(0xFFB4C7DA),
    track: Color(0xFF7E92A8),
    fixedTrack: Color(0xFF34455A),
    wrong: Color(0xFFD32F2F),
    mark: Color(0xFF6C86A3),
    clue: Color(0xFF1F3550),
  );

  static const SkinColours _night = SkinColours(
    margin: Color(0xFF0B1220),
    ground: Color(0xFF52668A),
    gridLine: Color(0xFF3A4C6C),
    track: Color(0xFFB4C6E0),
    fixedTrack: Color(0xFFEFF5FF),
    wrong: Color(0xFFFF7A7A),
    mark: Color(0xFFC3D2E8),
    clue: Color(0xFFEAF1FB),
  );

  @override
  final Brightness brightness;

  bool get _dark => brightness == Brightness.dark;

  @override
  TracksTheme get theme => TracksTheme.santa;

  @override
  String get name => 'Santa';

  @override
  String get travellerLabel => 'Santa';

  @override
  String get goalLabel => 'the house';

  @override
  SkinColours get colours => _dark ? _night : _day;

  // Between the snail (2) and the train (3): a walk, but a brisk one.
  @override
  double get cellsPerSecond => 2.5;

  @override
  Duration get arrivalDuration => const Duration(milliseconds: 800);

  @override
  Motif? get arrivalMotif => Motif.tracksSleighBells;

  @override
  void paintGround(Canvas canvas, Rect cell, int row, int column) {
    final shade = cellNoise(row, column, 1);
    final base = shade > 0.5
        ? Color.lerp(
            colours.ground,
            const Color(0xFFFFFFFF),
            (shade - 0.5) * 0.3,
          )
        : Color.lerp(colours.ground, colours.gridLine, (0.5 - shade) * 0.45);
    canvas.drawRect(cell, Paint()..color = base!);

    final u = cell.width;
    // A low drift: a shallow arc in a slightly deeper shade.
    final drift = Paint()
      ..color = Color.lerp(colours.ground, colours.gridLine, 0.6)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, u * 0.03)
      ..strokeCap = StrokeCap.round;
    final dx = cell.left + (0.12 + 0.4 * cellNoise(row, column, 2)) * u;
    final dy = cell.top + (0.55 + 0.35 * cellNoise(row, column, 3)) * u;
    canvas.drawPath(
      Path()
        ..moveTo(dx, dy)
        ..quadraticBezierTo(dx + u * 0.15, dy - u * 0.07, dx + u * 0.3, dy),
      drift,
    );

    // A sparkle on some cells: a small plus, brighter than the snow.
    if (cellNoise(row, column, 4) > 0.55) {
      final sparkle = Paint()
        ..color = _dark ? const Color(0xFFDDE8FA) : const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, u * 0.03)
        ..strokeCap = StrokeCap.round;
      final sx = cell.left + (0.15 + 0.7 * cellNoise(row, column, 5)) * u;
      final sy = cell.top + (0.15 + 0.4 * cellNoise(row, column, 6)) * u;
      final r = u * 0.045;
      canvas.drawLine(Offset(sx - r, sy), Offset(sx + r, sy), sparkle);
      canvas.drawLine(Offset(sx, sy - r), Offset(sx, sy + r), sparkle);
    }
  }

  @override
  void paintPiece(Canvas canvas, Rect cell, int mask, PieceStyle style) {
    final sides = sidesOf(mask);
    if (sides.isEmpty) return;
    canvas.save();
    canvas.clipRect(cell);
    if (sides.length == 1) {
      // A dangling trail stops short of the edge in a little mound, so it reads
      // as "not joined yet" rather than as prints running on into the next
      // cell.
      final path = centreline(cell, mask, stubReach: 0.8);
      _drawPrints(canvas, cell, path, style, count: 2);
      _drawMound(canvas, cell, sides[0]);
    } else {
      _drawPrints(canvas, cell, centreline(cell, mask), style, count: 4);
    }
    canvas.restore();
  }

  /// Pairs of boot prints along [centre], [count] of them, alternating left and
  /// right of the line.
  void _drawPrints(
    Canvas canvas,
    Rect cell,
    Path centre,
    PieceStyle style, {
    required int count,
  }) {
    final u = cell.width;
    final fixed = style == PieceStyle.fixed;
    final wrong = style == PieceStyle.wrong;
    final fill = Paint()
      ..color = wrong
          ? colours.wrong
          : (fixed ? colours.fixedTrack : colours.track);
    // A fixed print is bigger and has an outline in the snow's own colour, so
    // it reads as deeper without relying on its shade.
    final rim = Paint()
      ..color = colours.ground
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, u * 0.025);
    final scale = fixed ? 1.35 : 1.0;

    final samples = samplesAlong(centre, count);
    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      final side = i.isEven ? 1.0 : -1.0;
      var angle = math.atan2(s.tangent.dy, s.tangent.dx);
      var at = s.point + Offset(-s.tangent.dy, s.tangent.dx) * (side * u * 0.1);
      if (wrong) {
        // Scattered: every print askew and pushed off its line, like a trail
        // someone has stumbled along.
        angle += (i.isEven ? 0.7 : -0.7);
        at += Offset(-s.tangent.dy, s.tangent.dx) * (side * u * 0.05);
      }
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(angle);
      final sole = Rect.fromCenter(
        center: Offset(u * 0.045 * scale, 0),
        width: u * 0.13 * scale,
        height: u * 0.085 * scale,
      );
      final heel = Rect.fromCenter(
        center: Offset(-u * 0.06 * scale, 0),
        width: u * 0.065 * scale,
        height: u * 0.06 * scale,
      );
      if (fixed) {
        canvas.drawOval(sole, rim);
        canvas.drawOval(heel, rim);
      }
      canvas.drawOval(sole, fill);
      // A wrong print has no heel: half a print reads as broken without colour.
      if (!wrong) canvas.drawOval(heel, fill);
      canvas.restore();
    }
  }

  void _drawMound(Canvas canvas, Rect cell, int side) {
    final u = cell.width;
    final end = Offset.lerp(cell.center, sideMidpoint(cell, side), 0.8)!;
    final mound = Rect.fromCenter(
      center: end,
      width: u * 0.2,
      height: u * 0.15,
    );
    canvas.drawOval(
      mound.shift(Offset(0, u * 0.02)),
      Paint()..color = colours.gridLine,
    );
    canvas.drawOval(mound, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawOval(
      mound,
      Paint()
        ..color = colours.fixedTrack
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, u * 0.03),
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
    canvas.save();
    canvas.clipRect(port);
    // The prints to the grid stay behind when Santa goes.
    _drawPrints(
      canvas,
      port,
      centreline(port, TrackSide.east),
      PieceStyle.laid,
      count: 2,
    );
    if (!departed) {
      santa.paint(canvas, port.deflate(port.width * 0.05), brightness);
    }
    canvas.restore();
  }

  @override
  void paintGoal(Canvas canvas, Rect port, double arrival) {
    canvas.save();
    canvas.clipRect(port);
    // The trail ends at the door; the house is drawn a little smaller and lower
    // so the prints can be seen arriving.
    final top = Offset(port.center.dx, port.top);
    final stub = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(top.dx, port.top + port.height * 0.3);
    _drawPrints(canvas, port, stub, PieceStyle.laid, count: 1);
    final size = port.width * 0.84;
    final rect = Rect.fromLTWH(
      port.left + (port.width - size) / 2,
      port.bottom - size,
      size,
      size,
    );
    goalSpriteFor(arrival).paint(canvas, rect, brightness);
    canvas.restore();
  }

  @override
  void paintJourney(
    Canvas canvas,
    BoardLayout layout,
    TrackGeometry route,
    double t,
  ) {
    // Santa stops short of the goal port's centre: arriving on top of the house
    // would hide the windows that are about to light.
    final stop = math.max(0.0, (route.length - 0.9) / route.length);
    final at = t.clamp(0.0, 1.0) * stop;
    final u = layout.cellSize;
    // A small bounce with each step, a function of distance walked so Santa
    // stands still when the journey does.
    final bounce = -math.sin(at * route.length * math.pi * 4).abs() * u * 0.04;
    final centre = layout.toCanvas(route.pointAt(at)) + Offset(0, bounce);
    final size = u * 0.9;
    canvas.save();
    canvas.clipRect(layout.board);
    santa.paint(
      canvas,
      Rect.fromCenter(center: centre, width: size, height: size),
      brightness,
      flipX: route.directionAt(at).dx < 0,
    );
    canvas.restore();
  }
}
