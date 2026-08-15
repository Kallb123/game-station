// The one bit of celebration phase 3 ships, and it costs no dependency
// (`PLAN-phase-3.md` §2, §4.6).
//
// A `CustomPainter` over one `AnimationController`: a package would be a
// dependency to carry through every review for two seconds of falling paper,
// and `tool/check_offline.dart` reads the resolved graph, so every package
// added has to be justified against what it drags in (`AGENTS.md`).
//
// **The pieces are laid out by arithmetic rather than by `Random`.** Nothing in
// `lib/` reads ambient randomness (`PLAN-phase-1.md` §1) — the rule is there so
// that no saved identifier and no generated grid can come from one — and a
// scatter derived from each piece's own index keeps this file inside it. It
// also means the same celebration draws the same way twice, which is what makes
// a golden-free widget test of it possible at all.
//
// Sound is phase 5, with the audio layer (`PLAN-phase-3.md` §2).

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// How long the paper takes to fall past the bottom of its box.
///
/// Once, not on a loop: a celebration that never stops is movement in the
/// corner of a child's eye while they read their time.
const Duration confettiDuration = Duration(milliseconds: 2200);

/// How many pieces fall.
const int confettiPieces = 40;

/// Paper falling over whatever it is stacked on.
///
/// Draws nothing at all when `MediaQuery.disableAnimationsOf` is true — which
/// phase 1 already or-ed with the stored *Less moving about* setting
/// (`app.dart`), so a child who asked for less movement is asking this too. Not
/// a slower or shorter version: the setting is a request for stillness, and a
/// static heap of paper over the board is clutter rather than a compromise.
class Confetti extends StatefulWidget {
  /// Falling paper in the colours of [colors], oldest piece first.
  const Confetti({required this.colors, super.key});

  /// The colours the pieces are cut from, cycled through by index.
  final List<Color> colors;

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fall;

  @override
  void initState() {
    super.initState();
    // Built here rather than in a `late final` initialiser: with reduced motion
    // on, nothing reads it until [dispose] does, and a controller built there
    // looks up the `TickerMode` above a widget that is already deactivated.
    _fall = AnimationController(vsync: this, duration: confettiDuration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Started here rather than in [initState] because that is the earliest a
    // `MediaQuery` can be read. A controller that is never started holds no
    // ticker and paints nothing, so reduced motion needs no second mechanism.
    if (!MediaQuery.disableAnimationsOf(context) && _fall.isDismissed) {
      _fall.forward();
    }
  }

  @override
  void dispose() {
    _fall.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return const SizedBox.shrink();

    // Behind whatever is stacked over it and in front of the board, so it never
    // takes a tap meant for the card.
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _fall,
        builder: (context, _) => CustomPaint(
          painter: _ConfettiPainter(
            progress: _fall.value,
            colors: widget.colors,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// One frame of the fall.
class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({required this.progress, required this.colors});

  /// How far through the fall this frame is, from 0 to 1.
  final double progress;

  /// The colours to cut the pieces from.
  final List<Color> colors;

  /// How wide and tall one piece is, in logical pixels.
  static const double _pieceSize = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    for (var piece = 0; piece < confettiPieces; piece++) {
      // Each piece leaves a little after the one before, so the paper arrives
      // as a shower rather than as a single line crossing the screen.
      final start = _scatter(piece, 1) * 0.4;
      final fallen = (progress - start) / (1 - start);
      if (fallen <= 0) continue;

      final x = _scatter(piece, 2) * size.width;
      // Past the bottom edge by one piece, so nothing is left hanging in the
      // last frame.
      final y = fallen * (size.height + _pieceSize) - _pieceSize;
      final spin = _scatter(piece, 3) * math.pi * 8 * fallen;

      paint.color = colors[piece % colors.length].withValues(
        // Fading out over the last third, so the shower ends rather than
        // stopping.
        alpha: fallen > 0.66 ? (1 - fallen) * 3 : 1,
      );

      canvas
        ..save()
        ..translate(x, y)
        ..rotate(spin)
        // Drawn about its own centre, so the spin does not swing the piece
        // across the screen.
        ..drawRect(
          const Rect.fromLTWH(
            -_pieceSize / 2,
            -_pieceSize / 4,
            _pieceSize,
            _pieceSize / 2,
          ),
          paint,
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) =>
      old.progress != progress || old.colors != colors;
}

/// A number from 0 to 1 for [piece]'s [property], stable across frames and
/// across runs.
///
/// A hash rather than a `Random`: the pieces have to land in the same places on
/// every frame of one fall, so each property is a pure function of what it
/// describes. The constants are odd multipliers of a small integer mix — they
/// only have to spread forty inputs across the range, and a bias in them shows
/// up as paper falling in stripes rather than as a bug.
///
/// It works in sixteen bits throughout, so every product stays inside the 2^53
/// a web build's doubles hold exactly — the same reason the engine masks its
/// own arithmetic to 32 bits (`packages/puzzle_engine/lib/src/uint32.dart`).
double _scatter(int piece, int property) {
  var bits = (piece * 0x9E37 + property * 0x85EB) & 0xFFFF;
  bits ^= bits >> 7;
  bits = (bits * 0x2545) & 0xFFFF;
  bits ^= bits >> 9;
  return bits / 0x10000;
}
