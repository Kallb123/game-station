// The snail skin: a snail slides along a silvery slime trail to a pumpkin that
// glows when it gets there (`PLAN-phase-9-tracks.md` §4.8, §6 PR 9).
//
// The trail is a Canvas path, like the train's rails and the water's pipes, so
// a corner is a true quarter circle at any size. The two figures, the snail and
// the pumpkin, are 16 x 16 sprites. The snail is the slowest traveller of the
// four skins: the geometry is shared, so it is slow only because
// `cellsPerSecond` is small.

import 'dart:math' as math;
import 'dart:ui';

import 'package:puzzle_engine/puzzle_engine.dart' show TrackSide;

import '../../../core/audio/motif.dart';
import '../../../core/storage/save_data.dart' show TracksTheme;
import 'piece_path.dart';
import 'pixel_sprite.dart';
import 'track_geometry.dart';
import 'track_skin.dart';

/// The snail theme, built for one [brightness].
class SnailSkin implements TrackSkin {
  const SnailSkin(this.brightness);

  /// The snail, facing east. `paintJourney` flips it to go west.
  static const PixelSprite snail = PixelSprite(
    rows: [
      '..........pw.pw.',
      '..........pp.pp.',
      '..........bB.bB.',
      '..kkkkk...bB.bB.',
      '.kssssskk.bB.bB.',
      'kssSSSssk.bbbbbk',
      'ksSsssSsk.bbbbbk',
      'ksSsSsSskbbbbbbk',
      'ksSssSssbbbwpbbk',
      'kssSSsssbbbbbbbk',
      '.kssssskbbbbmmbk',
      '..kkkkkbbbbbbbk.',
      '.kbbbbbbbbbbbbk.',
      'kbbbbbbbbbbbbk..',
      '.kkkkkkkkkkkk...',
      '................',
    ],
    day: {
      'k': Color(0xFF4A2F1A),
      'b': Color(0xFFEBCB92),
      's': Color(0xFF9B72DB),
      'S': Color(0xFF5E3DA8),
      'w': Color(0xFFFFFFFF),
      'p': Color(0xFF2A1A10),
      'm': Color(0xFFB5703F),
      'B': Color(0xFFCFA766),
    },
    night: {
      'k': Color(0xFFC4A57F),
      'b': Color(0xFFEBCB92),
      's': Color(0xFFA880E8),
      'S': Color(0xFF6C4AC0),
      'w': Color(0xFFFFFFFF),
      'p': Color(0xFF2A1A10),
      'm': Color(0xFFB5703F),
      'B': Color(0xFFCFA766),
    },
  );

  // The pumpkin is the same body in all three frames; only the glow around it
  // and the brightness of its skin change, so the change reads as light
  // arriving rather than as a different pumpkin.
  static const List<String> _dullRows = [
    '................',
    '................',
    '......kkkk......',
    '......kggk......',
    '.....kkggkk.....',
    '...kkOooooOkk...',
    '..kooOooooOook..',
    '..khoOooooOohk..',
    '..khoOooooOohk..',
    '..kooOooooOook..',
    '..kooOooooOook..',
    '..kooOooooOook..',
    '..kooOooooOook..',
    '...kkOooooOkk...',
    '....kkkkkkkk....',
    '................',
  ];

  // A faint ring of light: the pumpkin is stirring.
  static const List<String> _stirringRows = [
    '................',
    '.....aaaaaa.....',
    '.....akkkka.....',
    '....aakggkaa....',
    '..aaakkggkkaaa..',
    '.aakkOooooOkkaa.',
    '.akooOooooOooka.',
    '.akhoOooooOohka.',
    '.akhoOooooOohka.',
    '.akooOooooOooka.',
    '.akooOooooOooka.',
    '.akooOooooOooka.',
    '.akooOooooOooka.',
    '.aakkOooooOkkaa.',
    '..aakkkkkkkkaa..',
    '...aaaaaaaaaa...',
  ];

  // The glow spills past the pumpkin ('A' close, 'a' far) and it smiles ('m').
  static const List<String> _glowingRows = [
    '....aaaaaaaa....',
    '....aAAAAAAa....',
    '...aaAkkkkAaa...',
    '.aaaAAkggkAAaaa.',
    'aaAAAkkggkkAAAaa',
    'aAAkkOooooOkkAAa',
    'aAkooOooooOookAa',
    'aAkhoOooooOohkAa',
    'aAkhoOooooOohkAa',
    'aAkooOmoomOookAa',
    'aAkooOommoOookAa',
    'aAkooOooooOookAa',
    'aAkooOooooOookAa',
    'aAAkkOooooOkkAAa',
    'aaAAkkkkkkkkAAaa',
    '.aaAAAAAAAAAAaa.',
  ];

  /// The pumpkin before the snail arrives: plain, no glow.
  static const PixelSprite pumpkinDull = PixelSprite(
    rows: _dullRows,
    day: {
      'k': Color(0xFF5A2E0C),
      'o': Color(0xFFE8892B),
      'O': Color(0xFFC96A14),
      'h': Color(0xFFF2A857),
      'g': Color(0xFF4F8A2E),
    },
    night: {
      'k': Color(0xFFA9703C),
      'o': Color(0xFFE8892B),
      'O': Color(0xFFC96A14),
      'h': Color(0xFFF2A857),
      'g': Color(0xFF5FA03A),
    },
  );

  /// Part way: a little brighter, with a faint ring of light.
  static const PixelSprite pumpkinStirring = PixelSprite(
    rows: _stirringRows,
    day: {
      'k': Color(0xFF5A2E0C),
      'o': Color(0xFFF09A30),
      'O': Color(0xFFD27418),
      'h': Color(0xFFF8BC6A),
      'g': Color(0xFF4F8A2E),
      'a': Color(0x55FFE680),
    },
    night: {
      'k': Color(0xFFB57C46),
      'o': Color(0xFFF09A30),
      'O': Color(0xFFD27418),
      'h': Color(0xFFF8BC6A),
      'g': Color(0xFF5FA03A),
      'a': Color(0x55FFE680),
    },
  );

  /// Arrived: bright, smiling, and glowing.
  static const PixelSprite pumpkinGlowing = PixelSprite(
    rows: _glowingRows,
    day: {
      'k': Color(0xFF5A2E0C),
      'o': Color(0xFFFFA726),
      'O': Color(0xFFE5801A),
      'h': Color(0xFFFFD27A),
      'g': Color(0xFF5BA032),
      'm': Color(0xFF5A2E0C),
      'A': Color(0x99FFE680),
      'a': Color(0x44FFE680),
    },
    night: {
      'k': Color(0xFFC08850),
      'o': Color(0xFFFFA726),
      'O': Color(0xFFE5801A),
      'h': Color(0xFFFFD27A),
      'g': Color(0xFF6BB442),
      'm': Color(0xFF5A2E0C),
      'A': Color(0x99FFE680),
      'a': Color(0x44FFE680),
    },
  );

  /// Every sprite this skin draws, for the sprite-table test.
  static const List<PixelSprite> sprites = [
    snail,
    pumpkinDull,
    pumpkinStirring,
    pumpkinGlowing,
  ];

  /// The pumpkin for [arrival], stepped in thirds so the change reads as light
  /// coming on rather than as a cross-fade.
  static PixelSprite goalSpriteFor(double arrival) {
    if (arrival < 1 / 3) return pumpkinDull;
    if (arrival < 2 / 3) return pumpkinStirring;
    return pumpkinGlowing;
  }

  static const SkinColours _day = SkinColours(
    margin: Color(0xFFEBDCC4),
    ground: Color(0xFF8B6A4A),
    gridLine: Color(0xFF6E5038),
    track: Color(0xFFF4F0E6),
    fixedTrack: Color(0xFFFFFBEE),
    wrong: Color(0xFFD32F2F),
    mark: Color(0xFFEBDCC4),
    clue: Color(0xFF3A2616),
  );

  static const SkinColours _night = SkinColours(
    margin: Color(0xFF17110C),
    ground: Color(0xFF3D2E22),
    gridLine: Color(0xFF2B2018),
    track: Color(0xFFD6D0C4),
    fixedTrack: Color(0xFFF6F0E0),
    wrong: Color(0xFFFF7A7A),
    mark: Color(0xFFD8C4A8),
    clue: Color(0xFFEFE2CE),
  );

  @override
  final Brightness brightness;

  bool get _dark => brightness == Brightness.dark;

  @override
  TracksTheme get theme => TracksTheme.snail;

  @override
  String get name => 'Snail';

  @override
  String get travellerLabel => 'the snail';

  @override
  String get goalLabel => 'the pumpkin';

  @override
  SkinColours get colours => _dark ? _night : _day;

  @override
  double get cellsPerSecond => 2;

  @override
  Duration get arrivalDuration => const Duration(milliseconds: 700);

  @override
  Motif? get arrivalMotif => Motif.tracksPop;

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
            (0.5 - shade) * 0.22,
          );
    canvas.drawRect(cell, Paint()..color = base!);

    // A few specks and one pebble, placed by the cell's position so the soil
    // is the same on every frame and every run.
    final u = cell.width;
    final dark = Paint()
      ..color = Color.lerp(colours.ground, const Color(0xFF000000), 0.35)!;
    final light = Paint()
      ..color = Color.lerp(colours.ground, const Color(0xFFFFFFFF), 0.25)!;
    for (var i = 0; i < 4; i++) {
      final at = Offset(
        cell.left + (0.1 + 0.8 * cellNoise(row, column, 2 + i * 2)) * u,
        cell.top + (0.1 + 0.8 * cellNoise(row, column, 3 + i * 2)) * u,
      );
      canvas.drawCircle(at, math.max(0.8, u * 0.022), i.isEven ? dark : light);
    }
    if (cellNoise(row, column, 11) > 0.45) {
      final at = Offset(
        cell.left + (0.15 + 0.7 * cellNoise(row, column, 12)) * u,
        cell.top + (0.15 + 0.7 * cellNoise(row, column, 13)) * u,
      );
      canvas.drawOval(
        Rect.fromCenter(center: at, width: u * 0.15, height: u * 0.1),
        Paint()
          ..color = Color.lerp(colours.ground, const Color(0xFFB8AC9C), 0.6)!,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: at + Offset(-u * 0.02, -u * 0.015),
          width: u * 0.06,
          height: u * 0.04,
        ),
        light,
      );
    }
  }

  @override
  void paintPiece(Canvas canvas, Rect cell, int mask, PieceStyle style) {
    final sides = sidesOf(mask);
    if (sides.isEmpty) return;
    canvas.save();
    canvas.clipRect(cell);
    if (sides.length == 1) {
      // An unjoined end stops short of the edge in a rounded blob of slime, so
      // it reads as "not joined yet" rather than as trail running on.
      _drawTrail(
        canvas,
        cell,
        centreline(cell, mask, stubReach: 0.8),
        style,
        blob: true,
      );
    } else {
      _drawTrail(canvas, cell, centreline(cell, mask), style);
    }
    canvas.restore();
  }

  /// A filled band along [centre], [width] wide where [bulge] is 0 and
  /// `width * (1 + bulge)` at the fullest. Built as a polygon so its edges can
  /// wander; [bulge] must be 0 at both ends of the cell, so the bands of two
  /// neighbouring cells meet at the same width and the trail has no seam.
  Path _ribbon(Path centre, double width, double bulge, {double shift = 0}) {
    final metrics = centre.computeMetrics().toList();
    final band = Path();
    if (metrics.isEmpty) return band;
    final metric = metrics.first;
    const steps = 16;
    final left = <Offset>[];
    final right = <Offset>[];
    for (var i = 0; i <= steps; i++) {
      final s = i / steps;
      final tangent = metric.getTangentForOffset(metric.length * s);
      if (tangent == null) continue;
      final normal = Offset(-tangent.vector.dy, tangent.vector.dx);
      final half = width * (1 + bulge * math.sin(math.pi * s)) / 2;
      final mid = tangent.position + normal * shift;
      left.add(mid + normal * half);
      right.add(mid - normal * half);
    }
    band.moveTo(left.first.dx, left.first.dy);
    for (final point in left.skip(1)) {
      band.lineTo(point.dx, point.dy);
    }
    for (final point in right.reversed) {
      band.lineTo(point.dx, point.dy);
    }
    return band..close();
  }

  void _drawTrail(
    Canvas canvas,
    Rect cell,
    Path centre,
    PieceStyle style, {
    bool blob = false,
  }) {
    final u = cell.width;
    final fixed = style == PieceStyle.fixed;
    final wrong = style == PieceStyle.wrong;
    // Position-keyed noise, so the same cell always glistens the same way.
    final a = cell.left.round();
    final b = cell.top.round();
    double noise(int salt) => cellNoise(a, b, salt);
    final wobble = (noise(1) - 0.5) * 0.5;

    if (wrong) {
      // A smear of blobs, not a tube: the slime has gone wrong and lumpy.
      final paint = Paint()..color = colours.wrong;
      final samples = samplesAlong(centre, 5);
      for (var i = 0; i < samples.length; i++) {
        final s = samples[i];
        final across = Offset(-s.tangent.dy, s.tangent.dx);
        final off = across * ((noise(10 + i) - 0.5) * u * 0.1);
        canvas.drawCircle(
          s.point + off,
          u * (0.07 + 0.06 * noise(20 + i)),
          paint,
        );
      }
      return;
    }

    final slime = colours.track;
    final pearl = colours.fixedTrack;
    final width = u * (fixed ? 0.36 : 0.22);
    final main = fixed ? pearl.withAlpha(0xE6) : slime.withAlpha(0x90);

    if (fixed) {
      // A soft shadow of dark soil under it, not an outline.
      canvas.drawPath(
        _ribbon(centre, width * 1.4, wobble).shift(Offset(0, u * 0.03)),
        Paint()..color = const Color(0x40000000),
      );
    } else {
      // A wetter, fainter fringe, so the edge fades instead of ending.
      canvas.drawPath(
        _ribbon(centre, width * 1.3, -wobble),
        Paint()..color = slime.withAlpha(0x34),
      );
    }
    canvas.drawPath(_ribbon(centre, width, wobble), Paint()..color = main);
    // A second, thinner, slightly off-centre layer, so the thickness varies.
    canvas.drawPath(
      _ribbon(centre, width * 0.55, -wobble, shift: u * 0.03),
      Paint()..color = const Color(0xFFFFFFFF).withAlpha(fixed ? 0x80 : 0x55),
    );

    final glint = Paint()..color = const Color(0xF2FFFFFF);
    final glints = samplesAlong(centre, fixed ? 5 : 3);
    for (var i = 0; i < glints.length; i++) {
      final s = glints[i];
      if (!fixed && noise(30 + i) < 0.25) continue;
      final across = Offset(-s.tangent.dy, s.tangent.dx);
      final at = s.point + across * ((noise(40 + i) - 0.5) * width * 0.7);
      if (noise(50 + i) > 0.5) {
        canvas.drawCircle(at, math.max(0.8, u * 0.024), glint);
      } else {
        canvas.drawLine(
          at - s.tangent * (u * 0.035),
          at + s.tangent * (u * 0.035),
          Paint()
            ..color = const Color(0xF2FFFFFF)
            ..strokeWidth = math.max(1, u * 0.025)
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    if (blob) {
      final metric = centre.computeMetrics().first;
      final end = metric.getTangentForOffset(metric.length)!.position;
      final radius = width * 0.78;
      canvas.drawCircle(
        end,
        radius * 1.25,
        Paint()..color = slime.withAlpha(0x34),
      );
      canvas.drawCircle(end, radius, Paint()..color = main);
      canvas.drawCircle(
        end + Offset(-radius * 0.3, -radius * 0.3),
        radius * 0.32,
        glint,
      );
    }
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

  /// The rectangle a snail is drawn into when centred on [centre]: a little
  /// above centre, so its foot rests on the trail rather than straddling it.
  Rect _snailRect(Offset centre, double size) => Rect.fromCenter(
    center: centre - Offset(0, size * 0.08),
    width: size,
    height: size,
  );

  @override
  void paintStart(Canvas canvas, Rect port, {required bool departed}) {
    canvas.save();
    canvas.clipRect(port);
    // The trail from the port's middle to the grid stays behind when the snail
    // goes.
    _drawTrail(canvas, port, centreline(port, TrackSide.east), PieceStyle.laid);
    if (!departed) {
      snail.paint(
        canvas,
        _snailRect(port.center, port.width * 0.9),
        brightness,
      );
    }
    canvas.restore();
  }

  @override
  void paintGoal(Canvas canvas, Rect port, double arrival) {
    canvas.save();
    canvas.clipRect(port);
    // The trail ends at the pumpkin's side; the pumpkin is drawn a little
    // smaller and lower so the trail can be seen arriving.
    final top = Offset(port.center.dx, port.top);
    final stub = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(top.dx, port.top + port.height * 0.3);
    _drawTrail(canvas, port, stub, PieceStyle.laid);
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
    // The snail stops a little short of the goal port's centre: arriving on
    // top of the pumpkin would hide the glow that is about to come on.
    final stop = math.max(0.0, (route.length - 0.9) / route.length);
    final at = t.clamp(0.0, 1.0) * stop;
    final centre = layout.toCanvas(route.pointAt(at));
    canvas.save();
    canvas.clipRect(layout.board);
    snail.paint(
      canvas,
      _snailRect(centre, layout.cellSize * 0.9),
      brightness,
      flipX: route.directionAt(at).dx < 0,
    );
    canvas.restore();
  }
}
