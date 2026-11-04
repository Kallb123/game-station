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
      '.........kkk.kkk',
      '.........wpk.wpk',
      '.........kbk.kbk',
      '..kkkkk..kbk.kbk',
      '.kssssskk.kbkkbk',
      'kssSSSssk.kbbbbk',
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
    },
    night: {
      'k': Color(0xFFC4A57F),
      'b': Color(0xFFEBCB92),
      's': Color(0xFFA880E8),
      'S': Color(0xFF6C4AC0),
      'w': Color(0xFFFFFFFF),
      'p': Color(0xFF2A1A10),
      'm': Color(0xFFB5703F),
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
    track: Color(0xFFDCE6EE),
    fixedTrack: Color(0xFFA9BDD0),
    wrong: Color(0xFFD32F2F),
    mark: Color(0xFFEBDCC4),
    clue: Color(0xFF3A2616),
  );

  static const SkinColours _night = SkinColours(
    margin: Color(0xFF17110C),
    ground: Color(0xFF3D2E22),
    gridLine: Color(0xFF2B2018),
    track: Color(0xFFB4C4D6),
    fixedTrack: Color(0xFFE4EEF8),
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
    final fill = wrong
        ? colours.wrong
        : (fixed ? colours.fixedTrack : colours.track);
    // A laid trail is wet and see-through, so the soil shows a little; a fixed
    // one is wider, solid and edged, and a wrong one is broken into dashes.
    final opaque = fixed || wrong;
    final bodyColour = opaque ? fill : fill.withAlpha(0xD0);
    final outline = Color.lerp(fill, const Color(0xFF000000), 0.55)!;
    final bodyWidth = u * (fixed ? 0.36 : 0.3);
    final sheen = Color.lerp(fill, const Color(0xFFFFFFFF), 0.8)!;

    final path = wrong ? dashed(centre, u * 0.2, u * 0.09) : centre;
    Paint stroke(Color colour, double width, {bool round = false}) => Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = (round || blob) ? StrokeCap.round : StrokeCap.butt
      ..strokeJoin = StrokeJoin.round;

    if (opaque) {
      canvas.drawPath(path, stroke(outline, bodyWidth + u * 0.09));
    } else {
      // A soft, wider edge of the same slime.
      canvas.drawPath(path, stroke(fill.withAlpha(0x38), bodyWidth + u * 0.1));
    }
    canvas.drawPath(path, stroke(bodyColour, bodyWidth));
    canvas.drawPath(
      path,
      stroke(
        wrong ? fill.withAlpha(0xFF) : sheen.withAlpha(0xE0),
        u * (wrong ? 0.0 : 0.05),
      ),
    );

    if (!wrong) {
      final glint = Paint()..color = const Color(0xF2FFFFFF);
      for (final s in samplesAlong(centre, 2)) {
        final across = Offset(-s.tangent.dy, s.tangent.dx) * (u * 0.07);
        canvas.drawCircle(s.point + across, u * 0.028, glint);
      }
    }

    if (blob) {
      final end = centre.computeMetrics().first.getTangentForOffset(
        centre.computeMetrics().first.length,
      )!;
      final radius = bodyWidth * 0.78;
      if (opaque) {
        canvas.drawCircle(
          end.position,
          radius + u * 0.045,
          Paint()..color = outline,
        );
      }
      canvas.drawCircle(end.position, radius, Paint()..color = bodyColour);
      canvas.drawCircle(
        end.position + Offset(-radius * 0.3, -radius * 0.3),
        radius * 0.32,
        Paint()..color = const Color(0xF2FFFFFF),
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
